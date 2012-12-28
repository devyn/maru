require 'maru/master'

module Maru
  class Master
    # Handles the connection between a master and a worker.
    #
    # This object is only created after the connection has been handled
    # by {BasicClient} and {BasicClient#command_IDENTIFY} has been invoked
    # with a desire to transition to the `WORKER` role.
    class WorkerClient
      # @return [Maru::Master] The master to which the connection is established.
      attr_reader :master

      # @return [EventMachine::Connection] A {Protocol} implementing
      #   representation of the connection.
      attr_reader :connection

      # @return [String] The worker's name.
      attr_reader :name

      # @return [String] Identification for the worker's owner. Often an email
      #   address.
      attr_reader :owner

      # @param [Master] master
      #   The master for which the connection is being held.
      # @param [EventMachine::Connection] connection
      #   A Maru {Protocol} session.
      # @param [String] name
      #   The worker's name.
      # @param [String] owner
      #   Identification for the worker's owner. Often an email address.
      def initialize(master, connection, name, owner)
        @master     = master
        @connection = connection
        @name       = name
        @owner      = owner
      end

      # When the connection is terminated, the worker must unregister
      # itself from the associated master.
      def connection_terminated
        @master.unregister_worker self
      end

      # @group Commands

      # Notifies the master that the worker is ready to receive work.
      def command_READY
        @master.worker_ready self
        :OK
      end

      # Notifies the master that the worker is currently at maximum capacity
      # and is not interested in receiving work.
      def command_BUSY
        @master.worker_busy self
        :OK
      end
    end
  end
end
