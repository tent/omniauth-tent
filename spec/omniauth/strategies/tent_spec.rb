require 'spec_helper'
require 'yajl'
require 'uri'

describe OmniAuth::Strategies::Tent do

  def app
    @app || set_app
  end

  def set_app(strategy_options = {})
    @app = Rack::Builder.app do
      use OmniAuth::Strategies::Tent, strategy_options
      run lambda{|env| [404, {'env' => env}, ["HELLO!"]]}
    end
  end

  let(:entity_uri) { "http://entity.example.org/xfapc" }
  let(:server_url) { "http://tent.example.org/xfapc" }
  let(:server_meta_post_url) { "#{server_url}/posts/meta-post" }
  let(:link_header) {
    %(<#{server_meta_post_url}>; rel="https://tent.io/rels/meta-post")
  }
  let(:meta_post) {
    {
      'entity' => entity_uri,
      'type' => 'https://tent.io/types/meta/v0#',
      'published_at' => (Time.now.to_f * 1000).to_i,
      'content' => {
        "entity" => entity_uri,
        "previous_entities" => [],
        "servers" => [
          {
            "version" => "0.3",
            "urls" => {
              "oauth_auth" => "#{server_url}/oauth/authorize",
              "oauth_token" => "#{server_url}/oauth/token",
              "posts_feed" => "#{server_url}/posts",
              "new_post" => "#{server_url}/posts",
              "post" => "#{server_url}/posts/{entity}/{post}",
              "post_attachment" => "#{server_url}/posts/{entity}/{post}/attachments/{name}?version={version}",
              "batch" => "#{server_url}/batch",
              "server_info" => "#{server_url}/server"
            },
            "preference" => 0
          }
        ]
      }
    }
  }

  let(:app_post_id) { 'app-post-id' }
  let(:app_post) {
    {
      :id => app_post_id,
      :published_at => (Time.now.to_f * 1000).to_i,
      :type => "https://tent.io/types/app/v0#",
      :content => {
        :name => "Example App Name",
        :description => "Example App Description",
        :url => "http://someapp.example.com",
        :redirect_uri => "http://someapp.example.com/oauth/callback",
        :post_types => {
          :read => %w( all ),
          :write => %w( https://tent.io/types/status/v0# )
        },
        :notification_post_types => %w( all ),
        :scopes => %w( import_posts )
      },
      :permissions => {
        :public => false
      }
    }
  }

  let(:app_credentials_post_id) { 'app-credentials-post-id' }
  let(:server_app_credentials_post_url) { "#{server_url}/posts/#{app_credentials_post_id}" }
  let(:app_credentials_post) {
    {
      :id => app_credentials_post_id,
      :published_at => (Time.now.to_f * 1000).to_i,
      :type => "https://tent.io/types/credentials/v0#",
      :content => {
        :hawk_key => 'hawk-mac-key',
        :hawk_algorithm => 'sha256'
      },
      :permissions => {
        :public => false
      }
    }
  }

  let(:app_credentials) {
    app_credentials_post[:content].merge(:hawk_id => app_credentials_post_id)
  }

  let(:access_token_hash) {
    {
      :access_token => 'app-auth-id',
      :hawk_key => 'hawk-mac-key',
      :hawk_algorithm => 'sha256',
      :token_type => 'hawk'
    }
  }

  def server_named_url(name, params = {})
    uri_template = meta_post['content']['servers'].first['urls'][name.to_s]
    uri_template.gsub(/\{([^\}]+)\}/) { URI.encode_www_form_component(params[$1.to_sym]) || "#{$1}" }
  end

  def stub_head_discovery!
    stub_request(:head, entity_uri).to_return(:headers => { 'Link' => link_header })
  end

  def stub_meta_discovery!
    stub_request(:any, server_meta_post_url).to_return(
      :status => 200,
      :headers => {
        'Content-Type' => 'application/json'
      },
      :body => Yajl::Encoder.encode(meta_post)
    )
  end

  def stub_app_create!
    stub_request(:post, server_named_url(:new_post)).to_return(
      :status => 200,
      :headers => {
        'Content-Type' => 'application/json',
        'Link' => %(<#{server_app_credentials_post_url}>; rel="https://tent.io/rels/credentials")
      },
      :body => Yajl::Encoder.encode(app_post)
    )
  end

  def stub_fetch_app!
    stub_request(:get, server_named_url(:post, :entity => entity_uri, :post => app_post_id)).to_return(
      :status => 200,
      :headers => {
        'Content-Type' => 'application/json',
      },
      :body => Yajl::Encoder.encode(app_post)
    )
  end

  def stub_fetch_app_failure!
    stub_request(:get, server_named_url(:post, :entity => entity_uri, :post => app_post_id)).to_return(
      :status => 404,
      :headers => {
        'Content-Type' => 'application/json',
      },
      :body => Yajl::Encoder.encode(:error => 'Not Found')
    )
  end

  def stub_fetch_app_credentials!
    stub_request(:get, server_app_credentials_post_url).to_return(
      :status => 200,
      :headers => {
        'Content-Type' => 'application/json',
      },
      :body => Yajl::Encoder.encode(app_credentials_post)
    )
  end

  def stub_app_auth_create!
    stub_request(:post, server_named_url(:oauth_token)).to_return(
      :status => 200,
      :headers => {
        'Content-Type' => 'application/json'
      },
      :body => Yajl::Encoder.encode(access_token_hash)
    )
  end

  let(:env) { {'rack.session' => {}} }

  let(:app_attrs) do
    {
      :name => app_post[:content][:name],
      :description => app_post[:content][:description],
      :url => app_post[:content][:url],
      :redirect_uri => app_post[:content][:redirect_uri],
      :read_post_types => app_post[:content][:post_types][:read],
      :write_post_types => app_post[:content][:post_types][:write],
      :notification_post_types => app_post[:content][:notification_post_types],
      :notification_url => app_post[:content][:notification_url],
      :scopes => app_post[:content][:scopes],
    }
  end

  describe '#request_phase' do
    it 'displays a form' do
      get '/auth/tent', {}, env
      expect(last_response.body).to be_include("<form")
    end

    it 'performs disvocery' do
      head_stub = stub_head_discovery!
      meta_stub = stub_meta_discovery!

      described_class.any_instance.stubs(:find_or_create_app!)
      described_class.any_instance.stubs(:build_uri_and_redirect!).returns([200, {}, []])

      post '/auth/tent', { :entity => entity_uri }, env

      expect(head_stub).to have_been_requested
      expect(meta_stub).to have_been_requested
    end

    creates_app = proc do
      it 'creates app' do
        stub_head_discovery!
        stub_meta_discovery!
        app_create_stub = stub_app_create!
        fetch_credentials_stub = stub_fetch_app_credentials!

        described_class.any_instance.stubs(:build_uri_and_redirect!).returns([200, {}, []])

        post '/auth/tent', { :entity => entity_uri }, env

        expect(app_create_stub).to have_been_requested
        expect(fetch_credentials_stub).to have_been_requested
      end
    end

    builds_uri_and_redirects = proc do
      it 'builds uri and redirects' do
        stub_head_discovery!
        stub_meta_discovery!
        stub_fetch_app!

        post '/auth/tent', { :entity => entity_uri }, env

        expect(last_response.status).to eq(302)
        expect(last_response.headers["Location"]).to match(%r{\A#{Regexp.escape(server_named_url(:oauth_auth))}})
        expect(last_response.headers["Location"]).to match(%r{client_id=#{app_post_id}})
      end
    end

    context 'when app_id proc returns nil' do
      before do
        set_app(:app => app_attrs)
      end

      context &creates_app
    end

    context 'when app not found' do
      context 'when lookup fails' do
        before do
          set_app(:app => app_attrs, :get_app => lambda { |entity| })
        end

        context &creates_app
      end

      context 'when fetch fails' do
        before do
          set_app(:app => app_attrs, :get_app => lambda { |entity| app_post.merge(:credentials => app_credentials) })
          stub_fetch_app_failure!
        end

        context &creates_app
      end
    end

    context 'when app found' do
      before do
        set_app(:app => app_attrs, :get_app => lambda { |entity| app_post.merge(:credentials => app_credentials) })
      end

      context &builds_uri_and_redirects
    end
  end

  describe "#callback_phase" do
    let(:state) { 'request-state' }
    let(:session) { Hash.new }

    let(:token_code) { 'token-code' }

    before do
      session['omniauth.state'] = state
      session['omniauth.entity'] = entity_uri
      session['omniauth.server'] = meta_post['content']['servers'].first
    end

    it 'creates app authorization' do
      app = app_post.merge(:credentials => app_credentials)
      set_app(:app => app_attrs, :get_app => proc { |e| app })

      stub_head_discovery!
      stub_meta_discovery!
      create_auth_stub = stub_app_auth_create!

      get '/auth/tent/callback', { :code => token_code, :state => state }, 'rack.session' => session

      expect(create_auth_stub).to have_been_requested

      auth_hash = last_response['env']['omniauth.auth']
      expect(auth_hash).to be_kind_of(Hashie::Mash)

      expect(auth_hash.provider).to eql('tent')
      expect(auth_hash.uid).to eql(entity_uri)
      expect(auth_hash.credentials).to eql(Hashie::Mash.new(
        :token => access_token_hash[:access_token],
        :secret => access_token_hash[:hawk_key]
      ))

      expect(auth_hash.extra).to be_kind_of(Hashie::Mash)
      expect(auth_hash.extra.credentials).to eql(Hashie::Mash.new(
        :id => access_token_hash[:access_token],
        :hawk_key => access_token_hash[:hawk_key],
        :hawk_algorithm => access_token_hash[:hawk_algorithm],
        :token_type => access_token_hash[:token_type]
      ))

      expect(auth_hash.extra.raw_info).to be_kind_of(Hashie::Mash)
      expect(auth_hash.extra.raw_info.auth_credentials).to eql(Hashie::Mash.new(access_token_hash))
      expect(auth_hash.extra.raw_info.app).to eql(Hashie::Mash.new(app_post.merge(:credentials => app_credentials)))
    end
  end

  describe "full flow" do
    let(:state) { 'request-state' }
    let(:token_code) { 'token-code' }

    before do
      described_class.any_instance.stubs(:generate_state).returns(state)
    end

    it "maintains state through full oauth flow" do
      app = nil
      set_app(:app => app_attrs, :on_app_created => proc { |a, e| app = a }, :get_app => proc { |e| app })

      ##
      # Request Phase

      stub_head_discovery!
      stub_meta_discovery!
      app_create_stub = stub_app_create!
      fetch_credentials_stub = stub_fetch_app_credentials!

      post '/auth/tent', { :entity => entity_uri }, env

      expect(last_response.status).to eq(302)
      expect(last_response.headers["Location"]).to match(%r{\A#{Regexp.escape(server_named_url(:oauth_auth))}})
      expect(last_response.headers["Location"]).to match(%r{client_id=#{app_post_id}})

      ##
      # Callback Phase

      create_auth_stub = stub_app_auth_create!
      get '/auth/tent/callback', { :code => token_code, :state => state }, env

      expect(create_auth_stub).to have_been_requested

      auth_hash = last_response['env']['omniauth.auth']
      expect(auth_hash).to be_kind_of(Hashie::Mash)

      expect(auth_hash.provider).to eql('tent')
      expect(auth_hash.uid).to eql(entity_uri)
      expect(auth_hash.credentials).to eql(Hashie::Mash.new(
        :token => access_token_hash[:access_token],
        :secret => access_token_hash[:hawk_key]
      ))

      expect(auth_hash.extra).to be_kind_of(Hashie::Mash)
      expect(auth_hash.extra.credentials).to eql(Hashie::Mash.new(
        :id => access_token_hash[:access_token],
        :hawk_key => access_token_hash[:hawk_key],
        :hawk_algorithm => access_token_hash[:hawk_algorithm],
        :token_type => access_token_hash[:token_type]
      ))

      expect(auth_hash.extra.raw_info).to be_kind_of(Hashie::Mash)
      expect(auth_hash.extra.raw_info.auth_credentials).to eql(Hashie::Mash.new(access_token_hash))
      expect(auth_hash.extra.raw_info.app).to eql(Hashie::Mash.new(app_post.merge(:credentials => app_credentials)))
    end
  end
end
