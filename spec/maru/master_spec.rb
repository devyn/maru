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

describe Maru::Master::Client do
  describe "#connection_terminated" do
    it "unregisters workers" do
      master = Minitest::Mock.new
      client = Maru::Master::Client.new master, nil

      client.instance_eval { @role = :worker }

      master.expect :unregister_worker, nil, [Maru::Master::Client]

      client.connection_terminated

      master.verify
    end
  end

  describe "#command_IDENTIFY" do
    it "refuses unknown roles with ArgumentError" do
      client = Maru::Master::Client.new nil, nil

      proc { client.command_IDENTIFY "AOI", "sora.1" }.must_raise ArgumentError
    end

    it "refuses to identify an already identified client" do
      client = Maru::Master::Client.new nil, nil

      client.instance_eval { @role = :bogus }

      proc { client.command_IDENTIFY "BOGUS2" }.must_raise StandardError
    end

    it "can register those that identify as WORKERs" do
      master = Minitest::Mock.new
      client = Maru::Master::Client.new master, nil

      master.expect :register_worker, nil, [Maru::Master::Client]

      client.command_IDENTIFY "WORKER", "rah.example.com:1", "jon.dee@example.com"

      master.verify

      client.name.must_equal "rah.example.com:1"
      client.owner.must_equal "jon.dee@example.com"
    end
  end

  describe "#must_be_worker!" do
    before do
      @client = Maru::Master::Client.new nil, nil
    end

    it "accepts workers" do
      @client.instance_eval { @role = :worker }
      @client.must_be_worker!
    end

    it "refuses workers by raising InsufficientCredentialsError" do
      proc { @client.must_be_worker! }.must_raise InsufficientCredentialsError
    end
  end
end
