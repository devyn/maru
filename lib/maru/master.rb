require 'eventmachine'
require 'maru/protocol'
require 'set'

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
  #     "port" => 2931
  #   }).start
  #
  # @example Configuring from command-line arguments
  #   Maru::Master.new.configure_from_argv!.start
  class Master
    # @return [String] The host that the server will be bound to once started.
    attr_accessor :host

    # @return [Integer] The TCP port that the server will be bound to once started.
    attr_accessor :port

    # @return [Set<Client>] The set of connected workers.
    attr_reader :workers

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

      @workers = Set.new
    end

    # Transfers control to the master and starts it. This method must be
    # run within an EventMachine reactor loop.
    def start
      @server = EventMachine.start_server @host, @port, Maru::Protocol do |conn|
        conn.command_acceptor = Client.new(self, conn)
      end
    end

    # Registers a worker as being connected and available to the master.
    #
    # @param [Client] worker
    def register_worker(worker)
      @workers.add worker
    end

    # Unregisters a worker from the master's pool.
    #
    # @param [Client] worker
    def unregister_worker(worker)
      @workers.delete worker
    end

    # Handles a single connection to the master.
    class Client
      # @return [Maru::Master] The master to which the connection is established.
      attr_reader :master

      # @return [Object] A {Maru::Protocol} implementing representation of the
      #   connection.
      attr_reader :connection

      # @return [Symbol,nil] The role the client is in, or `nil` if it has not yet
      #   chosen one.
      attr_reader :role

      # @return [String,nil] The name of the client, if applicable.
      attr_reader :name

      # @return [String,nil] The owner of the client, if applicable. Often an
      #   email address.
      attr_reader :owner

      # @param [Maru::Master] master
      #   The master for which the connection is managed.
      # @param [Object] connection
      #   The connection being managed. Extends {Maru::Protocol}.
      def initialize(master, connection)
        @master     = master
        @connection = connection
      end

      # Invoked when the connection ends. Simply unregisters from the master.
      def connection_terminated
        case @role
        when :worker
          @master.unregister_worker self
        end
      end

      # @group Commands

      # @overload command_IDENTIFY("WORKER", name, owner)
      #   Allows a client to self-identify as a worker.
      #
      #   @param [String] name
      #     The worker's name (for example, `DevHost1.1`).
      #   @param [String] owner
      #     An identifying piece of information for the worker's owner or
      #     maintainer. Conventionally an email address.
      def command_IDENTIFY(role, *args)
        raise StandardError, "Already identified." if @role

        case role
        when /^worker$/i
          @role = :worker
          @name, @owner = args

          @master.register_worker self
        else
          raise ArgumentError, "Unknown role."
        end

        :OK
      end

      # @group Command helpers

      # Used to ensure that the client is a worker before going through with
      # an operation.
      #
      # @raise [InsufficientCredentialsError] if the client is not a worker.
      def must_be_worker!
        raise InsufficientCredentialsError,
          "You must be a worker to perform that operation." unless @role == :worker
      end
    end
  end
end
