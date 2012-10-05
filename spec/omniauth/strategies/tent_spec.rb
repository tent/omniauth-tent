require 'spec_helper'
require 'yajl'

describe OmniAuth::Strategies::Tent do
  attr_accessor :app

  # customize rack app for testing, if block is given, reverts to default
  # rack app after testing is done
  def set_app!(tent_options = {})
    old_app = self.app
    self.app = Rack::Builder.app do
      use OmniAuth::Strategies::Tent, tent_options
      run lambda{|env| [404, {'env' => env}, ["HELLO!"]]}
    end
    if block_given?
      yield
      self.app = old_app
    end
    self.app
  end

  before(:all) do
    set_app!
  end

  let(:env) { {'rack.session' => {}} }

  let(:fresh_strategy){ Class.new(OmniAuth::Strategies::Tent) }

  let(:tent_entity) { 'https://example.com' }
  let(:tent_server) { "#{tent_entity}/tent" }
  let(:app_id) { 'app-id-123' }
  let(:link_header) { %(<#{tent_server}/profile>; rel="%s") % TentClient::PROFILE_REL }
  let(:tent_profile) { %({"https://tent.io/types/info/core/v0.1.0":{"licenses":["http://creativecommons.org/licenses/by/3.0/"],"entity":"#{tent_entity}","servers":["#{tent_server}"]}}) }
  let(:app_attrs) do
    {
      :name => "Example App",
      :description => "An example app",
      :scopes => { "read_posts" => "Display your posts feed" },
      :icon => "https://example.com/icon.png",
      :url => "https://example.com"
    }
  end
  let(:app_json) { %({"name":"Example App","id":"#{app_id}"}) }
  let(:app_hash) { Yajl::Parser.parse(app_json) }

  let(:token_code) { 'token-code-123abc' }

  let(:access_token) { 'access-token-abc' }
  let(:mac_key) { 'mac-key-312' }
  let(:mac_algorithm) { 'hmac-sha-256' }
  let(:token_type) { 'mac' }
  let(:app_auth_json) { %({"access_token":"#{access_token}","mac_key":"#{mac_key}","mac_algorithm":"#{mac_algorithm}","token_type":"#{token_type}") }

  let(:stub_head_discovery!) do
    stub_request(:head, tent_entity).to_return(:headers => {'Link' => link_header})
  end

  let(:stub_profile_discovery!) do
    stub_request(:get, "#{tent_server}/profile").to_return(:body => tent_profile, :headers => {'Content-Type' => TentClient::MEDIA_TYPE})
  end

  let(:stub_app_lookup_success!) do
    stub_request(:get, "#{tent_server}/apps/#{app_id}").to_return(:body => app_json, :headers => { 'Content-Type' => TentClient::MEDIA_TYPE })
  end

  let(:stub_app_lookup_failure!) do
    stub_request(:get, "#{tent_server}/apps/#{app_id}").to_return(:status => 404)
  end

  let(:stub_app_create_success!) do
    stub_request(:post, "#{tent_server}/apps").to_return(:body => app_json, :headers => { 'Content-Type' => TentClient::MEDIA_TYPE })
  end

  let(:stub_app_auth_create_success!) do
    stub_request(:post, "#{tent_server}/apps/#{app_id}/authorizations").with(:body => Yajl::Encoder.encode({ :code => token_code })).to_return(:body => app_auth_json, :headers => { 'Content-Type' => TentClient::MEDIA_TYPE })
  end

  describe '#request_phase' do
    it 'should display a form' do
      get '/auth/tent', {}, env
      expect(last_response.body).to be_include("<form")
    end

    it 'should perform disvocery' do
      head_stub = stub_head_discovery!
      profile_stub = stub_profile_discovery!

      described_class.any_instance.stubs(:find_or_create_app!)
      described_class.any_instance.stubs(:build_uri_and_redirect!).returns([200, {}, []])

      post '/auth/tent', { :entity => tent_entity }, env

      expect(head_stub).to have_been_requested
      expect(profile_stub).to have_been_requested
    end

    it 'should create app if app_id callback returns nil' do
      set_app!(:app => app_attrs)
      stub_head_discovery!
      stub_profile_discovery!
      app_create_stub = stub_app_create_success!
      described_class.any_instance.stubs(:build_uri_and_redirect!).returns([200, {}, []])

      post '/auth/tent', { :entity => tent_entity }, env

      expect(app_create_stub).to have_been_requested
    end

    it 'should create app if not found' do
      set_app!(:app => app_attrs, :on_app_created => mock(:call))
      stub_head_discovery!
      stub_profile_discovery!
      stub_app_lookup_failure!
      app_create_stub = stub_app_create_success!
      described_class.any_instance.stubs(:build_uri_and_redirect!).returns([200, {}, []])

      post '/auth/tent', { :entity => tent_entity }, env

      expect(app_create_stub).to have_been_requested
    end

    it 'should build uri and redirect' do
      set_app!(:get_app => lambda { |entity| app_hash })
      stub_head_discovery!
      stub_profile_discovery!
      stub_app_lookup_success!

      post '/auth/tent', { :entity => tent_entity }, env

      expect(last_response.status).to eq(302)
      expect(last_response.headers["Location"]).to match(%r{^#{tent_server}/oauth/authorize})
      expect(last_response.headers["Location"]).to match(%r{client_id=#{app_id}})
    end
  end

  describe '#callback_phase' do
    it 'should create app authorization' do
      state = 'abcdef'
      session = {}
      session['omniauth.state'] = state
      session['omniauth.entity'] = tent_entity
      session['omniauth.server_url'] = tent_server
      session['omniauth.app'] = { :id => app_id }
      session['omniauth.profile'] = Yajl::Parser.parse(tent_profile)

      stub_app_auth_create_success!
      stub_app_lookup_success!

      get '/auth/tent/callback', { :code => token_code, :state => state }, 'rack.session' => session

      auth_hash = last_response['env']['omniauth.auth_hash']
      expect(auth_hash).to_not be_nil
      expect(auth_hash.provider).to eq('tent')
      expect(auth_hash.uid).to eq(tent_entity)
      expect(auth_hash.info).to eq(Hashie::Mash.new(
        :name => nil,
        :nickname => tent_entity,
        :image => nil
      ))
      expect(auth_hash.credentials).to eq(Hashie::Mash.new(
        :token => access_token,
        :secret => mac_key
      ))
      expect(auth_hash.extra.raw_info.profile).to eq(Hashie::Mash.new(Yajl::Parser.parse(tent_profile)))
      expect(auth_hash.extra.credentials).to eq(Hashie::Mash.new(
        :mac_key_id => access_token,
        :mac_key => mac_key,
        :mac_algorithm => mac_algorithm,
        :token_type => token_type
      ))
      expect(auth_hash.extra.raw_info.app_authorization).to eq(Hashie::Mash.new(
        Yajl::Parser.parse(app_auth_json)
      ))
    end
  end
end
