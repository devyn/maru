require 'json'
require 'eventmachine'

require_relative 'authentication'
require_relative 'json_protocol'

module Maru
  module Client
    include Maru::JSONProtocol
    include EventMachine::Deferrable

    def self.connect(remote_type, host, port, client_type, client_name, client_key, &block)
      EventMachine.connect(host, port, self, remote_type, client_type, client_name, client_key, &block)
    end

    def initialize(remote_type, client_type, client_name, client_key)
      @remote_type = remote_type
      @client_type = client_type
      @client_name = client_name
      @client_key  = client_key
    end

    def post_protocol_init
      send_command "hello", type: @client_type, name: @client_name, extensions: []
    end

    def receive_command(result, name, *args)
      case name
      when "hello"
        hello = args[0]

        if hello["type"] != @client_type
          critical  :UnexpectedConnectionType
          self.fail "the server is not a #@client_type (type=#{hello["type"]})"
        end

        challenge = Maru::Authentication::Challenge.new(@client_key)

        send_command("challenge", challenge.to_s).callback { |response|
          if challenge.verify(response)
            @remote_verified = true
            if @self_verified
              self.succeed(self)
            end
          else
            critical  :AuthenticationFailure
            self.fail "failed to prove that the server shares our key"
          end
        }.errback { |err|
          critical  :AuthenticationFailure
          self.fail "server failed to respond to challenge; #{err["name"]}: #{err["message"]}"
        }
      when "challenge"
        result.succeed(Maru::Authentication.respond(args[0], @client_key))

        @self_verified = true
        if @remote_verified
          self.succeed(self)
        end
      end
    end

    def handle_critical(msg)
      self.fail "server: #{msg}"
    end
  end
end
