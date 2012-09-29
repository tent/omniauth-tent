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

      option :get_app_id, lambda { |entity| }
      option :on_app_created, lambda { |app| }
      option :app, { :name => nil, :icon => nil, :description => nil, :scopes => {}, :redirect_uris => nil }
      option :profile_info_types, []
      option :post_types, []
      option :notification_url, ""

      def request_params
        Hashie::Mash.new(request.params)
      end

      def request_phase
        if request.post? && request_params.entity
          set_state(:entity, request_params.entity)
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
      end

      def callback_phase
        verify_state!
        create_app_authorization!
        build_auth_hash!
        call_app!
      end

      private

      def set_state(key, val)
        session["omniauth.#{key}"] = val
        val
      end

      def get_state(key)
        session["omniauth.#{key}"]
      end

      def perform_discovery!
        client = ::TentClient.new
        @profile, @server_url = client.discover(request[:entity]).get_profile
        set_state(:server_url, @server_url)
        set_state(:profile, @profile)
      end

      def find_or_create_app!
        app_id = options[:get_app_id].call(get_state(:entity))
        app_id ? lookup_app(app_id) : create_app
      end

      def lookup_app(app_id)
        client = ::TentClient.new(@server_url)
        app = client.app.get(app_id).body
        if app && !app.kind_of?(::String)
          @tent_app = Hashie::Mash.new(app)
          set_state(:app_id, @tent_app.id)
        else
          create_app
        end
      end

      def create_app
        client = ::TentClient.new(@server_url)
        res = client.app.create(
          :name => options.app.name,
          :description => options.app.description,
          :scopes => options.app.scopes,
          :icon => options.app.icon,
          :url => options.app.url,
          :redirect_uris => options.app.redirect_uris || [callback_url]
        )

        if (app = res.body) && !app.kind_of?(::String)
          @tent_app = Hashie::Mash.new(app)
          options[:on_app_created].call(@tent_app)
          set_state(:app_id, @tent_app.id)
        else
          fail!(:app_create_failure, AppCreateFailure.new(res.body))
        end
      end

      def build_uri_and_redirect!
        auth_uri = URI(@server_url + '/oauth/authorize')
        params = {
          :client_id => @tent_app.id,
          :tent_profile_info_types => options[:profile_info_types].join(','),
          :tent_post_types => options[:post_types].join(','),
          :tent_notification_url => options[:notification_url],
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
        fail!(:state_missmatch) unless get_state(:state) == request.params['state']
      end

      def create_app_authorization!
        client = ::TentClient.new(get_state(:server_url))
        res = client.app.authorization.create(get_state(:app_id), :code => request.params['code'])
        fail!(:app_creation_failure) if res.body.kind_of?(::String)
        @app_authorization = Hashie::Mash.new(res.body)
      end

      def get_app
        client = ::TentClient.new(get_state(:server_url), {
          :mac_key_id => @app_authorization.access_token,
          :mac_key => @app_authorization.mac_key,
          :mac_algorithm => @app_authorization.mac_algorithm
        })

        client.app.get(get_state(:app_id)).body
      end

      def build_auth_hash!
        env['omniauth.auth_hash'] = Hashie::Mash.new(
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
