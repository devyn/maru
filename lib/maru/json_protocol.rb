require 'json'

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
    end

    def post_init
      @data_buf        = ""
      @command_results = {}
      @next_id         = 0

      if defined?(post_protocol_init)
        post_protocol_init
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
              send_data({reply: input["id"], error: {name: "InternalServerError", message: "#{$!.class.name}: #{$!.message}"}}.to_json << "\n")
            end
          elsif input["reply"] and @command_results[input["reply"]]
            if input["error"]
              @command_results[input["reply"]].fail input["error"]
            else
              @command_results[input["reply"]].succeed input["result"]
            end
          end
        end
      end
    end

    def send_command(name, *args)
      id = (@next_id += 1).to_s

      send_data({command: name, arguments: args, id: id}.to_json << "\n")

      return(@command_results[id] = Result.new)
    end
  end
end
