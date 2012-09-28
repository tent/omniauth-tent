$LOAD_PATH.unshift(File.dirname(__FILE__))
$LOAD_PATH.unshift(File.join(File.dirname(__FILE__), '..', 'lib'))

require 'bundler/setup'
require 'mocha_standalone'
require 'rack/test'
require 'omniauth-tent'

Dir["#{File.dirname(__FILE__)}/support/*.rb"].each { |f| require f }

RSpec.configure do |config|
  config.include Rack::Test::Methods
  config.extend  OmniAuth::Test::StrategyMacros, :type => :strategy
  config.mock_with :mocha
end
