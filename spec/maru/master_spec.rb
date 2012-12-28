require 'minitest/autorun'
require 'maru/master'
require 'maru/protocol'

describe Maru::Master do
  describe "#register_worker" do
    it "adds a worker to the pool" do
      master     = Maru::Master.new
      our_worker = Object.new

      master.register_worker our_worker
      master.workers.must_include our_worker
    end
  end

  describe "#unregister_worker" do
    it "unregisters a worker from the pool" do
      master     = Maru::Master.new
      our_worker = Object.new

      master.workers.add our_worker
      master.unregister_worker our_worker
      master.workers.wont_include our_worker
    end

    it "only unregisters a single worker from the pool" do
      master           = Maru::Master.new
      our_worker       = Object.new
      our_other_worker = Object.new

      master.workers.add our_worker
      master.workers.add our_other_worker

      master.unregister_worker our_worker
      master.workers.must_include our_other_worker
    end
  end

  describe "#worker_ready" do
    it "registers a worker as being ready for work" do
      master     = Maru::Master.new
      our_worker = Object.new

      master.workers.add  our_worker
      master.worker_ready our_worker

      master.ready_workers.must_include our_worker
    end

    it "immediately attempts to find work for the worker" # TODO
  end

  describe "#worker_busy" do
    it "unregisters a worker as being ready for work" do
      master     = Maru::Master.new
      our_worker = Object.new

      master.workers.add       our_worker
      master.ready_workers.add our_worker
      master.worker_busy       our_worker

      master.ready_workers.wont_include our_worker
    end

    it "only affects a single worker" do
      master           = Maru::Master.new
      our_worker       = Object.new
      our_other_worker = Object.new

      master.workers.add       our_worker
      master.workers.add       our_other_worker
      master.ready_workers.add our_worker
      master.ready_workers.add our_other_worker
      master.worker_busy       our_worker

      master.ready_workers.wont_include our_worker
      master.ready_workers.must_include our_other_worker
    end

    it "immediately relinquishes any reserved offerings" # TODO
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
