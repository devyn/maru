require 'eventmachine'
require 'maru/version'
require 'maru/protocol'
require 'maru/master/basic_client'
require 'set'
require 'logger'

# Raised when there are insufficient credentials to fulfill an operation.
class InsufficientCredentialsError < StandardError
end

module Maru
  # Implements the Maru "master" role, which is responsible for managing,
  # dispatching and advertising jobs and collecting their results.
  #
  # @example Starting
  #   Maru::Master.new.start
  #
  # @example Configuring from hash-like object
  #   Maru::Master.new({
  #     "host" => "0.0.0.0",
  #     "port" => 4450
  #   }).start
  #
  # @example Configuring from command-line arguments
  #   Maru::Master.new.configure_from_argv!.start
  class Master
    # @return [String] The host that the server will be bound to once started.
    attr_accessor :host

    # @return [Integer] The TCP port that the server will be bound to once started.
    attr_accessor :port

    # @return [Set<WorkerClient>] The set of connected workers.
    attr_reader :workers

    # @return [Set<WorkerClient>] The set of workers that are ready to receive work.
    attr_reader :ready_workers

    # @param [Hash] config
    #   Used to set the various configuration attributes of a master.
    # @option config [String] :host ("0.0.0.0")
    #   The host to bind the server to.
    # @option config [Integer] :port (4450)
    #   The TCP port to bind the server to.
    # @option config [Logger] :log (#<Logger @dev=STDERR, @level=Logger::FATAL>)
    #   The logger to output messages to.
    def initialize(config={})
      # Convert config to Hash<String,...>
      config = config.inject({}) { |h,(k,v)| h[k.to_s] = v; h }

      @host = config["host"] || "0.0.0.0"
      @port = config["port"] || 4450
      @log  = config["log"]

      # If no logger is given, we default to *only* dumping FATAL messages
      # to STDERR.
      if @log.nil?
        @log = Logger.new(STDERR)
        @log.level = Logger::FATAL
      end

      @workers       = Set.new
      @ready_workers = Set.new
    end

    # Transfers control to the master and starts it. This method must be
    # run within an EventMachine reactor loop.
    def start
      @log.info "maru master version #{Maru::VERSION} starting at #@host:#@port"

      @server = EventMachine.start_server @host, @port, Maru::Protocol do |conn|
        conn.command_acceptor = BasicClient.new(self, conn)
      end
    end

    # Gracefully stops the master.
    def stop
      return unless @server

      EventMachine.stop_server @server
      @server = nil
    end

    # Registers a worker as being connected and available to the master.
    #
    # @param [WorkerClient] worker
    def register_worker(worker)
      @log.debug "Worker registered: %p" % worker.name

      @workers.add worker
    end

    # Unregisters a worker from the master's pool.
    #
    # @param [WorkerClient] worker
    def unregister_worker(worker)
      @log.debug "Worker unregistered: %p" % worker.name

      @workers.delete worker
    end

    # Puts a worker in the 'ready for work' pile.
    #
    # Immediately attempts to find work for the worker.
    #
    # @param [WorkerClient] worker
    def worker_ready(worker)
      @log.debug "Worker ready: %p" % worker.name

      @ready_workers.add worker
    end

    # Removes a worker from the 'ready for work' pile.
    #
    # Immediately relinquishes any reserved offerings.
    #
    # @param [WorkerClient] worker
    def worker_busy(worker)
      @log.debug "Worker busy: %p" % worker.name

      @ready_workers.delete worker
    end
  end
end
