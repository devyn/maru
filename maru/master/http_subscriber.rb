require_relative '../master'

module Maru
	class Master < Sinatra::Base
		class HTTPSubscriber
			attr_reader :user

			def initialize(user, out)
				@user = user
				@out  = out
			end

			def onclose(&blk)
				@close = blk
			end

			def close
				@out.close rescue nil
				@close.call if @close
			end
		end

		class EventStreamSubscriber < HTTPSubscriber
			def initialize(user, out)
				super(user, out)

				@out.errback { close }
			end

			def send(msg)
				@out << "data: " + msg + "\n\n"
			end

			def send_keepalive
				@out << ":\n"
			end
		end

		class LongPollSubscriber < HTTPSubscriber
			@@token_table = {}

			def self.get(token)
				@@token_table[token]
			end

			def initialize(user, out)
				super(user, out)

				@token = rand(36**12).to_s(36)
				@queue = []

				@@token_table[@token] = self

				EM.next_tick { send( { type: "setToken", token: @token }.to_json ) }
			end

			def send(msg)
				if @out and @queue.empty?
					@out << msg
					disconnect
				else
					@queue << msg
				end
			end

			def send_keepalive
				@out << "\0" if @out
			end

			def reconnect(out)
				EM.cancel_timer(@timer) if @timer

				@out   = out
				@timer = nil

				if !@queue.empty?
					@out << @queue.shift
					disconnect
				end
			end

			def disconnect
				@out.close

				@out   = nil
				@timer = EM.add_timer(120) { close }
			end

			def close
				EM.cancel_timer(@timer) if @timer

				@timer = nil

				@@token_table.delete @token

				super
			end
		end
	end
end
