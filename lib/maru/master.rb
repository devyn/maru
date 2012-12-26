require 'eventmachine'
require 'maru/protocol'

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
  #     "port" => 2931
  #   }).start
  #
  # @example Configuring from command-line arguments
  #   Maru::Master.new.configure_from_argv!.start
  class Master
    # The host that the server will be bound to once started.
    attr_accessor :host

    # The TCP port that the server will be bound to once started.
    attr_accessor :port

    # @param [Hash] config
    #   Used to set the various configuration attributes of a master.
    # @option config [String] :host ("0.0.0.0")
    #   The host to bind the server to.
    # @option config [Integer] :port (4450)
    #   The TCP port to bind the server to.
    def initialize(config={})
      # Convert config to Hash<String,...>
      config = config.inject({}) { |h,(k,v)| h[k.to_s] = v; h }

      @host = config["host"] || "0.0.0.0"
      @port = config["port"] || 4450
    end

    # Transfers control to the master and starts it. This method must be
    # run within an EventMachine reactor loop.
    def start
      @server = EventMachine.start_server @host, @port, Maru::Protocol do |pr|
        pr.command_acceptor = self
      end
    end

    # @group Commands

    # A simple ping/pong.
    def command_PING
      ["PONG", Time.now.to_i]
    end
  end
end
