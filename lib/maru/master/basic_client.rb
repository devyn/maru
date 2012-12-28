require 'maru/master'
require 'maru/master/worker_client'

module Maru
  class Master
  # Handles a single, unidentified connection to the master.
    class BasicClient
      # @return [Maru::Master] The master to which the connection is established.
      attr_reader :master

      # @return [Object] A {Maru::Protocol} implementing representation of the
      #   connection.
      attr_reader :connection

      # @param [Maru::Master] master
      #   The master for which the connection is managed.
      # @param [Object] connection
      #   The connection being managed. Extends {Maru::Protocol}.
      def initialize(master, connection)
        @master     = master
        @connection = connection
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
        case role
        when /^worker$/i
          # Switch to worker context.
          worker = WorkerClient.new(master, connection, *args)

          @connection.command_acceptor = worker

          @master.register_worker worker
        else
          raise ArgumentError, "Unknown role."
        end

        :OK
      end
    end
  end
end
