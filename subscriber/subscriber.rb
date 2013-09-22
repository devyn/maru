#!/usr/bin/env ruby

$:.unshift(File.join(File.dirname(__FILE__), "../lib"))

require 'fileutils'
require 'json'
require 'rack/utils'
require 'sinatra/base'
require 'sinatra/streaming'
require 'haml'
require 'sass'
require 'sass/plugin/rack'
require 'sequel'
require 'yaml'

require 'maru/version'

module Maru
  class Subscriber < Sinatra::Application
    DEFAULT_CONFIG = {
      "host"        => "localhost",
      "port"        => 8421,
      "environment" => "development",
      "database"    => "sqlite://subscriber.db",
      "data_dir"    => "data",
      "plugin_path" => File.expand_path(File.join(File.dirname(__FILE__), "plugins")),
      "plugins"     => [],
      "producer"    => {
        "networks"  => []
      }
    }

    set :app_config, DEFAULT_CONFIG.dup
    set :server, :thin

    # Configure from command line if we are run directly
    if __FILE__ == $0
      require 'optparse'

      d      = lambda { |option| DEFAULT_CONFIG[option.to_s] }
      config = settings.app_config

      config['plugins'] = [] # or else we'd overwrite DEFAULT_CONFIG, not that it matters

      OptionParser.new { |op|
        op.on('-c', '--config FILE', "Load YAML configuration from FILE") { |file|
          y = YAML.load_file(file)

          if !y["secret"]
            # Generate a random secret for now, and warn the user.
            # The random secret is 48 bytes of random Base64.
            y["secret"] = [48.times.map{rand(64)}.pack("C*")].pack("m").gsub("\n", "")

            $stderr.puts "@" * 40
            $stderr.puts "Warning: You have not set a 'secret' in the configuration file."
            $stderr.puts "This is necessary for the application to be secure."
            $stderr.puts "Please add the following to `#{file}':"
            $stderr.puts
            $stderr.puts "secret: #{y["secret"].to_json}"
            $stderr.puts
            $stderr.puts "@" * 40
          end

          config.update(y)
        }
        op.on('--write-config FILE', "Write YAML configuration from options to FILE and exit") { |file|
          File.open file, 'w' do |f|
            c = config.dup

            # Add a random secret to the output
            c["secret"] = [48.times.map{rand(64)}.pack("C*")].pack("m").gsub("\n", "")

            YAML.dump c, f
          end
          exit
        }

        op.on('-H', '--host IP', "Set address to bind to (default: #{d[:host]})") { |host|
          config['host'] = host
        }
        op.on('-P', '--port NUMBER', "Set port to bind to (default: #{d[:port]})") { |port|
          config['port'] = port.to_i
        }
        op.on('-E', '--environment {development,production}', "Set rack environment (default: #{d[:environment]})") { |env|
          config['environment'] = env
        }
        op.on('-D', '--database URL', "Set database location (Sequel URL format, default: #{d[:database]}") { |db|
          config['database'] = db
        }

        op.on('-d', '--data-dir PATH', "Directory in which to place products received from jobs (default: #{d[:data_dir]})") { |data_dir|
          config['data_dir'] = data_dir
        }
        op.on('-I', '--plugin-dir DIRECTORY', "Search for plugins in DIRECTORY (default: #{d[:plugin_path]})") { |plugin_path|
          config['plugin_path'] = plugin_path
        }
        op.on('-p', '--plugin STRING', "Load a plugin") { |id|
          config['plugins'] << id
        }

        op.on_tail('-v', '--version', "Print version infomration and exit") {
          puts "maru subscriber #{Maru::VERSION}"
          exit
        }
        op.on_tail('-h', '--help', "Print this message and exit") {
          puts op
          exit
        }
      }.parse!(ARGV.dup)
    end

    helpers do
      include Rack::Utils
    end

    Sass::Plugin.options[:style] = :compressed
    use Sass::Plugin::Rack

    def self.initialize_from_config
      set :bind,              settings.app_config["host"]
      set :port,              settings.app_config["port"]
      set :environment,       settings.app_config["environment"].to_sym
      set :db, Sequel.connect(settings.app_config["database"])

      # ugh, so ugly
      set :networks, settings.app_config["producer"]["networks"].inject({}) { |networks, network|
        next unless %w(host key client_name).all? { |key| network.include? key }

        host, key, client_name = network["host"], network["key"], network["client_name"]

        host, port = host.split(":")
        port       = port ? port.to_i : 8490

        networks["#{host},#{client_name}"] = {host: host, port: port, key: key, client_name: client_name}
        networks
      }

      use Rack::Session::Cookie, :secret => settings.app_config["secret"]

      require_relative 'models/task'
      require_relative 'models/job'
      require_relative 'models/user'
      require_relative 'models/task_user_relationship'
      require_relative 'models/client'

      require_relative 'lib/plugin_api'

      require_relative 'helpers/producer'

      require_relative 'controllers/index'
      require_relative 'controllers/session'
      require_relative 'controllers/task'
      require_relative 'controllers/producer'

      settings.app_config["plugins"].each do |plugin|
        require File.join(settings.app_config["plugin_path"], "#{plugin}.rb")
      end

      Task.data_dir = settings.app_config["data_dir"]
    end

    initialize_from_config if __FILE__ == $0
  end
end

Maru::Subscriber.run! if __FILE__ == $0
