require 'minitest/autorun'
require 'maru/master/basic_client'

describe Maru::Master::BasicClient do
  describe "#command_IDENTIFY" do
    it "refuses unknown roles with ArgumentError" do
      client = Maru::Master::BasicClient.new nil, nil

      proc { client.command_IDENTIFY "AOI", "sora.1" }.must_raise ArgumentError
    end

    it "can register those that identify as WORKERs" do
      master = Minitest::Mock.new
      conn   = Minitest::Mock.new
      client = Maru::Master::BasicClient.new master, conn

      master.expect :register_worker,   nil, [Maru::Master::WorkerClient]
      conn.expect   :command_acceptor=, nil, [Maru::Master::WorkerClient]

      client.command_IDENTIFY "WORKER", "rah.example.com:1", "jon.dee@example.com"

      master.verify
      conn.verify
    end
  end
end
