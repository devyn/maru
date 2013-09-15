require 'json'
require 'eventmachine'

module Maru
  module JSONProtocol
    class Result
      include EventMachine::Deferrable

      def unrecognized_command!
        self.fail(name: "UnrecognizedCommand")
      end

      def invalid_argument!(msg="invalid argument")
        self.fail(name: "InvalidArgument", message: msg)
      end

      def forbidden!(msg="the operation is forbidden")
        self.fail(name: "Forbidden", message: msg)
      end
    end

    def post_init
      @data_buf        = ""
      @command_results = {}
      @next_id         = 0

      @on_disconnect   = []

      start_tls verify_peer: false
    end

    def ssl_handshake_completed
      if defined?(post_protocol_init)
        post_protocol_init
      end
    end

    def unbind
      @on_disconnect.each &:call

      if defined?(post_protocol_unbind)
        post_protocol_unbind
      end
    end

    def receive_data(data)
      @data_buf << data

      if @data_buf.include? "\n"
        split = @data_buf.split("\n")

        if @data_buf[-1] == "\n"
          inputs    = split.map { |text| JSON.parse(text) rescue nil }.reject(&:nil?)
          @data_buf = ""
        else
          inputs    = split[0..-2].map { |text| JSON.parse(text) rescue nil }.reject(&:nil?)
          @data_buf = split[-1]
        end

        inputs.each do |input|
          if input["command"]
            begin
              res = Result.new

              res.callback do |result|
                send_data({reply: input["id"], result: result}.to_json << "\n")
              end
              res.errback do |error|
                send_data({reply: input["id"], error: error}.to_json << "\n")
              end

              receive_command(res, input["command"], *input["arguments"])
            rescue
              warn "BUG: Maru JSON Protocol intercepted error!"
              warn "  #{$!.class.name}: #{$!.message}"
              warn $!.backtrace.map { |s| "    " << s }

              send_data({reply: input["id"], error: {name: "InternalServerError", message: "#{$!.class.name}: #{$!.message}"}}.to_json << "\n")
            end
          elsif input["reply"] and @command_results[input["reply"]]
            if input["error"]
              @command_results[input["reply"]].fail input["error"]
            else
              @command_results[input["reply"]].succeed input["result"]
            end
          elsif input["critical"]
            close_connection
            handle_critical(input["critical"])
          end
        end
      end
    end

    def handle_critical(msg)
      # Default implementation: do nothing
    end

    def send_command(name, *args)
      id = (@next_id += 1).to_s

      send_data({command: name, arguments: args, id: id}.to_json << "\n")

      return(@command_results[id] = Result.new)
    end

    def critical(msg)
      send_data({critical: msg.to_s}.to_json << "\n")
      close_connection_after_writing
    end

    def on_disconnect(&block)
      if block.respond_to? :call
        @on_disconnect << block
      end
    end
  end
end
