# -*- encoding: utf-8 -*-
lib = File.expand_path('../lib', __FILE__)
$LOAD_PATH.unshift(lib) unless $LOAD_PATH.include?(lib)
require 'deploify/version'

Gem::Specification.new do |gem|
  gem.name          = "deploify"
  gem.version       = Deploify::VERSION
  gem.authors       = ["Richard Riman"]
  gem.email         = ["riman.richard@gmail.com"]
  gem.description   = "deploify - capistrano based and deprec inspired deploy solution served as a gem"
  gem.summary       = "capistrano based and deprec inspired deploy gem"
  gem.homepage      = "https://github.com/richardriman/deploify"

  gem.required_ruby_version = ">= 1.8.7"

  gem.add_dependency "bundler", ">= 1.0.21"
  gem.add_dependency "capistrano", "~> 2.13.5"
  gem.add_dependency "rvm-capistrano", "~> 1.2.7"

  gem.add_development_dependency "bundler", ">= 1.0.21"
  gem.add_development_dependency "capistrano", "~> 2.13.5"
  gem.add_development_dependency "rvm-capistrano", "~> 1.2.7"

  gem.files         = `git ls-files`.split($/)
  gem.executables   = gem.files.grep(%r{^bin/}).map{ |f| File.basename(f) }
  gem.test_files    = gem.files.grep(%r{^(test|spec|features)/})
  gem.require_paths = ["lib"]
end
