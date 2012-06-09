require 'json'
require 'eventmachine'
require 'digest'

module Maru
	module Protocol
		module Host
			def initialize
				@state  = [:json]
				@buffer = []
			end

			def receive_data(data)
				case @state[0]
				when :json
					if idx = data.index("\n")
						buf = @buffer
						buf << data.slice!(0..idx)
						@buffer = [data]
						handle_json JSON.parse(buf.join(""))
					else
						@buffer << data
					end
				when :files
					file, length, more, callback = @state[1..4]

					if data.length >= length
						file.write data.slice!(0,length)
						file.close

						@buffer = [data]
						start_files more, &callback
					else
						file.write data
						@state[2] -= data.length
					end
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
					when "upload_files"
						upload_files json["files"], &ret
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

			def start_files(files, &callback)
				if m = files.shift
					@state = [:files, File.open(self.file_output_path(m["name"]), "wb"), m["length"], files, callback]
					@state[1].write @buffer.shift until @buffer.empty?
				else
					@state = [:json]
					callback.call
				end
			end
		end

		class Client < EventMachine::Connection
		end
	end
end

