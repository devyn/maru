require 'json'
require 'eventmachine'
require 'digest'

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
					handle_json JSON.parse(buf.join(""))
				else
					@buffer << data
				end
			end

			def handle_json(json)
				p json

				ret = ->(*response) {
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
					end
				rescue Exception => e
					p e
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
		end

		class Client < EventMachine::Connection
		end
	end
end

