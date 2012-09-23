require 'minitest/autorun'
require 'eventmachine'
require 'maru/protocol'

GOOGLE_CERT = <<-CERT
-----BEGIN CERTIFICATE-----
MIIF5DCCBU2gAwIBAgIKQJj2UwAAAABotjANBgkqhkiG9w0BAQUFADBGMQswCQYD
VQQGEwJVUzETMBEGA1UEChMKR29vZ2xlIEluYzEiMCAGA1UEAxMZR29vZ2xlIElu
dGVybmV0IEF1dGhvcml0eTAeFw0xMjA5MTMxMTU1MTRaFw0xMzA2MDcxOTQzMjda
MGYxCzAJBgNVBAYTAlVTMRMwEQYDVQQIEwpDYWxpZm9ybmlhMRYwFAYDVQQHEw1N
b3VudGFpbiBWaWV3MRMwEQYDVQQKEwpHb29nbGUgSW5jMRUwEwYDVQQDFAwqLmdv
b2dsZS5jb20wgZ8wDQYJKoZIhvcNAQEBBQADgY0AMIGJAoGBAMYPPL9uAqnHUj9z
0ukvqIheCm6Zdzv2xbHqvq9MfO950hU1BZZZaHE9uCxsN6C4rENbDGp9GJoBprU8
kgf2fvF5cHlOlsi5lX9RmfdI2WCzGF68EBghvsafQx1EqMYafV5153w/gHYX6K7s
JWq4afD2GKPn8InxfHxaDr8lgm1zAgMBAAGjggO3MIIDszAdBgNVHSUEFjAUBggr
BgEFBQcDAQYIKwYBBQUHAwIwHQYDVR0OBBYEFF2TbVO+t7y0MJpT+IXTOq9ukS7O
MB8GA1UdIwQYMBaAFL/AMOv1QxE+Z7qekfv8atrjaxIkMFsGA1UdHwRUMFIwUKBO
oEyGSmh0dHA6Ly93d3cuZ3N0YXRpYy5jb20vR29vZ2xlSW50ZXJuZXRBdXRob3Jp
dHkvR29vZ2xlSW50ZXJuZXRBdXRob3JpdHkuY3JsMGYGCCsGAQUFBwEBBFowWDBW
BggrBgEFBQcwAoZKaHR0cDovL3d3dy5nc3RhdGljLmNvbS9Hb29nbGVJbnRlcm5l
dEF1dGhvcml0eS9Hb29nbGVJbnRlcm5ldEF1dGhvcml0eS5jcnQwDAYDVR0TAQH/
BAIwADCCAn0GA1UdEQSCAnQwggJwggwqLmdvb2dsZS5jb22CCmdvb2dsZS5jb22C
DSoueW91dHViZS5jb22CC3lvdXR1YmUuY29tghYqLnlvdXR1YmUtbm9jb29raWUu
Y29tggh5b3V0dS5iZYILKi55dGltZy5jb22CDyouZ29vZ2xlLmNvbS5icoIOKi5n
b29nbGUuY28uaW6CCyouZ29vZ2xlLmVzgg4qLmdvb2dsZS5jby51a4ILKi5nb29n
bGUuY2GCCyouZ29vZ2xlLmZyggsqLmdvb2dsZS5wdIILKi5nb29nbGUuaXSCCyou
Z29vZ2xlLmRlggsqLmdvb2dsZS5jbIILKi5nb29nbGUucGyCCyouZ29vZ2xlLm5s
gg8qLmdvb2dsZS5jb20uYXWCDiouZ29vZ2xlLmNvLmpwggsqLmdvb2dsZS5odYIP
Ki5nb29nbGUuY29tLm14gg8qLmdvb2dsZS5jb20uYXKCDyouZ29vZ2xlLmNvbS5j
b4IPKi5nb29nbGUuY29tLnZugg8qLmdvb2dsZS5jb20udHKCDSouYW5kcm9pZC5j
b22CC2FuZHJvaWQuY29tghQqLmdvb2dsZWNvbW1lcmNlLmNvbYISZ29vZ2xlY29t
bWVyY2UuY29tghAqLnVybC5nb29nbGUuY29tggwqLnVyY2hpbi5jb22CCnVyY2hp
bi5jb22CFiouZ29vZ2xlLWFuYWx5dGljcy5jb22CFGdvb2dsZS1hbmFseXRpY3Mu
Y29tghIqLmNsb3VkLmdvb2dsZS5jb22CBmdvby5nbIIEZy5jb4INKi5nc3RhdGlj
LmNvbYIPKi5nb29nbGVhcGlzLmNuMA0GCSqGSIb3DQEBBQUAA4GBAJ4YTOfDm0q5
1ieqJyjhqys3nDFx1PvhqMhJ7B4lhzD0WIMDX8RWY8R4NSpTKaZrPFCfzPslWqkN
7haZ3IQE9a8r01CgxlH7r42HIEd5dSddX3RULtwKFjyS5V5IeWfTWFjQ0SnopuN7
3p7S3OqKTK+jbPUExFwLkPyhYufZq8Y9
-----END CERTIFICATE-----
CERT

YAHOO_CERT = <<-CERT
-----BEGIN CERTIFICATE-----
MIIE6jCCBFOgAwIBAgIDEIGKMA0GCSqGSIb3DQEBBQUAME4xCzAJBgNVBAYTAlVT
MRAwDgYDVQQKEwdFcXVpZmF4MS0wKwYDVQQLEyRFcXVpZmF4IFNlY3VyZSBDZXJ0
aWZpY2F0ZSBBdXRob3JpdHkwHhcNMTAwNDAxMjMwMDE0WhcNMTUwNzAzMDQ1MDAw
WjCBjzEpMCcGA1UEBRMgMmc4YU81d0kxYktKMlpENTg4VXNMdkRlM2dUYmc4RFUx
CzAJBgNVBAYTAlVTMRMwEQYDVQQIEwpDYWxpZm9ybmlhMRIwEAYDVQQHEwlTdW5u
eXZhbGUxFDASBgNVBAoTC1lhaG9vICBJbmMuMRYwFAYDVQQDEw13d3cueWFob28u
Y29tMIIBIjANBgkqhkiG9w0BAQEFAAOCAQ8AMIIBCgKCAQEA6ZM1jHCkL8rlEKse
1riTTxyC3WvYQ5m34TlFK7dK4QFI/HPttKGqQm3aVB1Fqi0aiTxe4YQMbd++jnKt
djxcpi7sJlFxjMZs4umr1eGo2KgTgSBAJyhxo23k+VpK1SprdPyM3yEfQVdV7JWC
4Y71CE2nE6+GbsIuhk/to+jJMO7jXx/430jvo8vhNPL6GvWe/D6ObbnxS72ynLSd
mLtaltykOvZEZiXbbFKgIaYYmCgh89FGVvBkUbGM/Wb5Voiz7ttQLLxKOYRj8Mdk
TZtzPkM9scIFG1naECPvCxw0NyMyxY3nFOdjUKJ79twanmfCclX2ZO/rk1CpiOuw
lrrr/QIDAQABo4ICDjCCAgowDgYDVR0PAQH/BAQDAgTwMB0GA1UdDgQWBBSmrfKs
68m+dDUSf+S7xJrQ/FXAlzA6BgNVHR8EMzAxMC+gLaArhilodHRwOi8vY3JsLmdl
b3RydXN0LmNvbS9jcmxzL3NlY3VyZWNhLmNybDCCAVsGA1UdEQSCAVIwggFOgg13
d3cueWFob28uY29tggl5YWhvby5jb22CDHVzLnlhaG9vLmNvbYIMa3IueWFob28u
Y29tggx1ay55YWhvby5jb22CDGllLnlhaG9vLmNvbYIMZnIueWFob28uY29tggxp
bi55YWhvby5jb22CDGNhLnlhaG9vLmNvbYIMYnIueWFob28uY29tggxkZS55YWhv
by5jb22CDGVzLnlhaG9vLmNvbYIMbXgueWFob28uY29tggxpdC55YWhvby5jb22C
DHNnLnlhaG9vLmNvbYIMaWQueWFob28uY29tggxwaC55YWhvby5jb22CDHFjLnlh
aG9vLmNvbYIMdHcueWFob28uY29tggxoay55YWhvby5jb22CDGNuLnlhaG9vLmNv
bYIMYXUueWFob28uY29tggxhci55YWhvby5jb22CDHZuLnlhaG9vLmNvbTAfBgNV
HSMEGDAWgBRI5mj5K9KylddH2CMgEE8zmJCf1DAdBgNVHSUEFjAUBggrBgEFBQcD
AQYIKwYBBQUHAwIwDQYJKoZIhvcNAQEFBQADgYEAp9WOMtcDMM5T0yfPecGv5QhH
RJZRzgeMPZitLksr1JxxicJrdgv82NWq1bw8aMuRj47ijrtaTEWXaCQCy00yXodD
zoRJVNoYIvY1arYZf5zv9VZjN5I0HqUc39mNMe9XdZtbkWE+K6yVh6OimKLbizna
inu9YTrN/4P/w6KzHho=
-----END CERTIFICATE-----
CERT

class TestCommandAcceptor
  def command_PING(str=nil)
    str ? ["PONG", str] : "PONG"
  end
end

describe Maru::Protocol do
  before do
    @protocol = Object.new
    @protocol.extend Maru::Protocol
  end

  describe "#post_init" do
    it "initializes TLS" do
      mock = Minitest::Mock.new

      @protocol.extend Module.new {
        define_method :start_tls do |*args|
          mock.start_tls(*args)
        end
      }

      mock.expect :start_tls, nil, [Hash]

      @protocol.post_init

      mock.verify
    end
  end

  describe "#ssl_handshake_completed" do
    it "rejects peers other than @verify_peer, if specified" do
      mock = Minitest::Mock.new

      @protocol.extend Module.new {
        define_method :close_connection do |*args|
          mock.close_connection(*args)
        end
        define_method :get_peer_cert do |*args|
          mock.get_peer_cert(*args)
        end
      }

      @protocol.verify_peer = YAHOO_CERT

      mock.expect :close_connection, nil
      mock.expect :get_peer_cert, GOOGLE_CERT

      @protocol.ssl_handshake_completed

      mock.verify
    end

    it "does not reject peers if they present the same certificate as @verify_peer" do
      mock = Minitest::Mock.new

      @protocol.extend Module.new {
        define_method :close_connection do |*args|
          raise "close_connection was called."
        end
        define_method :get_peer_cert do |*args|
          mock.get_peer_cert(*args)
        end
      }

      @protocol.verify_peer = GOOGLE_CERT

      mock.expect :get_peer_cert, GOOGLE_CERT

      @protocol.ssl_handshake_completed

      mock.verify
    end

    it "does not reject peers if @verify_peer is not specified" do
      @protocol.extend Module.new {
        define_method :close_connection do |*args|
          raise "close_connection was called."
        end
        define_method :get_peer_cert do |*args|
          raise "get_peer_cert was called."
        end
      }

      @protocol.ssl_handshake_completed
    end

    it "sets deferred status to [:succeeded] when connection has been established" do
      succeeded = false

      @protocol.callback do
        succeeded = true
      end

      @protocol.ssl_handshake_completed

      assert succeeded, "Callback was not invoked."
    end

    it "sets deferred status to [:failed] if the peer can not be verified" do
      failed = false

      @protocol.extend Module.new {
        define_method(:close_connection) { }
        define_method(:get_peer_cert)    { GOOGLE_CERT }
      }

      @protocol.verify_peer = YAHOO_CERT

      @protocol.errback do
        failed = true
      end

      @protocol.ssl_handshake_completed

      assert failed, "Errback was not invoked."
    end
  end

  describe "#receive_data" do
    it "invokes the interceptor if defined" do
      interceptor = Minitest::Mock.new
      @protocol.interceptor = interceptor

      interceptor.expect :call, nil, ["hello"]

      @protocol.receive_data "hello"

      interceptor.verify
    end

    it "invokes #parse if an interceptor is not defined" do
      mock = Minitest::Mock.new

      @protocol.extend Module.new {
        define_method :parse do |*args|
          mock.parse(*args)
        end
      }

      mock.expect :parse, nil, ["hello"]

      @protocol.receive_data "hello"

      mock.verify
    end
  end

  describe "#parse" do
    before do
      @protocol.parse_state      = :initial
      @protocol.parse_data       = {}
      @protocol.command_acceptor = Minitest::Mock.new
    end

    it "parses commands without triggers or arguments correctly" do
      @protocol.parse "/COMMAND "

      refute @protocol.parse_data.include?(:response_trigger), "parse data has a response trigger"

      @protocol.parse_data[:command_name].must_equal "COMMAND"
      @protocol.parse_data[:command_args].must_be :empty?

      @protocol.command_acceptor.expect :send, nil, ["command_COMMAND"]

      @protocol.parse "\n"
      @protocol.command_acceptor.verify
    end

    it "parses commands without triggers but with arguments correctly" do
      @protocol.parse "/HELLO 5:world"

      refute @protocol.parse_data.include?(:response_trigger), "parse data has a response trigger"

      @protocol.parse_data[:command_name].must_equal "HELLO"
      @protocol.parse_data[:command_args].must_equal ["world"]

      @protocol.command_acceptor.expect :send, nil, ["command_HELLO", "world"]

      @protocol.parse "\n"
      @protocol.command_acceptor.verify
    end

    it "parses arguments with spaces and newlines correctly" do
      @protocol.parse "/FOO 10:bar\nbaz da5:m r n"

      refute @protocol.parse_data.include?(:response_trigger), "parse data has a response trigger"

      @protocol.parse_data[:command_name].must_equal "FOO"
      @protocol.parse_data[:command_args].must_equal ["bar\nbaz da", "m r n"]

      @protocol.command_acceptor.expect :send, nil, ["command_FOO", "bar\nbaz da", "m r n"]

      @protocol.parse "\n"
      @protocol.command_acceptor.verify
    end

    it "parses commands with triggers but without arguments correctly" do
      @protocol.extend Module.new {
        define_method :send_command do |*args|
        end
      }

      @protocol.parse "5210/ROCK "

      @protocol.parse_data[:response_trigger].must_equal 5210
      @protocol.parse_data[:command_name].must_equal "ROCK"
      @protocol.parse_data[:command_args].must_be :empty?

      @protocol.command_acceptor.expect :send, nil, ["command_ROCK"]

      @protocol.parse "\n"
      @protocol.command_acceptor.verify
    end

    it "parses commands with triggers and arguments correctly" do
      @protocol.extend Module.new {
        define_method :send_command do |*args|
        end
      }

      @protocol.parse "2029/FIRE 4:your4:boss"

      @protocol.parse_data[:response_trigger].must_equal 2029
      @protocol.parse_data[:command_name].must_equal "FIRE"
      @protocol.parse_data[:command_args].must_equal ["your", "boss"]

      @protocol.command_acceptor.expect :send, nil, ["command_FIRE", "your", "boss"]

      @protocol.parse "\n"
      @protocol.command_acceptor.verify
    end
  end

  describe "#dispatch_parsed_command" do
    before do
      @protocol.command_acceptor = Minitest::Mock.new
    end

    it "dispatches methods according to command_name" do
      @protocol.parse_data = {:command_name => "HEART", :command_args => []}

      @protocol.command_acceptor.expect :send, nil, ["command_HEART"]

      @protocol.dispatch_parsed_command
      @protocol.command_acceptor.verify
    end

    it "dispatches methods case insensitively (always uppercase)" do
      @protocol.parse_data = {:command_name => "hEaRt", :command_args => []}

      @protocol.command_acceptor.expect :send, nil, ["command_HEART"]

      @protocol.dispatch_parsed_command
      @protocol.command_acceptor.verify
    end

    it "dispatches methods with command_args" do
      @protocol.parse_data = {:command_name => "LION", :command_args => ["giraffe"]}

      @protocol.command_acceptor.expect :send, nil, ["command_LION", "giraffe"]

      @protocol.dispatch_parsed_command
      @protocol.command_acceptor.verify
    end

    it "sends a RESULT command back when a response_trigger is specified" do
      mock = Minitest::Mock.new

      @protocol.extend Module.new {
        define_method :send_command do |*args|
          mock.send_command *args
        end
      }

      @protocol.parse_data = {:response_trigger => 40929, :command_name => "WIND", :command_args => []}

      @protocol.command_acceptor.expect :send, "it blows.", ["command_WIND"]
      mock.expect :send_command, nil, [:RESULT, 40929, "it blows."]

      @protocol.dispatch_parsed_command
      @protocol.command_acceptor.verify
      mock.verify
    end

    it "sends an ERROR command back if there is an error and there is a response_trigger" do
      mock = Minitest::Mock.new

      @protocol.extend Module.new {
        define_method :send_command do |*args|
          mock.send_command *args
        end
      }

      @protocol.parse_data = {:response_trigger => 4, :command_name => "FOOTBALL", :command_args => []}

      @protocol.command_acceptor = Object.new

      class << @protocol.command_acceptor
        def command_FOOTBALL
          raise RuntimeError, "rugby"
        end
      end

      mock.expect :send_command, nil, [:ERROR, 4, "RuntimeError", "rugby"]

      @protocol.dispatch_parsed_command
      mock.verify
    end

    it "handles incoming RESULT commands by invoking the appropriate trigger" do
      @protocol.parse_data = {:command_name => "RESULT", :command_args => ["404", "your mother"]}

      mock = Minitest::Mock.new

      @protocol.triggers = {404 => mock}

      mock.expect :set_deferred_status, nil, [:succeeded, "your mother"]

      @protocol.dispatch_parsed_command

      mock.verify
    end

    it "handles incoming ERROR commands by invoking the appropriate trigger" do
      @protocol.parse_data = {:command_name => "ERROR", :command_args => ["500", "SuckError", "you suck"]}

      mock = Minitest::Mock.new

      @protocol.triggers = {500 => mock}

      mock.expect :set_deferred_status, nil, [:failed, "SuckError", "you suck"]

      @protocol.dispatch_parsed_command

      mock.verify
    end
  end

  describe "#send_command" do
    before do
      @out = out = StringIO.new

      @protocol.extend Module.new {
        define_method :send_data do |data|
          out.write data
        end
      }

      @protocol.triggers = {}
      @protocol.trigger_index = 1
    end

    it "writes commands with no arguments and no trigger" do
      @protocol.send_command :HELLO

      @out.string.must_equal "/HELLO\n"
    end

    it "writes commands with arguments but no trigger" do
      @protocol.send_command :HELLO, "a", "b"

      @out.string.must_equal "/HELLO 1:a1:b\n"
    end

    it "writes commands with a trigger but no arguments, and registers them" do
      @protocol.send_command(:RAWR) { "block" }

      @out.string.must_equal "1/RAWR\n"

      assert @protocol.triggers[1], "Trigger was not defined"
    end

    it "writes commands with a trigger and arguments, and registers them" do
      @protocol.send_command(:RAWR, "hi", "how", "are", "you") { "block" }

      @out.string.must_equal "1/RAWR 2:hi3:how3:are3:you\n"

      assert @protocol.triggers[1], "Trigger was not defined"
    end
  end

  it "runs server-side" do
    expected_response = "/RESULT 1:14:PONG3:baz\n/RESULT 1:24:PONG\n"
    complete = false

    EventMachine.run do
      EventMachine.add_timer 3 do
        raise "Task did not complete within 3 seconds."
      end

      EventMachine.start_server "127.0.0.1", 50399, Maru::Protocol do |conn|
        conn.command_acceptor = TestCommandAcceptor.new
      end

      EventMachine.connect "127.0.0.1", 50399, Module.new {
        define_method :post_init do
          @data = []
          start_tls
        end

        define_method :ssl_handshake_completed do
          send_data "1/PING 3:baz\n"
          send_data "2/PING\n"
        end

        define_method :receive_data do |data|
          @data << data

          # Check whether the sum of the lengths in @data are greater than or equal to our
          # expected response length
          if @data.inject(0) { |l,d| l + d.length } >= expected_response.length
            response = @data.join(nil)
            response.must_equal expected_response

            complete = true
            EventMachine.stop_event_loop
          end
        end
      }
    end

    assert complete, "Task did not complete."
  end

  it "runs client-side" do
    expected_request = "1/PING 3:baz\n2/PING\n"
    complete = false

    EventMachine.run do
      EventMachine.add_timer 3 do
        raise "Task did not complete within 3 seconds."
      end

      EventMachine.start_server "127.0.0.1", 50399, Module.new {
        define_method :post_init do
          @data = []
          start_tls
        end

        define_method :receive_data do |data|
          @data << data

          if @data.inject(0) { |l,d| l + d.length } >= expected_request.length
            request = @data.join(nil)
            request.must_equal expected_request

            send_data "/RESULT 1:14:PONG3:baz\n"
            send_data "/RESULT 1:24:PONG\n"
          end
        end
      }

      EventMachine.connect "127.0.0.1", 50399, Maru::Protocol do |conn|
        conn.callback do
          conn.send_command :PING, "baz" do |result|
            result.callback do |pong, baz|
              pong.must_equal "PONG"
              baz.must_equal "baz"
            end
          end

          conn.send_command :PING do |result|
            result.callback do |pong|
              pong.must_equal "PONG"
              complete = true
              EventMachine.stop_event_loop
            end
          end
        end
      end
    end

    assert complete, "Task did not complete."
  end
end
