$LOAD_PATH.unshift(File.dirname(__FILE__))
$LOAD_PATH.unshift(File.join(File.dirname(__FILE__), '..', 'lib'))

require 'bundler/setup'
require 'mocha/api'
require 'rack/test'
require 'webmock/rspec'
require 'omniauth-tent'

Dir["#{File.dirname(__FILE__)}/support/*.rb"].each { |f| require f }

RSpec.configure do |config|
  config.color = true
  config.include WebMock::API
  config.include Rack::Test::Methods
  config.extend  OmniAuth::Test::StrategyMacros, :type => :strategy
  config.mock_with :mocha
  config.expect_with :rspec do |c|
    c.syntax = :expect
  end
end

OmniAuth.config.logger = Logger.new("/dev/null")
