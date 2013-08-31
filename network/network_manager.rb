require 'sinatra'
require 'rack-flash'
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

  Sass::Plugin.options[:style] = :compressed
  use Sass::Plugin::Rack

  use Rack::Flash

  set :redis,      Redis.new(settings.app_config["redis"])
  set :redis_sub,  Redis.new(settings.app_config["redis"])
  set :key_prefix, settings.app_config["redis"]["key_prefix"]

  # if they don't exist already, the custom sass files should be initialized
  if Dir[File.join(settings.public_folder, "stylesheets/sass/custom/main.{sass,scss}")].empty?
    File.open(File.join(settings.public_folder, "stylesheets/sass/custom/main.sass"), "w") do |f|
      f.puts "// Put your custom styles in here."
    end
  end
  if Dir[File.join(settings.public_folder, "stylesheets/sass/custom/_variables.{sass,scss}")].empty?
    File.open(File.join(settings.public_folder, "stylesheets/sass/custom/_variables.sass"), "w") do |f|
      f.puts "// Put your custom variables in here."
    end
  end
end

require_relative 'models/user'
require_relative 'models/client'

require_relative 'helpers/user'
require_relative 'helpers/client'
require_relative 'helpers/nav'
require_relative 'helpers/ui'

configure do
  User.redis        = settings.redis
  User.key_prefix   = settings.key_prefix

  Client.redis      = settings.redis
  Client.key_prefix = settings.key_prefix
end

require_relative 'controllers/index'
require_relative 'controllers/session'
require_relative 'controllers/user'
require_relative 'controllers/client'

not_found do
  haml :not_found
end
