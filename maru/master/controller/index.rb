require_relative '../../master'

module Maru
	class Master < Sinatra::Base
		get '/' do
			if logged_in?
				if @user.is_admin
					@groups = Group.all
				else
					@groups = (@user.groups.to_a + Group.all(:public => true).to_a).uniq
				end
			else
				@groups = Group.all(:public => true)
			end

			erb :index
		end

		get '/subscribe.event-stream' do
			content_type "text/event-stream"

			stream :keep_open do |out|
				socket = EventStreamSubscriber.new( @user, out )

				socket.onclose do
					settings.group_subscribers.delete socket
				end

				settings.group_subscribers << socket
			end
		end

		get '/subscribe.poll' do
			content_type "application/json"

			if params[:token]
				socket = LongPollSubscriber.get( params[:token] )

				if socket
					stream :keep_open do |out|
						socket.reconnect( out )
					end
				else
					[410, {reason: 'expired'}.to_json]
				end
			else
				stream :keep_open do |out|
					socket = LongPollSubscriber.new( @user, out )

					socket.onclose do
						settings.group_subscribers.delete socket
					end

					settings.group_subscribers << socket
				end
			end
		end
	end
end
