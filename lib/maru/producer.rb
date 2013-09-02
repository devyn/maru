require 'socket'
require 'json'

require_relative 'authentication'
require_relative 'json_protocol'

module Maru
  module Producer
    include Maru::JSONProtocol
    include EventMachine::Deferrable

    def self.connect(host, port, client_name, client_key, action, &block)
      EventMachine.connect(host, port, self, client_name, client_key, action, &block)
    end

    def initialize(client_name, client_key, action)
      @client_name = client_name
      @client_key  = client_key
      @action      = action
    end

    def post_protocol_init
      send_command "hello", type: "producer", name: @client_name, extensions: []
    end

    def receive_command(result, name, *args)
      case name
      when "hello"
        hello = args[0]

        if hello["type"] != "network"
          critical  :UnexpectedConnectionType
          self.fail "the server is not a network (type=#{hello["type"]})"
        end

        challenge = Maru::Authentication::Challenge.new(@client_key)

        send_command("challenge", challenge.to_s).callback { |response|
          if challenge.verify(response)
            @network_verified = true
            if @self_verified
              self.send(*@action)
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
        if @network_verified
          submit_payload
        end
      end
    end

    def submit(payload)
      remaining = payload.count
      errors    = []
      jobs      = []

      payload.each do |job_json|
        send_command("submit", job_json).callback { |id|
          remaining -= 1

          $stdout << '.'
          $stdout.flush

          jobs << id

          if remaining == 0
            $stdout.puts
            self.succeed(errors, jobs)
          end
        }.errback { |error|
          remaining -= 1

          $stdout << 'F'
          $stdout.flush

          errors << error.update("job" => job_json)

          if remaining == 0
            $stdout.puts
            self.succeed(errors, jobs)
          end
        }
      end
    end

    def cancel(*ids)
      remaining = ids.count
      errors = []

      ids.each do |id|
        send_command("cancel", id).callback {
          remaining -= 1

          $stdout << '.'
          $stdout.flush

          if remaining == 0
            $stdout.puts
            self.succeed(errors)
          end
        }.errback { |error|
          remaining -= 1

          $stdout << 'F'
          $stdout.flush

          errors << error.update("id" => id)

          if remaining == 0
            $stdout.puts
            self.succeed(errors)
          end
        }
      end
    end
  end
end
