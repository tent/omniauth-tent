require 'spec_helper'

describe OmniAuth::Strategies::Tent do
  attr_accessor :app

  # customize rack app for testing, if block is given, reverts to default
  # rack app after testing is done
  def set_app!(tent_options = {})
    old_app = self.app
    self.app = Rack::Builder.app do
      use Rack::Session::Cookie
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

  let(:fresh_strategy){ Class.new(OmniAuth::Strategies::Tent) }

  let(:tent_entity) { 'https://example.com' }
  let(:tent_server) { "#{tent_entity}/tent" }
  let(:link_header) { %(<#{tent_server}/profile>; rel="%s") % TentClient::PROFILE_REL }
  let(:tent_profile) { %({"https://tent.io/types/info/core/v0.1.0":{"licenses":["http://creativecommons.org/licenses/by/3.0/"],"entity":"#{tent_entity}","servers":["#{tent_server}"]}}) }

  describe '#request_phase' do
    it 'should display a form' do
      get '/auth/tent'
      expect(last_response.body).to be_include("<form")
    end

    it 'should perform disvocery' do
      head_stub = stub_request(:head, tent_entity).to_return(:headers => {'Link' => link_header})
      profile_stub = stub_request(:get, "#{tent_server}/profile").to_return(:body => tent_profile, :headers => {'Content-Type' => TentClient::MEDIA_TYPE})

      post '/auth/tent', :entity => tent_entity
      expect(last_response.status).to eq(200)

      expect(head_stub).to have_been_requested
      expect(profile_stub).to have_been_requested
    end
  end
end
