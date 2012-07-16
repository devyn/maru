require 'sinatra/base'
require 'json'
require 'data_mapper'
require 'fileutils'
require 'openssl'
require 'erubis'
require 'rdiscount'
require 'eventmachine'

require_relative 'version'
require_relative 'plugin'
require_relative 'log'

module Maru
	class Master < Sinatra::Base
		require_relative 'master/model/group'
		require_relative 'master/model/job'
		require_relative 'master/model/worker'
		require_relative 'master/model/user'

		DataMapper.finalize

		require_relative 'master/http_subscriber'

		enable :static

		set    :root,          File.join( File.dirname( __FILE__ ), '..' )

		set    :views,         -> { File.join( root, 'views'  ) }
		set    :public_folder, -> { File.join( root, 'static' ) }

		set    :erubis,        :escape_html => true

		set    :filestore,     nil

		set    :group_subscribers, []

		configure do
			DataMapper.setup( :default, ENV["DATABASE_URL"] || "sqlite://#{Dir.pwd}/maru.db" )
			DataMapper.auto_upgrade!

			if User.all.empty?
				User.create :email => "maru@example.com", :password => "maru", :is_admin => true
			end

			EM.next_tick do
				@@expiry_check = EM.add_periodic_timer(60) do
					begin
						Job.all( :worker.not => nil, :completed_at => nil ).each do |job|
							if Time.now - job.assigned_at.to_time > job.expiry
								Log.info "#{job} has expired. Reaping."
								job.update :worker => nil
							end
						end
					rescue
						next
					end
				end

				@@keep_alive = EM.add_periodic_timer(25) do
					settings.group_subscribers.each do |s|
						s.send_keepalive rescue next
					end
				end

				Log.info "maru master #{Maru::VERSION} (https://github.com/devyn/maru/) fired up and ready to go."
			end
		end

		before do
			if session[:user] and session[:user_authenticated_at]
				@user = User.first( :id => session[:user], :invalid_before.lt => session[:user_authenticated_at] )
			end

			if session[:worker] and session[:worker_authenticated_at]
				@worker = Worker.first( :id => session[:worker], :invalid_before.lt => session[:worker_authenticated_at], :user.not => nil )
			end
		end

		require_relative 'master/helpers'

		require_relative 'master/controller/index'
		require_relative 'master/controller/group'
		require_relative 'master/controller/user'
		require_relative 'master/controller/admin'
		require_relative 'master/controller/worker_api'
	end
end

Maru::Master.run! if __FILE__ == $0
