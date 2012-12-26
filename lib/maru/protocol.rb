require 'openssl'
require 'eventmachine'

module Maru
  # Implements the Maru protocol. Use as an EventMachine server.
  module Protocol
    include EventMachine::Deferrable

    # @return [String] Path to the certificate chain file to identify with.
    attr_accessor :cert_chain_file

    # @return [String] Path to the private key file for the certificate.
    attr_accessor :private_key_file

    # @return [String] An optional certificate to validate against once the
    #   connection is established.
    attr_accessor :verify_peer

    # @return [Object] An object that has methods to accept commands, e.g. `command_AUTH`
    #   which corresponds to a hypothetical 'AUTH' command.
    attr_accessor :command_acceptor

    # @return [Proc] When set to a block, the block will be called every time data is received,
    #   so that commands may intercept the data (e.g. to accept a file).
    attr_accessor :interceptor

    # @return [Symbol] The current state of the network protocol parser.
    attr_accessor :parse_state

    # @return [Hash] Context data for the parser.
    attr_accessor :parse_data

    # @return [Integer] Keeps track of the next unused incremental index for #send_command.
    attr_accessor :trigger_index

    # @return [Hash<Integer,EventMachine::Deferrable>] A collection of triggers to be invoked
    #   once data has been received in response to a command invocation.
    attr_accessor :triggers

    # @private
    def post_init
      @parse_state = :initial
      @parse_data  = {}

      @trigger_index = 1
      @triggers      = {}

      start_tls :private_key_file =>  @private_key_file,
                :cert_chain_file  => @cert_chain_file,
                :verify_peer      => false
    end

    # @private
    def ssl_handshake_completed
      if @verify_peer
        # Verify that the peer is indeed the peer we're looking for. This is
        # used for clients. Servers have their own auth protocols.

        cert        = OpenSSL::X509::Certificate.new(get_peer_cert)
        verify_cert = OpenSSL::X509::Certificate.new(@verify_peer)

        if cert.to_s != verify_cert.to_s
          set_deferred_status :failed # Notify callbacks of failure to connect.
          close_connection
          return
        end
      end

      set_deferred_status :succeeded # Notify callbacks of connection.
    end

    # @private
    def receive_data(data)
      if @interceptor
        @interceptor.call(data)
      else
        parse(data)
      end
    end

    # @private
    def parse(data)
      index = 0

      while index < data.length
        ch = data[index]

        case @parse_state
        when :initial
          case ch
          when ?/
            index += 1

            @parse_state = :command_name
            @parse_data[:command_name] = [] # see `:response_trigger`; same sort of idea.
          when ?0..?9
            @parse_state = :response_trigger
            @parse_data[:response_trigger] = [] # initially array of chars, which is then joined
          else
            index += 1 # skip over any initial garbage (newlines, spaces, cows, that sort of thing)
          end
        when :response_trigger
          index += 1

          case ch
          when ?\n
            @parse_state = :initial
            @parse_data  = {}
          when ?/
            @parse_state = :command_name
            @parse_data[:response_trigger] = @parse_data[:response_trigger].join(nil).to_i
            @parse_data[:command_name]     = [] # see `:response_trigger`; same sort of idea.
          when ?0..?9
            @parse_data[:response_trigger] << ch
          else
          end
        when :command_name
          index += 1

          case ch
          when ?\n, ?\s
            @parse_data[:command_name] = @parse_data[:command_name].join(nil)
            @parse_data[:command_args] = []

            if ch == ?\n
              # Command with no arguments.
              dispatch_parsed_command
            else
              # Arguments follow.
              @parse_state = :argument_size
              @parse_data[:argument_size] = [] # see `:response_trigger`
            end
          else
            @parse_data[:command_name] << ch
          end
        when :argument_size
          index += 1

          case ch
          when ?\n
            dispatch_parsed_command
          when ?:
            # Colon separates argument length from argument data. So make that transition:
            @parse_state = :argument_data
            @parse_data[:argument_size] = @parse_data[:argument_size].join(nil).to_i
            @parse_data[:argument_data] = [] # see `:response_trigger`, etc.
          when ?0..?9
            @parse_data[:argument_size] << ch
          else
            # Skip anything else.
          end
        when :argument_data
          # Try to take as much as is remaining from the data.
          part = data.slice(index, @parse_data[:argument_size])
          index += part.length

          @parse_data[:argument_size] -= part.length
          @parse_data[:argument_data] << part

          if @parse_data[:argument_size] <= 0
            # Add the argument.
            @parse_data[:command_args] << @parse_data[:argument_data].join(nil)

            # Transition for the next argument.
            @parse_data[:argument_size] = []
            @parse_data.delete :argument_data

            @parse_state = :argument_size
          end
        end
      end
    end

    # @private
    def dispatch_parsed_command
      @parse_data[:command_name].upcase!

      if @parse_data[:command_name] == "RESULT"
        # Handle RESULT specially. Look for triggers with the first argument
        # as their trigger, and give the remaining arguments
        #
        # If a trigger can not be found, ignore it.
        if trigger = @triggers.delete(@parse_data[:command_args].shift.to_i)

          trigger.set_deferred_status :succeeded, *@parse_data[:command_args]
        end
      elsif @parse_data[:command_name] == "ERROR"
        # Similar to RESULT, but for errors.
        if trigger = @triggers.delete(@parse_data[:command_args].shift.to_i)

          trigger.set_deferred_status :failed, *@parse_data[:command_args]
        end
      elsif @parse_data[:command_name] == "PING"
        # Built-in PING functionality: returns ["PONG", Time.now.to_i]
        if trigger = @parse_data[:response_trigger]
          send_command :RESULT, trigger, "PONG", Time.now.to_i
        end
      else
        begin
          res = @command_acceptor.send("command_#{@parse_data[:command_name]}", # e.g. AUTH => #command_AUTH
                                       *@parse_data[:command_args])

          # Send the result(s) if the client was expecting them.
          if trigger = @parse_data[:response_trigger]
            if res.is_a?(Array)
              send_command :RESULT, trigger, *res
            else
              send_command :RESULT, trigger, res
            end
          end
        rescue Exception => e
          # Report the error if the client was expecting a result.
          if trigger = @parse_data[:response_trigger]
            send_command :ERROR, trigger, e.class.name, e.message
          end
        end
      end

      # Reset the parser.
      @parse_state = :initial
      @parse_data  = {}
    end

    # Sends a command upstream. If a block is given, the peer will be notified that
    # a response is expected.
    #
    # @param [String,Symbol] name
    #   The name of the command.
    # @param [String] args
    #   Arguments (as strings) to be sent upstream.
    #
    # @yieldparam [EventMachine::Deferrable] result
    #   The deferred result of the command. May be an error.
    def send_command(name, *args, &block)
      out = []

      out << @trigger_index if block

      out << '/'
      out << name.upcase
      out << ' ' unless args.empty?

      args.each do |argument|
        a = argument.to_s

        out << a.length.to_s << ':'
        out << a
      end

      out << "\n"

      if block
        defer = @triggers[@trigger_index] = Object.new
        defer.extend(EventMachine::Deferrable)

        block.call(defer)

        @trigger_index += 1
      end

      send_data out.join(nil)
    end
  end
end
