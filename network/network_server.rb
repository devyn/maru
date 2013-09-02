#!/usr/bin/env ruby

# -*- encoding: utf-8 -*-

$:.unshift(File.join(File.dirname(__FILE__), "../lib"))

require 'eventmachine'
require 'yaml'
require 'redis'
require 'optparse'
require 'set'
require 'uri'

require 'maru/version'
require 'maru/log'
require 'maru/json_protocol'
require 'maru/authentication'

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
        info "Assigning job \e[1m%i\e[0;36m (\e[0;1m%s\e[0;36m -> \e[35m%s\e[36m) to \e[35m%s" % [
          job_json["id"],
          job_json["type"],
          URI.parse(job_json["destination"]).host,
          worker_name
        ]
      end

      def submitted(job_json)
        info "Job \e[1m%i\e[0;36m (\e[0;1m%s\e[0;36m -> \e[35m%s\e[36m) submitted" % [
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

      def client_was_deleted(client_name)
        info "Client \e[35m%s\e[0;36m was deleted and will be disconnected" % [client_name]
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
        @redis_sub.subscribe(key("available_jobs"), key("assigned_jobs"), key("clients"), key("active_clients")) do |on|
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
            when key("assigned_jobs")
              case message
              when /^aborted:(\d+):(.*)/
                id, worker_name = $1.to_i, $2

                EventMachine.next_tick do
                  @clients.each do |client|
                    if client.type == :worker and client.name == worker_name
                      client.send_command "abort", id
                    end
                  end
                end
              end
            when key("clients")
              case message
              when /^deleted:(.*)/
                client_name = $1

                EventMachine.next_tick { client_was_deleted(client_name) }
              end
            when key("active_clients")
              case message
              when /^disconnected:(.*)/
                client_name = $1

                if @clients.find { |client| client.name == client_name }
                  # When a client disconnects from a network, its name is
                  # removed from the active_clients set. However, though
                  # discouraged when trivially avoidable, multiple clients
                  # with the same name are allowed to be connected at the
                  # same time.
                  #
                  # As multiple network processes may also run in order to
                  # handle load balancing better in some cases, if the client
                  # is still connected when it is removed from the
                  # active_clients set, it must be re-added to the set in
                  # order to report the status of the client properly.

                  @redis.sadd(key("active_clients"), client_name)
                end
              end
            end
          end
        end
      end
    end

    def lookup_client(client_name)
      client = @redis.hget(key("clients"), client_name)

      if client
        JSON.parse(client)
      else
        nil
      end
    end

    def get(worker_name, types)
      types = types.dup

      until types.empty?
        type = types.delete_at rand(types.length)

        # The loop is just in case we find jobs that don't exist
        # due to an unclean database.
        loop do
          id = @redis.spop key("available_jobs:#{type}")
          if id
            job = @redis.hget(key("jobs"), id)

            # If the database isn't clean, sometimes available_jobs
            # contains jobs that don't exist. For obvious reasons,
            # we need to skip those. This will remove those entries
            # as well due to the SPOP above.
            next unless job

            job = JSON.parse(job)

            @redis.sadd key("assigned_jobs:#{worker_name}"), id
            @redis.hset key("jobs(worker)"), id, worker_name

            @log.assigning job, worker_name

            return job
          else
            break
          end
        end
      end
      nil
    end

    def submit(producer_name, job_json)
      # ensure destination URI is valid

      begin
        URI.parse(job_json["destination"])
      rescue
        return false
      end

      # get next ID

      job_json["id"] = id = @redis.incr(key("next_job_id")).to_i

      job_json["producer"] = producer_name

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

    def abort_job(id, &callback)
      if worker_name = @redis.hget(key("jobs(worker)"), id)
        @redis.multi do
          @redis.srem(key("assigned_jobs:#{worker_name}"), id)
          @redis.hdel(key("jobs(worker)"), id)

          @redis.publish(key("assigned_jobs"), "aborted:#{id}:#{worker_name}")
        end
      end

      true
    end

    def cancel(producer_name, id)
      if @redis.hexists(key("failed_jobs"), id)
        @redis.multi do
          @redis.hdel(key("jobs"), id)
          @redis.hdel(key("failed_jobs"), id)
        end
        true
      elsif job_json_string = @redis.hget(key("jobs"), id)
        job_json = JSON.parse(job_json_string)

        if job_json["producer"] == producer_name
          abort_job(id)

          @redis.multi do
            @redis.hdel(key("jobs"), id)
          end

          true
        else
          :not_owner
        end
      elsif @redis.sismember(key("completed_jobs"), id)
        :job_already_completed
      else
        :not_found
      end
    end

    def retry(producer_name, id)
      if @redis.hexists(key("failed_jobs"), id)
        if job_json_string = @redis.hget(key("jobs"), id)
          job_json = JSON.parse(job_json_string)

          if job_json["producer"] == producer_name
            @redis.multi do
              @redis.sadd(key("available_jobs:#{job_json["type"]}"), id)
              @redis.publish("available_jobs", "#{id}:#{job_json["type"]}")
            end

            true
          else
            :not_owner
          end
        end
      else
        :job_not_failed
      end
    end

    def completed(worker_name, id)
      if @redis.srem(key("assigned_jobs:#{worker_name}"), id)
        @redis.multi do
          @redis.hdel(key("jobs(worker)"), id)
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
        @redis.multi do
          @redis.hdel(key("jobs(worker)"), id)
          @redis.hset(key("failed_jobs"), id, message)
        end

        @log.failed(worker_name, id, message)
        true
      else
        false
      end
    end

    def reject(worker_name, id)
      if @redis.srem(key("assigned_jobs:#{worker_name}"), id)
        job_json = JSON.parse(@redis.hget(key("jobs"), id))

        @redis.multi do
          @redis.hdel(key("jobs(worker)"), id)
          @redis.sadd(key("available_jobs:#{job_json["type"]}"), id)

          @redis.publish key("available_jobs"), "#{id}:#{job_json["type"]}"
        end

        @log.reject(worker_name, id)
        true
      else
        false
      end
    end

    def reject_all(worker_name)
      assigned_jobs = @redis.smembers(key("assigned_jobs:#{worker_name}"))

      unless assigned_jobs.empty?
        job_jsons = @redis.hmget(key("jobs"), assigned_jobs).map { |json| JSON.parse(json) }

        jobs = assigned_jobs.zip(job_jsons)

        @redis.multi do
          jobs.each do |(id, job_json)|
            @redis.hdel(key("jobs(worker)"), id)
            @redis.sadd(key("available_jobs:#{job_json["type"]}"), id)

            @redis.publish key("available_jobs"), "#{id}:#{job_json["type"]}"

            @log.reject(worker_name, id)
          end

          @redis.del(key("assigned_jobs:#{worker_name}"))
        end
      end
    end

    def register_client(client)
      @clients << client
    end

    def client_ready(client)
      # Notify other database users
      @redis.multi do
        @redis.sadd(key("active_clients"), client.name)
        @redis.publish(key("active_clients"), "connected:#{client.name}")
      end
    end

    def unregister_client(client)
      @clients.delete client

      if client.ready?
        # Notify other database users
        @redis.multi do
          @redis.srem(key("active_clients"), client.name)

          # If the client is still connected to any other network processes,
          # that process is expected to SADD the name to active_clients again,
          # but must not publish that it has connected
          @redis.publish(key("active_clients"), "disconnected:#{client.name}")
        end
      end
    end

    def client_was_deleted(client_name)
      @log.client_was_deleted(client_name)

      if clients = @clients.select { |c| c.name == client_name }
        remaining = clients.count

        clients.each { |client|
          client.on_disconnect {
            remaining -= 1
            if remaining == 0
              # reject jobs owned by the client
              reject_all client_name
            end
          }
          client.critical :AuthenticationFailure
        }
      end
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

        send_command "hello", type: "network", name: @network.name, extensions: []
      end

      def post_protocol_unbind
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
          when "hello"
            hello = args[0]

            return result.invalid_argument!("name not specified") unless hello["name"]
            return result.invalid_argument!("type not specified") unless hello["type"]

            unless %w{worker producer}.include? hello["type"]
              return result.invalid_argument!("unsupported connection type")
            end

            @hello = hello

            # If this returns nil, the client name is unknown, but we mustn't make that obvious
            @info = @network.lookup_client(hello["name"])

            # Send our challenge

            challenge = Maru::Authentication::Challenge.new(@info["key"]) if @info

            send_command("challenge", challenge.to_s).callback { |response|
              if @info and challenge.verify(response)
                @name = @hello["name"]

                if @info["permissions"].include? @hello["type"]
                  # Authentication is successful. Enable client.
                  @type = @hello["type"].to_sym
                  @network.client_ready self
                else
                  # Client is not authorized for the connection type.
                  critical :Unauthorized
                end
              else
                # Not successful. Close connection.
                critical :AuthenticationFailure
              end
            }

            result.succeed(nil)
          when "challenge"
            if @hello
              return result.invalid_argument!("challenge required") unless challenge = args[0]

              # Generate response to challenge.
              # The way authentication works in maru is that both sides
              # challenge a shared key to prove the identity of the other
              # before continuing.

              result.succeed(Maru::Authentication.respond(challenge, @info["key"]))
            else
              # `hello` must be sent first
              result.unrecognized_command!
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
          id = @network.submit(@name, args[0])

          if id
            result.succeed(id)
          else
            result.fail(name: "InvalidJob", message: "job data malformed")
          end
        when "cancel"
          case @network.cancel(@name, args[0])
          when :not_owner
            result.fail(name: "Unauthorized", message: "you did not submit that job")
          when :not_found
            result.fail(name: "NotFound", message: "the job was not found")
          when :job_already_completed
            result.fail(name: "InvalidOperation", message: "the job has already been completed")
          else
            result.succeed(nil)
          end
        when "retry"
          case @network.retry(@name, args[0])
          when :not_owner
            result.fail(name: "Unauthorized", message: "you did not submit that job")
          when :job_not_failed
            result.fail(name: "InvalidOperation", message: "the job has not yet failed or does not exist")
          else
            result.succeed(nil)
          end
        else
          result.unrecognized_command!
        end
      end

      def ready?
        @type ? true : false
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
