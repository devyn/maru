require 'optparse'
require 'uri'
require 'eventmachine'
require 'httpclient'
require 'fileutils'
require 'yaml'

module Maru
  class Worker
    DEFAULT_CONFIG = {
      "name"        => "MyWorker",
      "temp_dir"    => "/tmp/maru-worker/MyWorker",
      "plugin_path" => File.expand_path(File.join(File.dirname(__FILE__), "worker/plugins")),
      "plugins"     => [],
      "color"       => nil
    }.freeze

    class PrerequisiteAcquisitionFailed < StandardError; end
    class PrerequisiteChecksumFailed    < StandardError; end

    class Log
      def initialize(out, color=nil)
        @out   = out
        @color = color.nil? ? out.tty? : color
      end

      def connected_to_network(name)
        info "Connected to network '\e[35m%s\e[36m'" % name
      end

      def network_connection_failed(name, msg)
        warn "Failed to connect to network '\e[35m%s\e[33m': %s" % [name, msg]
      end

      def job_received(network, job)
        info "Received job from '\e[35m%s\e[36m': \e[0;1m%s \e[0;36m(→ \e[35m%s\e[36m)" % [
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

      def job_info(msg, options={})
        info "  #{msg}", options
      end

      def job_warn(msg, options={})
        warn "  #{msg}", options
      end

      def info(msg, options={})
        if @color
          @out << "\e[1m>> \e[0;36m#{msg}\e[0m"
        else
          @out << ">> #{msg.gsub(/\e\[\d{1,2}(?:;\d{1,2})?m/, '')}"
        end

        if options[:newline] == false
          @out.flush
        else
          @out << "\n"
        end
      end

      def warn(msg, options={})
        if @color
          @out << "\e[1m!! \e[0;33m#{msg}\e[0m"
        else
          @out << "!! #{msg.gsub(/\e\[\d{1,2}(?:;\d{1,2})?m/, '')}"
        end

        if options[:newline] == false
          @out.flush
        else
          @out << "\n"
        end
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
      attr_reader :type, :destination, :description

      attr_accessor :prerequisites

      def initialize(job_json, worker, &on_finish)
        @worker        = worker

        @type          = job_json["type"]
        @destination   = job_json["destination"]
        @description   = job_json["description"]

        @prerequisites = {}

        @results       = {}

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

      def submit
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
              "X-Maru-Worker-Id"       => @worker.name
            }
          )
        rescue
          error("while trying to submit results: #{$!.message}")
        end

        if res.code == 200
          @worker.log.job_completed
          @on_finish.(:success)
        else
          error("while trying to submit results: HTTP error #{res.code}: #{res.reason}")
        end
      end

      def error(msg)
        @worker.log.job_error(msg)
        @on_finish.(:error, msg)
      end
    end

    attr_reader :config, :name, :log, :http

    def initialize(config={})
      @config = DEFAULT_CONFIG.merge(config)

      @name = @config["name"]

      @log = Log.new(STDOUT, @config["color"])

      @http = HTTPClient.new

      @plugins = {}

      Plugin::PLUGINS.each do |plugin|
        @plugins[plugin.job_type] = plugin.new(@config)
      end
    end

    def run
      @log.connected_to_network "Dummy"

      job_json = {
        "type" => "me.devyn.maru.Echo",
        "destination" => "http://localhost:3000/task/4cf9d0007ca1e256ec4fbdf3cf8d6ea8/submit",
        "description" => {
          "external" => {
            "maru.blend" => {"url" => "http://s.devyn.me/maru.blend", "sha256" => "32368540ea4a82330d4fd7f47e1d051df390956ccd53d125e914ec3f156d5b31"}
          },
          "results" => {
            "hello.txt" => "Hello world!"
          }
        }
      }

      @log.job_received "Dummy", job_json

      prereq_results = acquire_prerequisites(job_json)

      process_job(job_json, prereq_results)
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
          rescue HTTPClient::BadResponseError
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

    def process_job(job_json, prereq_results)
      temp_path = File.join(@config["temp_dir"], "jobs", "%032x" % rand(16**32))

      @job = Job.new(job_json, self) do
        @job = nil

        #EM.next_tick { self.get_work } # or something
      end

      @job.prerequisites = prereq_results

      @job_thread = Thread.start do
        begin
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
    #puts Maru::VERSION
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
