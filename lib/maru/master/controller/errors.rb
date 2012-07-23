require_relative '../../master'

module Maru
	class Master < Sinatra::Base
		error 400 do
			@error_name = "400 Bad Request"
			@error_message = "The client sent something that doesn't make sense."

			erb :error
		end

		error 403 do
			@error_name = "403 Forbidden"
			@error_message = "You are not authorized to see this."

			erb :error
		end

		error 404 do
			@error_name = "404 Not Found"
			@error_message = "The resource does not appear to exist."

			erb :error
		end

		error do
			@error_name = "500 Internal Server Error"
			@error_message = "Something strange happened. The error has been logged."

			Log.exception env['sinatra.error']

			erb :error
		end

		get '/test_error' do
			raise "I'm an error!"
		end

		get '/test_420' do
			420
		end
	end
end
