require 'sinatra'
require 'redis'
require 'openssl'
require 'bcrypt'
require 'json'
require 'cgi'
require 'haml'
require 'sass'
require 'sass/plugin/rack'
require 'yaml'

DEFAULT_CONFIG = {
  "name" => "mynetwork",
  "cookie_secret" => rand(36**36).to_s(36),
  "private" => false,
  "redis" => {
    "host" => "localhost",
    "port" => 6379,
    "key_prefix" => "maru.network.mynetwork."
  }
}

Sass::Plugin.options[:style] = :compressed
use Sass::Plugin::Rack

helpers do
  include Rack::Utils
end

configure do
  # Create default config file if it doesn't exist
  unless File.file? "network_manager.yaml"
    File.open("network_manager.yaml", "w") do |f|
      YAML.dump(DEFAULT_CONFIG, f)
    end rescue nil
  end

  set :app_config, (DEFAULT_CONFIG.merge(YAML.load_file("network_manager.yaml")) rescue DEFAULT_CONFIG)

  use Rack::Session::Cookie, :secret => settings.app_config["cookie_secret"]

  set :redis,      Redis.new(settings.app_config["redis"])
  set :redis_sub,  Redis.new(settings.app_config["redis"])
  set :key_prefix, settings.app_config["redis"]["key_prefix"]
end

require_relative 'models/user'
require_relative 'models/client'

require_relative 'helpers/user'
require_relative 'helpers/nav'

configure do
  User.redis        = settings.redis
  User.key_prefix   = settings.key_prefix

  Client.redis      = settings.redis
  Client.key_prefix = settings.key_prefix
end

require_relative 'controllers/index'
require_relative 'controllers/session'
require_relative 'controllers/user'

not_found do
  haml :not_found
end
