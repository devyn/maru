require 'minitest/autorun'
require 'maru/master'
require 'maru/protocol'

describe Maru::Master do
  describe "#command_PING" do
    it "returns an array of the pattern [\"PONG\", <Time->Integer>]" do
      result = Maru::Master.new.command_PING

      result[0].must_equal "PONG"
      result[1].must_be :>, 0
    end

    it "is responsive when invoked via a real server" do
      master = Maru::Master.new(host: "127.0.0.1", port: 44450)

      EventMachine.run do
        EventMachine.add_timer 0.1 do
          flunk "Test timed out."
        end

        master.start

        EventMachine.connect "127.0.0.1", 44450, Maru::Protocol do |pr|
          pr.send_command "PING" do |result|
            result.callback do |pong, number|
              pong.must_equal "PONG"
              number.to_i.must_be :>, 0

              EventMachine.stop_event_loop
            end

            result.errback do |error_class, error_message|
              flunk "Received error: #{error_class}: #{error_message}"
            end
          end
        end
      end
    end
  end
end
