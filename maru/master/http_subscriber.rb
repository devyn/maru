require_relative '../master'

module Maru
	class Master < Sinatra::Base
		class HTTPSubscriber
			attr_reader :user

			def initialize(user, out)
				@user = user
				@out  = out

				@out.errback do
					close
				end
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
			def send(msg)
				@out << "data: " + msg + "\n\n"
			end

			def send_keepalive
				@out << ":\n"
			end
		end

		class LongPollSubscriber < HTTPSubscriber
			def send(msg)
				@out << msg
				close
			end

			def send_keepalive
				@out << "\0"
			end
		end
	end
end
