require 'minitest/autorun'
require 'maru/master/worker_client'

describe Maru::Master::WorkerClient do
  describe "#connection_terminated" do
    it "unregisters workers" do
      master = Minitest::Mock.new
      client = Maru::Master::WorkerClient.new master, nil, nil, nil

      master.expect :unregister_worker, nil, [Maru::Master::WorkerClient]

      client.connection_terminated

      master.verify
    end
  end

  describe "#command_READY" do
    it "dispatches Master#worker_ready" do
      master = Minitest::Mock.new
      client = Maru::Master::WorkerClient.new master, nil, nil, nil

      master.expect :worker_ready, nil, [Maru::Master::WorkerClient]
      client.command_READY
      master.verify
    end
  end

  describe "#command_BUSY" do
    it "dispatches Master#worker_busy" do
      master = Minitest::Mock.new
      client = Maru::Master::WorkerClient.new master, nil, nil, nil

      master.expect :worker_busy, nil, [Maru::Master::WorkerClient]
      client.command_BUSY
      master.verify
    end
  end
end
