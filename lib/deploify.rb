unless Capistrano::Configuration.respond_to?(:instance)
  abort "Deploify requires Capistrano ~> 2.13.5"
end

require "#{File.dirname(__FILE__)}/deploify/capistrano_extensions"
require "#{File.dirname(__FILE__)}/plugins/all"
require "#{File.dirname(__FILE__)}/deploify/recipes"
