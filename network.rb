#!/usr/bin/env ruby

# -*- encoding: utf-8 -*-

$:.unshift(File.join(File.dirname(__FILE__), "lib"))

require 'eventmachine'
require 'yaml'
require 'redis'
require 'optparse'
require 'set'
require 'uri'

require 'maru/version'
require 'maru/log'
require 'maru/json_protocol'

module Maru
  class Network
    attr_reader :config, :redis, :key_prefix, :name, :log, :waitlist

    DEFAULT_CONFIG = {
      "name"  => "mynetwork",
      "host"  => "0.0.0.0",
      "port"  => "8490",
      "color" => nil,
      "redis" => {
        "host" => "localhost",
        "port" => 6379,
        "key_prefix" => "maru.network.mynetwork."
      }
    }.freeze

    class Log < Maru::Log
      def assigning(job_json, worker_name)
        info "Assigning job \e[1m%i\e[0;36m (\e[0;1m%s\e[0;36m → \e[35m%s\e[36m) to \e[35m%s" % [
          job_json["id"],
          job_json["type"],
          URI.parse(job_json["destination"]).host,
          worker_name
        ]
      end

      def submitted(job_json)
        info "Job \e[1m%i\e[0;36m (\e[0;1m%s\e[0;36m → \e[35m%s\e[36m) submitted" % [
          job_json["id"],
          job_json["type"],
          URI.parse(job_json["destination"]).host
        ]
      end

      def completed(worker_name, id)
        info "Job \e[1m%i\e[0;36m \e[32mcompleted\e[36m by \e[35m%s" % [id, worker_name]
      end

      def failed(worker_name, id, message)
        warn "Job \e[1m%i\e[0;33m \e[31mfailed\e[33m by \e[35m%s\e[33m: %s" % [id, worker_name, message]
      end

      def reject(worker_name, id)
        info "Job \e[1m%i\e[0;36m \e[33mrejected\e[36m by \e[35m%s" % [id, worker_name]
      end

      def exiting
        info "Exiting"
      end
    end

    def initialize(config={})
      @config = DEFAULT_CONFIG.merge(config)

      @name = @config["name"]

      @log = Log.new(STDOUT, @config["color"])

      @redis     = Redis.new(@config["redis"])
      @redis_sub = Redis.new(@config["redis"])

      @key_prefix = @config["redis"]["key_prefix"] || "maru.network.#{@config["name"]}."

      @clients  = Set.new
      @waitlist = {}
    end

    def run
      unless @server
        [:INT, :TERM].each do |signal|
          trap signal do
            @log.exiting

            # New thread for Ruby 2.0
            Thread.start do
              EventMachine.stop
            end
          end
        end

        @server = EventMachine.start_server(@config["host"], @config["port"], Client, self)

        subscribe_redis
      end
    end

    def subscribe_redis
      Thread.start do
        @redis_sub.subscribe(key("available_jobs")) do |on|
          on.message do |channel,message|
            case channel
            when key("available_jobs")
              id, type = message.split(":")

              if @waitlist[type]
                @waitlist[type].each do |client|
                  client.send_command "job_available"
                end
                @waitlist.delete type
              end
            end
          end
        end
      end
    end

    def get(worker_name, types)
      types = types.dup

      until types.empty?
        type = types.delete_at rand(types.length)
        id = @redis.spop key("available_jobs:#{type}")
        if id
          @redis.sadd key("assigned_jobs:#{worker_name}"), id

          job = JSON.parse(@redis.hget(key("jobs"), id))

          @log.assigning job, worker_name

          return job
        end
      end
      nil
    end

    def submit(job_json)
      # ensure destination URI is valid

      begin
        URI.parse(job_json["destination"])
      rescue
        return nil
      end

      # get next ID

      job_json["id"] = id = @redis.incr(key("next_job_id")).to_i

      @redis.multi do
        # add to job description map
        @redis.hset key("jobs"), id, job_json.to_json

        # place in pool for workers who are looking for jobs of this type
        @redis.sadd key("available_jobs:#{job_json["type"]}"), id

        # notify network instances of the new job
        @redis.publish key("available_jobs"), "#{id}:#{job_json["type"]}"
      end

      @log.submitted job_json

      return id
    end

    def completed(worker_name, id)
      if @redis.srem(key("assigned_jobs:#{worker_name}"), id)
        @redis.multi do
          @redis.hdel(key("jobs"), id)
          @redis.sadd(key("completed_jobs"), id)
        end

        @log.completed(worker_name, id)
        true
      else
        false
      end
    end

    def failed(worker_name, id, message)
      if @redis.srem(key("assigned_jobs:#{worker_name}"), id)
        @redis.hset(key("failed_jobs"), id, message)

        @log.failed(worker_name, id, message)
        true
      else
        false
      end
    end

    def reject(worker_name, id)
      if @redis.srem(key("assigned_jobs:#{worker_name}"), id)
        job_json = JSON.parse(@redis.hget(key("jobs"), id))

        @redis.sadd(key("available_jobs:#{job_json["type"]}"), id)

        @log.reject(worker_name, id)
        true
      else
        false
      end
    rescue
      p $!
      puts $!.backtrace
      raise $!
    end

    def register_client(client)
      @clients << client
    end

    def unregister_client(client)
      @clients.delete client
    end

    module Client
      include Maru::JSONProtocol

      attr_accessor :network

      attr_reader :type, :name

      def initialize(network)
        @network = network
      end

      def post_protocol_init
        @network.register_client self

        send_command "hello", :network, @network.name, {}
      end

      def unbind
        @network.unregister_client self
      end

      def receive_command(result, name, *args)
        case @type
        when :worker
          receive_worker_command(result, name, *args)
        when :producer
          receive_producer_command(result, name, *args)
        else
          case name
          when "_new_session"
            # FIXME: temporary fake authentication

            type, options = args

            options ||= {}

            case type
            when "worker"
              result.invalid_argument! "must provide worker name" unless options["name"]

              @type = :worker
              @name = options["name"]
              result.succeed(nil)
            when "producer"
              @type = :producer
              result.succeed(nil)
            else
              result.invalid_argument! "must be worker or producer"
            end
          else
            result.unrecognized_command!
          end
        end
      end

      def receive_worker_command(result, name, *args)
        case name
        when "get"
          job = @network.get(@name, args)

          if job
            result.succeed(job)
          else
            args.each do |type|
              @network.waitlist[type] ||= Set.new
              @network.waitlist[type] << self
            end

            result.fail(name: "NoJobsAvailable", message: "there are no jobs available for the selected type")
          end
        when "completed"
          id = args[0]
          @network.completed(@name, id)

          result.succeed(nil)
        when "failed"
          id, message = args
          @network.failed(@name, id, message)

          result.succeed(nil)
        when "reject"
          id = args[0]
          @network.reject(@name, id)

          result.succeed(nil)
        else
          result.unrecognized_command!
        end
      end

      def receive_producer_command(result, name, *args)
        case name
        when "submit"
          id = @network.submit(args[0])

          if id
            result.succeed(id)
          else
            result.fail(name: "InvalidJob", message: "job data malformed")
          end
        else
          result.unrecognized_command!
        end
      end
    end

    private

    def key(string)
      @key_prefix.to_s + string
    end
  end
end

if __FILE__ == $0
  config = Maru::Network::DEFAULT_CONFIG.dup

  opts = OptionParser.new

  opts.on "-c", "--config FILE", "Load YAML configuration from FILE" do |file|
    config.update(YAML.load_file(file))
  end

  opts.on_tail "--write-config FILE", "Write YAML configuration from options to FILE and exit" do |file|
    File.open file, "w" do |f|
      YAML.dump(config, f)
    end
    exit
  end

  opts.on "-n", "--name STRING", "Set network name" do |name|
    config["name"] = name
  end

  opts.on "-H", "--host IP", "Set address to bind to" do |host|
    config["host"] = host
  end

  opts.on "-P", "--port NUMBER", "Set port to bind to" do |port|
    config["port"] = port.to_i
  end

  opts.on "--color [{always,never,auto}]", "Enable or disable colorized logging output" do |val|
    case val
    when "always"
      config["color"] = true
    when "never"
      config["color"] = false
    when "auto"
      config["color"] = nil
    when nil
      config["color"] = true
    else
      config["color"] = nil
    end
  end

  opts.on "-r", "--redis HOST[:PORT]", "Redis server location" do |hostport|
    host, port = hostport.split(":")
    port = port ? port.to_i : 6380

    config["redis"]["host"] = host
    config["redis"]["port"] = port
  end

  opts.on "--redis-key-prefix STRING", "Redis key prefix" do |key_prefix|
    config["redis"]["key_prefix"] = key_prefix
  end

  opts.on_tail "-v", "--version", "Print version information and exit" do
    puts "maru network #{Maru::VERSION}"
    exit
  end

  opts.on_tail "-h", "--help", "Print this message and exit" do
    puts opts
    exit
  end

  opts.parse!(ARGV)

  EventMachine.run do
    Maru::Network.new(config).run
  end
end
