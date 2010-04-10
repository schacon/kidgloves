require 'rubygems'
require 'rack'
require 'kidgloves'

class HelloWorld
  def call(env)
    [200, {"Content-Type" => "text/html"}, ["Hello world!"]]
  end
end

Rack::Handler::KidGloves.run HelloWorld.new
