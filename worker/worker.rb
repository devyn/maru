#!/usr/bin/env ruby

# -*- encoding: utf-8 -*-

$:.unshift(File.join(File.dirname(__FILE__), "../lib"))

require 'optparse'
require 'uri'
require 'eventmachine'
require 'httpclient'
require 'openssl'
require 'fileutils'
require 'yaml'

require 'maru/version'
require 'maru/log'
require 'maru/json_protocol'
require 'maru/authentication'

module Maru
  class Worker
    DEFAULT_CONFIG = {
      "name"        => "MyWorker",
      "temp_dir"    => "/tmp/maru-worker/MyWorker",
      "plugin_path" => File.expand_path(File.join(File.dirname(__FILE__), "plugins")),
      "plugins"     => [],
      "networks"    => [],
      "color"       => nil
    }.freeze

    class PrerequisiteAcquisitionFailed < StandardError; end
    class PrerequisiteChecksumFailed    < StandardError; end

    class Log < Maru::Log
      def connected_to_network(name)
        info "Connected to network '\e[35m%s\e[36m'" % name
      end

      def disconnected_from_network(name)
        warn "Disconnected from network '\e[35m%s\e[33m'" % name
      end

      def network_connection_failed(name, msg)
        warn "Failed to connect to network '\e[35m%s\e[33m': %s" % [name, msg]
      end

      def waiting_for_work
        info "No work available. Standing by."
      end

      def exiting
        info "Exiting"
      end

      def job_received(network, job)
        info "Received job from '\e[35m%s\e[36m': \e[0;1m%s \e[0;36m(-> \e[35m%s\e[36m)" % [
          network,
          job["type"],
          URI.parse(job["destination"]).host
        ]
      end

      def acquiring_job_prerequisites
        job_info "Acquire prerequisites"
      end

      def job_prerequisite_fetch(url)
        job_info "  \e[32m%-10s \e[35m%s" % ["fetch", url]
      end

      def job_prerequisite_cached(url)
        job_info "  \e[32m%-10s \e[35m%s" % ["cached", url]
      end

      def job_prerequisite_failed(url)
        job_info "  \e[31m%-10s \e[35m%s" % ["failed", url]
      end

      def job_uploading_to(dest_name)
        job_info "Upload results to \e[35m%s" % dest_name
      end

      def job_completed
        job_info "\e[32mJob completed"
      end

      def job_error(msg, options={})
        job_warn "\e[1;31mJob error: \e[0;31m%s" % msg, options
      end

      def job_aborted
        job_warn "Job aborted by network"
      end

      def job_info(msg, options={})
        info "  #{msg}", options
      end

      def job_warn(msg, options={})
        warn "  #{msg}", options
      end
    end

    class Plugin
      PLUGINS = []
      
      def self.inherited(c)
        PLUGINS << c
      end

      def initialize(config)
      end
    end

    class Job
      attr_reader :id, :type, :destination, :description

      attr_accessor :prerequisites, :thread

      def initialize(job_json, network, worker, &on_finish)
        @network       = network
        @worker        = worker

        @id            = job_json["id"]
        @type          = job_json["type"]
        @destination   = job_json["destination"]
        @description   = job_json["description"]

        @prerequisites = {}

        @results       = {}

        @incomplete    = true

        @on_finish     = on_finish
      end

      def info(msg)
        @worker.log.job_info msg
      end

      def warn(msg)
        @worker.log.job_warn msg
      end

      def result(filename, string_or_io)
        unless string_or_io.is_a? IO
          string_or_io = string_or_io.to_s
        end

        @results[filename] = string_or_io
      end

      def reject(&block)
        if @incomplete
          @incomplete = false

          EventMachine.next_tick do
            @network.send_command("reject", @id).callback {
              block.() if block
            }.errback {
              block.() if block
            }

            @thread.kill
          end
        end
      end

      def abort
        if @incomplete
          EventMachine.next_tick { @thread.kill }

          @worker.log.job_aborted
          @on_finish.(:aborted)
        end
      end

      def submit
        if @incomplete
          @worker.log.job_uploading_to(@destination)

          # TODO: errors should result in submission being queued, really

          begin
            res = @worker.http.post(
              @destination,
              @results.map { |k, v|
                ["results[#{k}]", v]
              },
              {
                "Content-Type"           => "multipart/form-data",
                "User-Agent"             => "maru",
                "X-Maru-Job-Type"        => @type,
                "X-Maru-Job-Description" => @description,
                "X-Maru-Worker-Id"       => @network.client_name,
                "X-Maru-Network-Id"      => @network.name
              }
            )

            if res.code == 200
              @incomplete = false

              EventMachine.next_tick do
                @network.send_command("completed", @id)

                @worker.log.job_completed
                @on_finish.(:completed)
              end
            else
              error("while trying to submit results: HTTP error #{res.code}: #{res.reason}")
            end
          rescue
            error("while trying to submit results: #{$!.message}")
          end
        end
      end

      def error(msg)
        if @incomplete
          @incomplete = false

          EventMachine.next_tick do
            @network.send_command "failed", @id, msg

            @worker.log.job_error(msg)
            @on_finish.(:failed, msg)
          end
        end
      end
    end

    module NetworkClient
      include Maru::JSONProtocol

      attr_accessor :worker, :work_available

      attr_reader :name, :client_name, :extensions

      def initialize(worker, host, port, client_name, key)
        @worker      = worker
        @host        = host
        @port        = port
        @client_name = client_name
        @key         = key

        @work_available = true
        @registered     = false
      end

      def post_protocol_init
        send_command "hello", name: @client_name, type: "worker", extensions: []
      end

      def post_protocol_unbind
        if @registered
          @worker.unregister_network self
          @registered = false
        end

        if @critical
          if @no_retry
            @worker.log.network_connection_failed @name, "critical error: #@critical. Will not attempt to reconnect."
          else
            @worker.log.network_connection_failed @name, "critical error: #@critical. Will retry in 10 seconds."

            EventMachine.add_timer(10) do
              EventMachine.connect(@host, @port, NetworkClient, @worker, @host, @port, @client_name, @key)
            end
          end

          @critical = nil
        else
          unless @no_retry
            @worker.log.network_connection_failed "#@host:#@port", "could not connect. Will retry in 10 seconds."

            EventMachine.add_timer(10) do
              EventMachine.connect(@host, @port, NetworkClient, @worker, @host, @port, @client_name, @key)
            end
          end
        end
      end

      def receive_command(result, name, *args)
        case name
        when "hello"
          @hello = args[0]

          @type, @name, @extensions = @hello["type"], @hello["name"], @hello["extensions"]

          if @type != "network"
            @worker.log.network_connection_failed "#@host:#@port", "remote is not a network. Will not attempt to reconnect."
            @no_retry = true

            close_connection
          end

          # Send challenge to prove that the network knows our shared key

          challenge = Maru::Authentication::Challenge.new(@key)

          send_command("challenge", challenge.to_s).callback { |response|
            if !challenge.verify(response)
              @worker.log.network_connection_failed "#@host:#@port", "network failed to prove its authenticity! Will not attempt to reconnect."
              @no_retry = true

              close_connection
            end
          }

          result.succeed(nil)
        when "challenge"
          result.succeed(Maru::Authentication.respond(args[0], @key))

          # Everything looks good! Continue.
          #
          # Possible TODO: Ensure the network's challenge has gone okay first as well somehow.
          #                Might not be an issue.
          @worker.register_network self
          @registered = true
        when "job_available"
          @work_available = true

          if @worker.waiting_for_work
            @worker.get_work
          end

          result.succeed(nil)
        when "abort"
          if @worker.job.id == args[0]
            @worker.job.abort
          end

          result.succeed(nil)
        end
      end

      def handle_critical(msg)
        @critical = msg
      end

      def disconnect
        @no_retry = true
        close_connection_after_writing
      end
    end

    attr_reader :config, :name, :log, :http, :waiting_for_work, :job

    def initialize(config={})
      @config = DEFAULT_CONFIG.merge(config)

      @name = @config["name"]

      @log = Log.new(STDOUT, @config["color"])

      @http = HTTPClient.new

      @http.ssl_config.verify_mode = OpenSSL::SSL::VERIFY_NONE

      @waiting_for_work = true

      @plugins = {}

      @networks = []

      Plugin::PLUGINS.each do |plugin|
        @plugins[plugin.job_type] = plugin.new(@config)
      end
    end

    def register_network(network)
      @networks.unshift network

      @log.connected_to_network network.name

      if @waiting_for_work
        get_work
      end
    end

    def unregister_network(network)
      @log.disconnected_from_network network.name

      @networks.delete network
    end

    def run
      [:INT, :TERM].each do |signal|
        trap signal do
          @log.exiting

          # In Ruby 2.0, for safety, this must be done on another thread.
          Thread.start do
            if @job
              @job.reject {
                @networks.each(&:disconnect)
                EventMachine.stop
              }
            else
              @networks.each(&:disconnect)
              EventMachine.stop
            end
          end
        end
      end

      @config["networks"].each do |network|
        host, port  = network["host"].split(":")
        port        = port ? port.to_i : 8490
        key         = network["key"]
        client_name = network["client_name"] || @name

        EventMachine.connect(host, port, NetworkClient, self, host, port, client_name, key)
      end
    end

    def get_work
      @waiting_for_work = false

      # only try once for each network
      remaining = @networks.count

      try = proc do
        remaining -= 1

        network = @networks.shift
        @networks << network

        if network.work_available
          # @plugins.keys = list of job types
          res = network.send_command "get", *@plugins.keys

          res.callback do |job_json|
            @log.job_received network.name, job_json

            process_job(job_json, network)
          end

          res.errback do |err|
            network.work_available = false

            if remaining > 0
              try.()
            else
              @log.waiting_for_work

              @waiting_for_work = true
            end
          end
        end
      end

      if remaining > 0
        try.()
      else
        @log.waiting_for_work

        @waiting_for_work = true
      end
    end

    def acquire_prerequisites(job_json)
      prerequisites = @plugins[job_json["type"]].prerequisites_for(job_json["description"])

      prereq_results = {}

      unless prerequisites.empty?
        @log.acquiring_job_prerequisites

        prerequisites.each do |prereq|
          path = File.join(@config["temp_dir"], "prerequisites", Digest::SHA1.hexdigest(prereq[:url]) + "-" + URI.parse(prereq[:url]).path.split("/").last)

          if File.exists? path
            if Digest::SHA256.file(path).hexdigest == prereq[:sha256]
              @log.job_prerequisite_cached prereq[:url]

              prereq_results[prereq[:identifier] || prereq[:url]] = path
              next
            end
          end

          @log.job_prerequisite_fetch prereq[:url]

          FileUtils.mkdir_p(File.dirname(path))

          digest = Digest::SHA256.new

          begin
            File.open(path, "wb") do |f|
              @http.get_content(prereq[:url]) do |chunk|
                f << chunk
                digest << chunk
              end
            end
          rescue
            @log.job_prerequisite_failed prereq[:url]

            File.unlink(path)

            raise PrerequisiteAcquisitionFailed, prereq[:url]
          end

          if prereq[:sha256] and digest.hexdigest != prereq[:sha256]
            @log.job_prerequisite_failed prereq[:url]

            raise PrerequisiteChecksumFailed, prereq[:url]
          end

          prereq_results[prereq[:identifier] || prereq[:url]] = path
        end
      end

      return prereq_results
    end

    def process_job(job_json, network)
      temp_path = File.join(@config["temp_dir"], "jobs", "%032x" % rand(16**32))

      @job = Job.new(job_json, network, self) do |status, error_message|
        @job = nil

        get_work
      end

      begin
        URI.parse(@job.destination)
      rescue
        @job.error("destination URI invalid")
      end

      @job.thread = Thread.start do
        begin
          @job.prerequisites = acquire_prerequisites(job_json)

          FileUtils.mkdir_p temp_path

          Dir.chdir temp_path do
            @plugins[@job.type].process_job(@job)
          end
        rescue
          @job.error("#{$!.class.name}: #$!")
        ensure
          FileUtils.rm_r temp_path rescue nil
        end
      end
    end
  end
end

if __FILE__ == $0
  config = Maru::Worker::DEFAULT_CONFIG.dup

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

  opts.on "-n", "--name STRING", "Set worker name" do |name|
    config["name"] = name
  end

  opts.on "-I", "--plugin-dir DIRECTORY", "Search for plugins in DIRECTORY" do |dir|
    config["plugin_path"] = dir
  end

  opts.on "-p", "--plugin STRING", "Load a plugin" do |id|
    config["plugins"] 
    config["plugins"] << id
  end

  opts.on "-T", "--temp-dir DIRECTORY", "Set temporary files directory" do |dir|
    config["temp_dir"] = dir
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

  opts.on_tail "-v", "--version", "Print version information and exit" do
    puts "maru worker #{Maru::VERSION}"
    exit
  end

  opts.on_tail "-h", "--help", "Print this message and exit" do
    puts opts
    exit
  end

  opts.parse!(ARGV)

  config["plugins"].each do |plugin|
    require File.join(config["plugin_path"], "#{plugin}.rb")
  end

  EventMachine.run { Maru::Worker.new(config).run }
end
