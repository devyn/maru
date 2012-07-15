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

class Numeric
	def humanize_seconds
		days    = self / 86400
		hours   = self % 86400 / 3600
		minutes = self % 3600 / 60
		seconds = self % 60

		out = []
		out << "#{days.floor} day#{'s' unless days == 1}"          if days    >= 1
		out << "#{hours.floor} hour#{'s' unless hours == 1}"       if hours   >= 1
		out << "#{minutes.floor} minute#{'s' unless minutes == 1}" if minutes >= 1
		out << "%.1f second#{'s' unless seconds == 1}" % seconds   if out.empty? or (hours < 1 and seconds >= 0)

		if out.empty?
			"0 seconds"
		elsif out.size == 1
			out.first
		else
			"#{out[0..-2].join(", ")} and #{out.last}"
		end
	end
end

class Maru::BasicFilestore
	attr_accessor :base_path, :base_url

	def initialize(base_path, base_url)
		@base_path, @base_url = base_path, base_url
	end

	def store_prerequisite(input, name, group)
		base        = File.join(@base_path, group.id.to_s, "prerequisites")
		target_path = File.join(base, name)

		if verify_path(base, target_path)
			FileUtils.mkdir_p(File.dirname(target_path))
			IO::copy_stream input, target_path

			File.chmod(0666 & ~File.umask, target_path) # see issue #15 

			url    = @base_url.chomp('/') + "/#{group.id}/prerequisites/#{name}"
			sha256 = OpenSSL::Digest::SHA256.file(target_path).hexdigest

			return [url, sha256]
		else
			raise SecurityViolation, "The name of the prerequisite to be stored led into a restricted area."
		end
	end

	def delete_prerequisite(name, group)
		base        = File.join(@base_path, group.id.to_s, "prerequisites")
		target_path = File.join(base, name)

		if verify_path(base, target_path)
			File.unlink(target_path) if File.file? target_path
		else
			raise SecurityViolation, "The name of the prerequisite to be stored led into a restricted area."
		end
	end

	def store_result(input, name, group)
		base        = File.join(@base_path, group.id.to_s, "results")
		target_path = File.join(base, name)

		if verify_path(base, target_path)
			FileUtils.mkdir_p(File.dirname(target_path))
			IO::copy_stream input, target_path

			File.chmod(0666 & ~File.umask, target_path) # see issue #15

			url    = @base_url.chomp('/') + "/#{group.id}/results/#{name}"
			sha256 = OpenSSL::Digest::SHA256.file(target_path).hexdigest

			return [url, sha256]
		else
			raise SecurityViolation, "The name of the result to be stored led into a restricted area."
		end
	end

	def delete_result(name, group)
		base        = File.join(@base_path, group.id.to_s, "results")
		target_path = File.join(base, name)

		if verify_path(base, target_path)
			File.unlink(target_path) if File.file? target_path
		else
			raise SecurityViolation, "The name of the result to be stored led into a restricted area."
		end
	end

	def results_path(group)
		return @base_url.chomp('/') + "/#{group.id}/results/"
	end

	def clean(group)
		path = File.join(@base_path, group.id.to_s)

		if File.directory? path
			FileUtils.rm_r path
		end
	end

	class SecurityViolation < Exception; end

	private

	def verify_path(base, path)
		base, path = File.expand_path(base), File.expand_path(path)

		path[0, base.size] == base
	end
end

class Maru::Master < Sinatra::Base
	class Group
		include DataMapper::Resource

		belongs_to :user

		has n, :jobs, :constraint => :destroy

		property :id,            Serial
		property :name,          String,  :required => true, :length  => 255
		property :details,       Json,    :default  => {}
		property :paused,        Boolean, :required => true, :default => false

		property :kind,          String,  :required => true, :length  => 255

		property :public,        Boolean, :required => true, :default => false

		property :prerequisites, Json,    :default => []

		property :average_job_time,          Float
		property :average_amount_of_workers, Float

		timestamps :created_at

		def to_s
			"##{self.id} (#{self.name})"
		end

		def estimated_time_left
			current     = jobs(:completed_at => nil).length
			most_recent = jobs(:completed_at.not => nil, :order => [:completed_at.desc]).first

			if current == 0
				"none"
			elsif most_recent.nil? or average_job_time.nil? or average_amount_of_workers.nil?
				"unknown"
			else
				if (t = average_job_time * current / average_amount_of_workers - (Time.now - most_recent.completed_at.to_time)) > 0
					t.humanize_seconds
				else
					"unknown"
				end
			end
		end
	end

	class Job
		include DataMapper::Resource

		belongs_to :group
		belongs_to :worker, :required => false

		property :id,            Serial
		property :name,          String,   :required => true, :length => 255
		property :details,       Json,     :default  => {}

		property :expiry,        Integer,  :required => true, :default => 3600 # in seconds after assigned_at

		property :prerequisites, Json,     :default => []

		property :assigned_at,   DateTime
		property :completed_at,  DateTime

		def to_s
			"##{self.id} (#{self.group.name} / #{self.name})"
		end
	end

	class Worker
		include DataMapper::Resource

		belongs_to :user, :required => false

		has n, :jobs

		property :id,             Serial
		property :name,           String, :required => true, :length => 128, :unique  => true # The name of the worker.
		property :authenticator,  String, :required => true, :length => 24,  :default => proc { rand(36**24).to_s(36) }
		                                  # The key, but we can't call it that.

		# Session revocation
		property :invalid_before, DateTime, :required => true, :default => proc { Time.now }

		def to_s
			self.name
		end
	end

	class User
		include DataMapper::Resource

		has n, :workers
		has n, :groups,  :constraint => :destroy

		property :id,            Serial
		property :email,         String, :required => true, :length => 255, :unique => true
		property :password_hash, String, :required => true, :length => 64
		property :password_salt, String, :required => true, :length => 4

		# Permissions
		property :can_own_workers,  Boolean, :required => true, :default => false
		property :can_own_groups,   Boolean, :required => true, :default => false
		property :is_admin,         Boolean, :required => true, :default => false

		# Session revocation
		property :invalid_before, DateTime, :required => true, :default => Time.at(0)

		validates_format_of :email, :as => :email_address

		def password=(pass)
			self.password_salt = rand( 36 ** 4 ).to_s( 36 )
			self.password_hash = OpenSSL::HMAC.hexdigest( OpenSSL::Digest::SHA256.new, self.password_salt, pass )
		end

		def password_is?(pass)
			OpenSSL::HMAC.hexdigest( OpenSSL::Digest::SHA256.new, self.password_salt, pass ) == self.password_hash
		end

		def to_s
			email
		end
	end

	DataMapper.finalize

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

	helpers do
		def get_worker
			@worker
		end

		def get_worker!
			get_worker or halt(403, {"Content-Type" => "text/plain"}, "Who are you? Worker, authenticate!")
		end

		def logged_in?
			!@user.nil?
		end

		def must_be_logged_in!
			redirect to('/user/login') if not logged_in?
		end

		def must_be_able_to_own_groups!
			must_be_logged_in!
			redirect to('/') unless @user.is_admin or @user.can_own_groups
		end

		def must_be_able_to_own_workers!
			must_be_logged_in!
			redirect to('/') unless @user.is_admin or @user.can_own_workers
		end

		def must_be_able_to_manage_users!
			must_be_logged_in!
			redirect_to('/') unless @user.is_admin or @user.can_manage_users
		end

		def must_be_admin!
			must_be_logged_in!
			redirect_to('/') unless @user.is_admin
		end

		def update_group_status(group)
			complete   = group.jobs( :completed_at.not => nil ).length
			processing = group.jobs( :worker.not => nil, :completed_at => nil ).map { |job| {:name => job.name, :worker => job.worker.name} }
			total      = group.jobs.length

			settings.group_subscribers.each do |socket|
				next if !group.public and not (socket.user == group.user or socket.user.is_admin)

				socket.send( { type: "groupStatus", groupID: group.id, complete: complete, processing: processing, total: total, estimatedTimeLeft: group.estimated_time_left }.to_json )
			end
		end
	end

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

		stream :keep_open do |out|
			socket = LongPollSubscriber.new( @user, out )

			socket.onclose do
				settings.group_subscribers.delete socket
			end

			settings.group_subscribers << socket
		end
	end

	get '/user/login' do
		@title = "log in"

		redirect to('/') if logged_in?
		erb :user_login
	end

	post '/user/login' do
		@title = "log in"

		if user = User.first( :email => params[:email] )
			if user.password_is? params[:password]
				session[:user] = user.id
				session[:user_authenticated_at] = Time.now
				redirect to('/')
			else
				@error = "Wrong email or password."
				erb :user_login
			end
		else
			@error = "Wrong email or password."
			erb :user_login
		end
	end

	get '/user/logout' do
		session[:user] = nil
		redirect to('/')
	end

	get '/admin' do
		must_be_admin!

		@title = "admin"
		@users = User.all

		erb :admin
	end

	post '/worker/new' do
		must_be_able_to_own_workers!

		@worker = Worker.new :user => @user, :name => params[:name]

		content_type "application/json"
		if @worker.save
			{:worker => @worker}.to_json
		else
			if w = Worker.get( :name => params[:name], :user => nil )
				@worker = w

				@worker.user = @user

				if @worker.save
					{:worker => @worker}.to_json
				else
					halt 400, {:errors => @worker.errors.full_messages}.to_json
				end
			else
				halt 400, {:errors => @worker.errors.full_messages}.to_json
			end
		end
	end

	post '/worker/:id/key/regenerate' do
		must_be_able_to_own_workers!

		@worker = Worker.get(params[:id])

		halt 404 unless @worker
		halt 403 unless @user.is_admin or @user == @worker.user

		@worker.authenticator = rand(36**24).to_s(36)
		@worker.invalid_before = Time.now

		content_type "application/json"
		if @worker.save
			{:worker => @worker}.to_json
		else
			halt 400, {:errors => @worker.errors.full_messages}.to_json
		end
	end

	delete '/worker/:id' do
		must_be_able_to_own_workers!

		@worker = Worker.get(params[:id])

		halt 404 unless @worker
		halt 403 unless @user.is_admin or @user == @worker.user

		if @worker.destroy
			halt 204 # no content
		else
			# forfeit all jobs the worker is currently working on
			@worker.jobs( :completed_at => nil ).update :worker => nil, :assigned_at => nil

			if @worker.update :user => nil
				halt 204
			else
				halt 500
			end
		end
	end

	post '/user/new' do
		must_be_admin!

		@new_user = User.create :email => params[:email], :password => params[:password]

		content_type 'application/json'
		if @new_user.valid?
			%{{"user":#{@new_user.to_json( :only => [ :id, :email, :can_own_groups, :can_own_workers, :is_admin ] )}}}
		else
			# vuuuuub
			halt 400, {:errors => @new_user.errors.full_messages}.to_json
		end
	end

	put '/user/:id/permission/:field' do
		must_be_admin!

		halt 404 unless @target_user = User.get(params[:id])
		halt 404 unless %w(can_own_groups can_own_workers is_admin).include? params[:field]

		request.body.rewind

		@target_user[params[:field]] = request.body.read.strip

		content_type 'application/json'
		if @target_user.save
			halt 204
		else
			halt 400, {:errors => @target_user.errors.full_messages}.to_json
		end
	end

	get '/user/preferences' do
		must_be_logged_in!

		@title       = "preferences"
		@target_user = @user

		erb :user_preferences
	end

	get '/user/:id/login' do
		must_be_admin!

		if user = User.get(params[:id])
			session[:user] = user.id
			session[:authenticated_at] = Time.now
			redirect to('/')
		else
			halt 404, "not found"
		end
	end

	get '/user/:id/preferences' do
		must_be_admin!

		halt 404 unless @target_user = User.get(params[:id])

		erb :user_preferences
	end

	post '/user/:id/password' do
		must_be_logged_in!

		halt 404 unless @target_user = User.get(params[:id])
		halt 400 unless params[:new_password] == params[:confirm_password]

		if @user == @target_user
			if @user.password_is? params[:current_password]
				@user.password = params[:new_password]
				halt 500 if !@user.save
			else
				halt 400
			end
		elsif @user.is_admin
			@target_user.password = params[:new_password]
			halt 500 if !@target_user.save
		else
			halt 403
		end
	end

	post '/user/:id/logout' do
		must_be_logged_in!

		halt 404 unless @target_user = User.get(params[:id])
		halt 403 unless @user == @target_user or @user.is_admin

		if @target_user.update :invalid_before => Time.now
			session[:authenticated_at] = Time.now if @user == @target_user
			halt 204 # no content
		else
			halt 500
		end
	end

	delete '/user/:id' do
		must_be_logged_in!

		halt 404 unless @target_user = User.get(params[:id])
		halt 403 unless @target_user == @user or @user.is_admin

		User.transaction do
			@target_user.workers.each do |worker|
				if worker.destroy == false
					if worker.update :user => nil
						worker.jobs( :completed_at => nil ).update :worker => nil, :assigned_at => nil
					else
						raise
					end
				end
			end

			# No idea why I have to do this. Apparently destroying the workers makes the user object immutable.
			User.get(@target_user.id).destroy or raise
		end

		session[:user] = nil if @target_user == @user

		halt 204
	end

	get '/group/new' do
		must_be_able_to_own_groups!

		@title = "submit work"

		erb :group_new
	end

	get '/group/new/form/*' do |kind|
		content_type "application/x-json-and-html-separated-by-zero-byte"

		halt 404 unless plugin = Maru::Plugin[kind]

		f = Maru::Plugin::GroupFormBuilder.new

		plugin.build_group_form(f)

		%'#{f.restrictions.to_json}\0#{f.html}'
	end

	post '/group/new' do
		must_be_able_to_own_groups!

		if params[:kind].nil? or !(plugin = Maru::Plugin[params[:kind]])
			@error = "- unsupported group kind"
			halt 400, erb(:group_new)
		end

		group        = Group.new
		group.user   = @user
		group.kind   = params[:kind]
		group.public = params[:public] ? true : false

		if !(errors = plugin.validate_group_params(params)).empty?
			@error = errors.map { |e| "- #{e}" }.join("\n")
			halt 400, erb(:group_new)
		end

		group_builder = Maru::Plugin::GroupBuilder.new group, settings.filestore

		plugin.build_group(group_builder, params)

		if group_builder.save
			redirect to('/')
		else
			@error = group.errors.full_messages.map { |e| "- #{e}" }.join("\n")
			halt 400, erb(:group_new)
		end
	end

	get '/group/:id.json' do
		# Returns information about a group in JSON format, for automation purposes
		halt 501
	end

	get '/group/:id/edit' do
		# Form for editing groups
		# Not all group kinds may be editable
		halt 501
	end

	post '/group/:id' do
		# Edits/updates a group
		halt 501
	end

	post '/group/:id/pause' do
		must_be_able_to_own_groups!

		halt 404 unless @group = Group.get(params[:id])
		halt 403 unless @group.user == @user or @user.is_admin

		if @group.update :paused => true
			halt 204
		else
			halt 500
		end
	end

	post '/group/:id/resume' do
		must_be_able_to_own_groups!

		halt 404 unless @group = Group.get(params[:id])
		halt 403 unless @group.user == @user or @user.is_admin

		if @group.update :paused => false
			halt 204
		else
			halt 500
		end
	end

	delete '/group/:id' do
		must_be_able_to_own_groups!

		halt 404 unless @group = Group.get(params[:id])
		halt 403 unless @group.user == @user or @user.is_admin

		if @group.destroy
			if settings.filestore.respond_to? :clean
				settings.filestore.clean @group
			end

			halt 204
		else
			halt 500
		end
	end

	get '/group/:id/details' do
		if @group = Group.get(params[:id])
			erb :details, :layout => false
		else
			halt 404
		end
	end

	# The following should check the user agent to ensure it's a Maru worker and not a browser

	get '/worker/authenticate' do
		content_type "text/plain"

		session[:challenge] = rand(36**20).to_s(36)
	end

	post '/worker/authenticate' do
		content_type "text/plain"

		if session[:challenge]
			target = Worker.first :name => params[:name], :user.not => nil

			if target and params[:response] == OpenSSL::HMAC.hexdigest(OpenSSL::Digest::SHA256.new, target.authenticator, session[:challenge])
				session[:worker]                  = target.id
				session[:worker_authenticated_at] = Time.now
				session[:challenge]               = nil
				"Authentication successful."
			else
				session[:challenge] = nil
				halt 403, "Authentication failed. You'll have to get another challenge."
			end
		else
			halt 400, "You must first obtain a challenge. (GET /worker/authenticate)"
		end
	end

	get '/job' do
		content_type "application/json"

		worker = get_worker!

		jobs = Job.all :worker => nil, :group => { :kind => params[:kinds].split( ',' ), :paused => false }

		unless params[:blacklist].to_s.empty?
			jobs = jobs.all :id.not => params[:blacklist].split( ',' ).map( &:to_i )
		end

		job = jobs.first :offset => rand(jobs.count)

		if job.nil?
			halt 204, JSON.dump( :error => "no jobs available" )
		else
			job.update :worker => worker, :assigned_at => Time.now

			Log.info "Job #{job} assigned to #{worker}"

			EM.next_tick { update_group_status job.group }

			%{{"job":#{job.to_json( :exclude => [:worker_id, :user_id], :relationships => {:group => {:relationships => {:user => {:only => [:email]}}}} )}}}
		end
	end

	post '/job/:id' do
		content_type "application/json"

		begin
			worker = get_worker!

			job = Job.first :id => params[:id], :worker => worker

			result_url = nil

			if job.nil?
				halt 404, JSON.dump( :error => "job not found" )
			else
				params[:files] = [params[:files]] if params[:files].is_a? Hash

				params[:files].each do |file|
					begin
						if settings.filestore.respond_to? :store_result
							file["data"][:tempfile].rewind

							result_url, sha256 = settings.filestore.store_result file["data"][:tempfile], file["name"], job.group

							if file["sha256"] and file["sha256"] != sha256
								settings.filestore.delete_result file["name"], job.group
								halt 400, JSON.dump( :error => "SHA256 invalid for #{file["name"]}" )
							end
						else
							# discard it with a warning
							Log.warn "#{job}: result discarded because filestore is unable to store it"
						end
					ensure
						file["data"][:tempfile].close
					end
				end unless params[:files].nil?

				job.update :completed_at => Time.now

				group = job.group
				dt    = job.completed_at.to_time - job.assigned_at.to_time
				w     = group.jobs(:worker.not => nil, :completed_at => nil).length + 1

				if group.average_job_time.nil?
					group.average_job_time = dt
				else
					group.average_job_time = group.average_job_time * 0.9 + dt * 0.1
				end

				if group.average_amount_of_workers.nil?
					group.average_amount_of_workers = w
				else
					group.average_amount_of_workers = group.average_amount_of_workers * 0.7 + w * 0.3
				end

				group.save

				Log.info "Job #{job} completed by #{worker}"

				EM.next_tick { update_group_status job.group }

				JSON.dump( :success => true, :result_url => result_url )
			end
		rescue Exception
			Log.error "In completion of job ##{params[:id]}" do
				Log.exception $!
			end

			halt 500, JSON.dump( :error => $!.to_s )
		end
	end

	post '/job/:id/forfeit' do
		content_type "application/json"

		worker = get_worker!

		job = Job.first :id => params[:id], :worker => worker

		if job.nil?
			halt 404, JSON.dump( :error => "job not found" )
		else
			job.update :worker => nil, :assigned_at => nil

			Log.warn "Job #{job} forfeited by #{worker}"

			EM.next_tick { update_group_status job.group }

			JSON.dump( :success => true )
		end
	end
end

Maru::Master.run! if __FILE__ == $0
