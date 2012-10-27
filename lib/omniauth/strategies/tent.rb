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
      StateMissmatchError = Class.new(Error)

      option :get_app, lambda { |entity| }
      option :on_app_created, lambda { |app, entity| }
      option :app, { :name => nil, :icon => nil, :description => nil, :scopes => {}, :redirect_uris => nil }
      option :profile_info_types, []
      option :post_types, []
      option :notification_url, ""

      def request_params
        Hashie::Mash.new(request.params)
      end

      def request_phase
        if request.post? && request_params.entity
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
        fail!(:app_create_failure, e)
      rescue AppLookupFailure => e
        fail!(:app_lookup_failure, e)
      rescue => e
        fail!(:unknown_error, e)
      end

      def callback_phase
        verify_state!
        create_app_authorization!
        build_auth_hash!
        delete_state!
        call_app!
      rescue AppAuthorizationCreateFailure => e
        fail!(:app_auth_create_failure, e)
      rescue StateMissmatchError => e
        fail!(:state_missmatch, e) 
      rescue => e
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
        session["omniauth.#{key}"] = val
        val
      end

      def get_state(key)
        session["omniauth.#{key}"]
      end

      def perform_discovery!
        client = ::TentClient.new
        @profile, @server_url = client.discover(get_state(:entity)).get_profile
        set_state(:server_url, @server_url)
        set_state(:profile, @profile)
      end

      def find_or_create_app!
        app = Hashie::Mash.new(options[:get_app].call(get_state(:entity)) || {})
        client = ::TentClient.new(get_state(:server_url), :mac_key_id => app[:mac_key_id],
                                                          :mac_key => app[:mac_key],
                                                          :mac_algorithm => app[:mac_algorithm])
        if app[:id]
          res = client.app.get(app[:id])
          if res.body.kind_of?(::String)
            if ((400...500).to_a - [404]).include?(res.status)
              create_app and return
            else
              raise AppLookupFailure.new(res.inspect)
            end
          else
            set_app(app)
          end
        else
          create_app
        end
      end

      def set_app(app)
        set_state(:app, app)
      end

      def get_app
        @tent_app ||= Hashie::Mash.new(get_state(:app) || {})
      end

      def create_app
        client = ::TentClient.new(@server_url)
        app_attrs = {
          :name => options.app.name,
          :description => options.app.description,
          :scopes => options.app.scopes,
          :icon => options.app.icon,
          :url => options.app.url,
          :redirect_uris => options.app.redirect_uris || [callback_url]
        }

        res = client.app.create(app_attrs)

        if (app = res.body) && !app.kind_of?(::String)
          set_app(app)
          options[:on_app_created].call(get_app, get_state(:entity))
        else
          raise AppCreateFailure.new(res.inspect)
        end
      end

      def build_uri_and_redirect!
        auth_uri = URI(@server_url + '/oauth/authorize')
        params = {
          :client_id => get_app[:id],
          :tent_profile_info_types => options[:profile_info_types].join(','),
          :tent_post_types => options[:post_types].join(','),
          :tent_notification_url => options[:notification_url],
          :scope => options[:app][:scopes].keys.join(','),
          :redirect_uri => callback_url,
        }
        params[:state] = set_state(:state, SecureRandom.hex(32))
        build_uri_params!(auth_uri, params)

        redirect auth_uri.to_s
      end

      def build_uri_params!(uri, params)
        uri.query = params.inject([]) do |memo, (key,val)|
          memo << "#{key}=#{URI.encode_www_form_component(val)}"
          memo
        end.join('&')
      end

      def verify_state!
        raise StateMissmatchError unless get_state(:state) == request.params['state']
      end

      def create_app_authorization!
        client = ::TentClient.new(get_state(:server_url), :mac_key_id => get_app[:mac_key_id],
                                                          :mac_key => get_app[:mac_key],
                                                          :mac_algorithm => get_app[:mac_algorithm])
        res = client.app.authorization.create(get_app[:id], :code => request.params['code'])
        raise AppAuthorizationCreateFailure.new(res.body) if res.body.kind_of?(String)
        @app_authorization = Hashie::Mash.new(res.body)
      end

      def build_auth_hash!
        env['omniauth.auth'] = Hashie::Mash.new(
          :provider => 'tent',
          :uid => get_state(:entity),
          :info => extract_basic_info(get_state(:profile)),
          :credentials => {
            :token => @app_authorization.access_token,
            :secret => @app_authorization.mac_key
          },
          :extra => {
            :raw_info => {
              :profile => get_state(:profile),
              :app_authorization => @app_authorization,
              :app => get_app
            },
            :credentials => {
              :mac_key_id => @app_authorization.access_token,
              :mac_key => @app_authorization.mac_key,
              :mac_algorithm => @app_authorization.mac_algorithm,
              :token_type => @app_authorization.token_type
            }
          }
        )
      end

      def delete_state!
        %w( entity app server_url profile state ).each do |key|
          session.delete("omniauth.#{key}")
        end
      end

      def extract_basic_info(profile)
        basic_info = Hashie::Mash.new(profile.inject({}) { |memo, (k,v)|
          memo = v if k =~ %r{^https://tent.io/types/info/basic}
          memo
        })

        {
          :name => basic_info.name,
          :nickname => get_state(:entity),
          :image => basic_info.avatar
        }
      end
    end
  end
end
