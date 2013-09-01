require 'fileutils'
require 'json'
require 'rack/utils'
require 'sinatra'
require 'sinatra/streaming'
require 'haml'
require 'sass'
require 'sass/plugin/rack'
require 'sequel'
require 'yaml'

DEFAULT_CONFIG = {
  "database" => "sqlite://subscriber.db",
  "data_dir" => "data"
}

configure do
  set :app_config, DEFAULT_CONFIG.merge(YAML.load_file("subscriber.yaml")) rescue DEFAULT_CONFIG

  set :db, Sequel.connect(settings.app_config["database"])

  Sass::Plugin.options[:style] = :compressed
  use Sass::Plugin::Rack
end

helpers do
  include Rack::Utils
end

require_relative 'models/task'
require_relative 'models/job'

Task.data_dir = settings.app_config["data_dir"]

require_relative 'controllers/index'
require_relative 'controllers/task'
