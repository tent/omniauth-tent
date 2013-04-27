require 'omniauth'
require 'tent-client'
require 'uri'
require 'securerandom'

module OmniAuth
  module Strategies
    class Tent
      include OmniAuth::Strategy

      Error = Class.new(StandardError)
      AppCreateFailure = Class.new(Error)
      AppLookupFailure = Class.new(Error)
      AppAuthorizationCreateFailure = Class.new(Error)
      DiscoveryFailure = Class.new(Error)
      StateMissmatchError = Class.new(Error)
      InvalidAppError = Class.new(Error)
      OAuthError = Class.new(Error)

      option :get_app, lambda { |entity| }
      option :on_app_created, lambda { |app, entity| }

      option :app, {
        :name => nil,
        :description => nil,
        :url => nil,
        :redirect_uri => nil,
        :read_post_types => [],
        :write_post_types => [],
        :notification_post_types => [],
        :notification_url => nil,
        :scopes => [],
        :icon => nil
      }

      def request_params
        Hashie::Mash.new(request.params)
      end

      def request_phase
        if request.post?
          raise DiscoveryFailure.new("No entity given!") unless request_params.entity

          delete_state!
          set_state(:entity, ensure_entity_has_scheme(request_params.entity))
          perform_discovery!
          find_or_create_app!
          build_uri_and_redirect!
        else
          OmniAuth::Form.build(
            :title => (options[:title] || "Entity Verification")
          ) do |f|
            f.text_field 'Entity', 'entity'
          end.to_response
        end
      rescue AppCreateFailure => e
        delete_state!
        fail!(:app_create_failure, e)
      rescue AppLookupFailure => e
        delete_state!
        fail!(:app_lookup_failure, e)
      rescue InvalidAppError => e
        delete_state!
        fail!(:invalid_app, e)
      rescue DiscoveryFailure => e
        delete_state!
        fail!(:discovery_failure, e)
      rescue => e
        delete_state!
        fail!(:unknown_error, e)
      end

      def callback_phase
        check_error!
        verify_state!
        token_exchange!
        build_auth_hash!
        delete_state!
        call_app!
      rescue AppAuthorizationCreateFailure => e
        delete_state!
        fail!(:app_auth_create_failure, e)
      rescue StateMissmatchError => e
        delete_state!
        fail!(:state_missmatch, e) 
      rescue => e
        delete_state!
        fail!(:unknown_error, e)
      end

      private

      def ensure_entity_has_scheme(entity_uri)
        if entity_uri =~ %r{^[a-z]{3,}?://}
          entity_uri
        else
          "https://#{entity_uri}"
        end
      end

      def set_state(key, val)
        (session["omniauth.tent-keys"] ||= []) << key unless session["omniauth.tent-keys"].to_a.include?(key)
        session["omniauth.#{key}"] = val
        val
      end

      def get_state(key)
        session["omniauth.#{key}"]
      end

      def perform_discovery!
        client = ::TentClient.new(get_state(:entity))
        unless @server_meta = client.server_meta_post
          raise DiscoveryFailure.new("Failed to perform discovery on #{get_state(:entity).inspect}")
        end
      end

      def validate_app!(app)
        unless Hash === app
          raise InvalidAppError.new("Expected app to be a hash, got instance of #{app.class.name}")
        end

        expected_attributes = [:id, :credentials]
        if expected_attributes.any? { |key| !app.has_key?(key) }
          raise InvalidAppError.new("Expected app to have #{expected_attributes.map(&:inspect).join(', ')}, got #{app.keys.map(&:inspect).join(', ')}")
        end
      end

      def find_or_create_app!
        app = options[:get_app].call(get_state(:entity))
        app = Hashie::Mash.new(app) if Hash === app

        if app
          validate_app!(app)

          ##
          # Check if app exists, if not create a new one

          app_credentials = {
            :id => app[:credentials][:hawk_id],
            :hawk_key => app[:credentials][:hawk_key],
            :hawk_algorithm => app[:credentials][:hawk_algorithm]
          }
          client = ::TentClient.new(get_state(:entity), :credentials => app_credentials, :server_meta => @server_meta)

          res = client.post.get(get_state(:entity), app[:id])

          if res.success?
            set_app(app)
            set_server(res.env[:tent_server])
          else
            if (400...500).include?(res.status)
              create_app and return
            else
              raise AppLookupFailure.new(res.inspect)
            end
          end
        else
          create_app
        end
      end

      def set_server(server)
        server['urls'].delete_if { |k,v| k !~ /\Aoauth/ }
        set_state(:server, server)
        @server = server
      end

      def get_server
        @server ||= get_state(:server)
      end

      def set_app(app)
        @tent_app = Hashie::Mash.new(app)
      end

      def get_app
        @tent_app || set_app(options[:get_app].call(get_state(:entity)))
      end

      def create_app
        client = ::TentClient.new(get_state(:entity), :server_meta => @server_meta)

        app_attrs = {
          :type => "https://tent.io/types/app/v0#",
          :content => {
            :name => options[:app][:name],
            :description => options[:app][:description],
            :url => options[:app][:url],
            :redirect_uri => options[:app][:redirect_uri],
            :post_types => {
              :read => options[:app][:read_post_types],
              :write => options[:app][:write_post_types]
            },
            :notification_url => options[:app][:notification_url],
            :notification_post_types => options[:app][:notification_post_types],
            :scopes => options[:app][:scopes]
          },
          :permissions => {
            :public => false
          }
        }

        app_icon_attrs = if options[:app][:icon]
          if Hash === options[:app][:icon]
            options[:app][:icon]
          elsif options[:app][:icon].respond_to?(:path)
            # Assume IO
            filename = options[:app][:icon].path.to_s.split('/').last || 'appicon.png'
            {
              :content_type => "image/#{filename.split('.').last || 'png'}",
              :category => 'icon',
              :name => filename,
              :data => options[:app][:icon]
            }
          elsif String === options[:app][:icon]
            {
              :content_type => "image/png",
              :category => 'icon',
              :name => "appicon.png",
              :data => options[:app][:icon]
            }
          end
        end
        attachments = [app_icon_attrs].compact

        res = client.post.create(app_attrs, {}, :attachments => attachments)

        if res.success? && (Hash === res.body)
          app = res.body
          credentials_post_link = ::TentClient::LinkHeader.parse(res.env[:response_headers]['Link'].to_s).links.find { |l| l[:rel] == 'https://tent.io/rels/credentials' }

          if credentials_post_link && (credentials_post_res = client.http.get(credentials_post_link.uri.to_s)) && credentials_post_res.success?
            credentials_post = Hashie::Mash.new(credentials_post_res.body)
            set_app(app.merge(:credentials => {
              :hawk_id => credentials_post.id,
              :hawk_key => credentials_post.content.hawk_key,
              :hawk_algorithm => credentials_post.content.hawk_algorithm
            }))
            options[:on_app_created].call(get_app, get_state(:entity))
          else
            raise AppLookupFailure.new("Failed to fetch app credentials!")
          end

          set_server(res.env[:tent_server])
        else
          raise AppCreateFailure.new(res.inspect)
        end
      end

      def generate_state
        SecureRandom.hex(32)
      end

      def build_uri_and_redirect!
        auth_uri = URI(get_server['urls']['oauth_auth'])

        params = {
          :client_id => get_app[:id],
        }
        params[:state] = set_state(:state, generate_state)

        auth_uri.query = build_query_string(params)

        redirect auth_uri.to_s
      end

      def build_query_string(params)
        params.inject([]) do |memo, (key,val)|
          memo << "#{key}=#{URI.encode_www_form_component(val)}"
          memo
        end.join('&')
      end

      def check_error!
        if request_params['error']
          raise OAuthError.new(request_params['error'])
        end
      end

      def verify_state!
        raise StateMissmatchError.new("Expected #{get_state(:state).inspect}, got #{request.params['state'].inspect}") unless get_state(:state) == request.params['state']
      end

      def token_exchange!
        app_credentials = get_app[:credentials].dup
        app_credentials.merge!(:id => app_credentials.delete(:hawk_id))
        client = ::TentClient.new(get_state(:entity), :credentials => app_credentials)
        client.server_meta['servers'] = [get_server]

        res = client.oauth_token_exchange(:code => request.params['code'], :token_type => 'https://tent.io/oauth/hawk-token')

        raise AppAuthorizationCreateFailure.new(res.body) unless res.success?
        @auth_credentials = Hashie::Mash.new(res.body)
      end

      def build_auth_hash!
        env['omniauth.auth'] = Hashie::Mash.new(
          :provider => 'tent',
          :uid => get_state(:entity),
          :credentials => {
            :token => @auth_credentials.access_token,
            :secret => @auth_credentials.hawk_key
          },
          :extra => {
            :raw_info => {
              :auth_credentials => @auth_credentials,
              :app => get_app
            },
            :credentials => {
              :id => @auth_credentials.access_token,
              :hawk_key => @auth_credentials.hawk_key,
              :hawk_algorithm => @auth_credentials.hawk_algorithm,
              :token_type => @auth_credentials.token_type
            }
          }
        )
      end

      def delete_state!
        session.delete('omniauth.tent-keys').to_a.each do |key|
          session.delete("omniauth.#{key}")
        end
      end
    end
  end
end
