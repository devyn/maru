require_relative '../../master'

module Maru
	class Master < Sinatra::Base
		get '/admin' do
			must_be_admin!

			@title = "admin"
			@users = User.all

			erb :admin
		end
	end
end
