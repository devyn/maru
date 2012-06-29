require 'json'
require 'eventmachine'
require 'digest'
require 'socket'

module Maru
	module Protocol
		module Host
			def initialize
				@buffer = []
			end

			def receive_data(data)
				if idx = data.index("\n")
					buf = @buffer
					buf << data.slice!(0..idx)
					@buffer = [data]
					buf = buf.join("").strip
					if buf.empty?
						return
					else
						handle_json JSON.parse(buf)
					end
				else
					@buffer << data
				end
			rescue JSON::ParserError
				close_connection
			end

			def handle_json(json)
				log_request json

				ret = ->(*response) {
					log_response json, response
					tell :event => :response, :method => json["method"], :id => json["id"], :response => response
				}

				begin
					case json["method"]
					when "new_session"
						new_session &ret
					when "load_session"
						load_session json["session_id"], &ret
					when "clear_session"
						clear_session &ret
					when "set_kinds"
						set_kinds json["kinds"], &ret
					when "ready"
						ready &ret
					when "busy"
						busy &ret
					when "accept"
						accept &ret
					when "complete"
						complete &ret
					when "forfeit"
						forfeit &ret
					when "create_group"
						create_group json["group"], &ret
					when "cause_err"
						raise "error!"
					else
						ret.(:err, "unknown method")
					end
				rescue Exception => e
					log_error e
					ret.(:err, e.message)
				end
			end

			def offer(job)
				tell_raw %{{"event":"offering","job":#{job}}}
			end

			def tell(json)
				tell_raw json.to_json
			end

			def tell_raw(data)
				send_data data
				send_data "\n"
			end

			def log_request(req)
				req_ = req.dup
				req_.delete "id"
				req_.delete "method"
				warn "#{Time.now}\t#{ip}\t\e[36m#{req["method"]}#{req["id"] ? "/#{req["id"]}" : ""}\e[0m\t<<\t#{req_.to_json}"
			end

			def log_response(req, res)
				warn "#{Time.now}\t#{ip}\t\e[36m#{req["method"]}#{req["id"] ? "/#{req["id"]}" : ""}\e[0m\t>>\t#{res.to_json}"
			end

			def log_error(err)
				warn "\e[31m#{Time.now}\t#{ip}\t#{err.class.name}: #{err.message}\e[0m"

				err.backtrace.each do |bt|
					warn "\e[31m\t\t\t#{bt}\e[0m"
				end
			end

			def ip
				si = Socket.unpack_sockaddr_in(get_peername)
				return si[1]
			end
		end

		class Client < EventMachine::Connection
		end
	end
end

