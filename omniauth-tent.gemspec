# -*- encoding: utf-8 -*-
lib = File.expand_path('../lib', __FILE__)
$LOAD_PATH.unshift(lib) unless $LOAD_PATH.include?(lib)
require 'omniauth-tent/version'

Gem::Specification.new do |gem|
  gem.name          = "omniauth-tent"
  gem.version       = Omniauth::Tent::VERSION
  gem.authors       = ["Jesse Stuart"]
  gem.email         = ["jessestuart@gmail.com"]
  gem.description   = %q{Omniauth Strategy for Tent}
  gem.summary       = %q{Omniauth Strategy for Tent}
  gem.homepage      = "https://github.com/tent/omniauth-tent"

  gem.files         = `git ls-files`.split($/)
  gem.executables   = gem.files.grep(%r{^bin/}).map{ |f| File.basename(f) }
  gem.test_files    = gem.files.grep(%r{^(test|spec|features)/})
  gem.require_paths = ["lib"]

  gem.add_runtime_dependency 'omniauth', '~> 1.1.1'
  gem.add_runtime_dependency 'tent-client'

  gem.add_development_dependency 'rspec', '~> 2.7'
  gem.add_development_dependency 'rack-test'
  gem.add_development_dependency 'bundler'
  gem.add_development_dependency 'rake'
  gem.add_development_dependency 'kicker'
  gem.add_development_dependency 'mocha'
end
