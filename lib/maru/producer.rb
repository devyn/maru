require 'socket'
require 'json'

module Maru
  class Producer
    def initialize(host, port=8490)
      @host    = host
      @port    = port
      @socket  = TCPSocket.new(host, port)
      @next_id = 0

      if (hello = JSON.parse(@socket.gets))["command"] == "hello"
        type, @network_name, @network_options = hello["arguments"]

        if type != "network"
          raise "remote is not a network (type = #{type})"
        end
      else
        raise "did not receive hello from network"
      end

      # FIXME: temporary fake authentication
      send_command "_new_session", "producer"
    end

    def submit(job_json)
      send_command "submit", job_json
    end

    def send_command(name, *args)
      @socket.puts({command: name, arguments: args, id: @next_id}.to_json)

      until (msg = JSON.parse(@socket.gets)) and msg["reply"] == @next_id
      end

      @next_id += 1

      if msg["result"]
        msg["result"]
      elsif msg["error"]
        raise "#{msg["error"]["name"]}: #{msg["error"]["message"]}"
      end
    end
  end
end
