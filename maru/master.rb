require 'sinatra/base'
require 'json'
require 'data_mapper'
require 'fileutils'
require 'openssl'
require 'erubis'
require 'rdiscount'

require_relative 'plugin'

class Maru::Master < Sinatra::Base
	class Group
		include DataMapper::Resource

		belongs_to :user

		property :id,            Serial
		property :name,          String,  :required => true, :length  => 255
		property :details,       Json,    :default  => {}

		property :kind,          String,  :required => true, :length  => 255

		property :public,        Boolean, :required => true, :default => true

		property :prerequisites, Json,    :required => true, :default => []
		property :output_dir,    String,  :required => true, :length  => 255

		timestamps :created_at

		has n, :jobs

		def to_color base=37
			"\e[1;31m##{self.id} \e[0;#{base}m(\e[1;36m#{self.name}\e[0;#{base}m)\e[0m"
		end

		self.raise_on_save_failure = true
	end

	class Job
		include DataMapper::Resource

		belongs_to :group
		belongs_to :worker, :required => false

		property :id,           Serial
		property :name,         String,   :required => true, :length => 255
		property :details,      Json,     :default  => {}

		property :expiry,       Integer,  :required => true, :default => 3600 # in seconds after assigned_at

		property :assigned_at,  DateTime
		property :completed_at, DateTime

		def to_color base=37
			"\e[1;35m##{self.id} \e[0;#{base}m(\e[1;36m#{self.group.name} \e[0;#{base}m/ \e[36m#{self.name}\e[#{base}m)\e[0m"
		end

		self.raise_on_save_failure = true
	end

	class Worker
		include DataMapper::Resource

		belongs_to :user

		has n, :jobs

		property :id,             Serial
		property :name,           String, :required => true, :length => 128, :unique  => true # The name of the worker.
		property :authenticator,  String, :required => true, :length => 24,  :default => ->{ rand(36**24).to_s(36) }
		                                  # The key, but we can't call it that.

		def to_color base=37
			"\e[33m#{self.name}\e[0m"
		end
	end

	class User
		include DataMapper::Resource

		has n, :workers
		has n, :groups

		property :id,            Serial
		property :email,         String, :required => true, :length => 255, :unique => true
		property :password_hash, String, :required => true, :length => 64
		property :password_salt, String, :required => true, :length => 4

		# Permissions
		property :can_own_workers,      Boolean, :required => true, :default => false
		property :can_own_groups,       Boolean, :required => true, :default => false
		property :can_manage_users,     Boolean, :required => true, :default => false
		property :can_modify_any_group, Boolean, :required => true, :default => false

		def password=(pass)
			self.password_salt = rand( 36 ** 4 ).to_s( 36 )
			self.password_hash = OpenSSL::HMAC.hexdigest( OpenSSL::Digest::SHA256.new, self.password_salt, pass )
		end

		def password_is?(pass)
			OpenSSL::HMAC.hexdigest( OpenSSL::Digest::SHA256.new, self.password_salt, pass ) == self.password_hash
		end

		def to_color base=37
			"\e[32m#{email}\e[0m"
		end
	end

	DataMapper.finalize

	class PathIsOutside < Exception; end

	enable :sessions
	enable :static

	set    :root,          File.join( File.dirname( __FILE__ ), '..' )

	set    :views,         -> { File.join( root, 'views'  ) }
	set    :public_folder, -> { File.join( root, 'static' ) }

	set    :erubis,        :escape_html => true

	configure do
		DataMapper.setup( :default, ENV["DATABASE_URL"] || "sqlite://#{Dir.pwd}/maru.db" )
		DataMapper.auto_upgrade!

		@@expiry_check = Thread.start do
			loop do
				begin
					Job.all( :worker.not => nil, :completed_at => nil ).each do |job|
						if Time.now - job.assigned_at.to_time > job.expiry
							Kernel.warn "\e[1m>\e[0m Reaping #{job.to_color} (expired)"
							job.update :worker => nil
						end
					end
					sleep 60
				rescue Exception
				end
			end
		end
	end

	before do
		if session[:user]
			@user = User.get( session[:user] )
		end
	end

	helpers do
		def generate_id
			rand( 36 ** 12 ).to_s( 36 )
		end

		def join_relative( base, path )
			base = File.expand_path( base )
			o    = File.expand_path( File.join( base, path ) )

			raise PathIsOutside if o[0,base.size] != base
			return o
		end

		def get_worker
			Worker.first :id => session[:worker], :authenticator => session[:authenticator]
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

			redirect to('/') unless @user.can_own_groups
		end
	end

	get '/' do
		if logged_in?
			if @user.can_modify_any_group
				@groups = Group.all
			else
				@groups = user.groups + Group.all(:public => true)
			end
		else
			@groups = Group.all(:public => true)
		end

		erb :index
	end

	get '/user/login' do
		redirect to('/') if logged_in?
		erb :user_login
	end

	post '/user/login' do
		if user = User.first( :email => params[:email] )
			if user.password_is? params[:password]
				session[:user] = user.id
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

	get '/users' do
		# Manage users
		halt 501
	end

	get '/group/new' do
		must_be_able_to_own_groups!

		erb :group_new
	end

	post '/group/new' do
		must_be_able_to_own_groups!

		if params[:kind].nil? or !(plugin = Maru::Plugins[params[:kind]])
			@error = "- unsupported group kind"
			halt 501, erb(:group_new)
		end

		group      = Group.new( params )
		group.id   = nil
		group.kind = plugin.machine_name

		plugin_errors = plugin.validate_group( group ).to_a

		if group.valid? and plugin_errors.empty?
			group.save

			plugin.create_jobs_for group

			warn "\e[1m> \e[0mGroup #{group.to_color}\e[0m created with \e[32m#{group.jobs.length}\e[0m jobs"

			redirect to('/')
		else
			@error = (group.errors.full_messages + plugin_errors).map {|s| "- #{s}"}.join("\n")

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

	get '/group/:id/delete' do
		# Deletes a group
		halt 501
	end

	# The following should check the user agent to ensure it's a Maru worker and not a browser

	get '/worker/authenticate' do
		content_type "text/plain"

		session[:challenge] = rand(36**20).to_s(36)
	end

	post '/worker/authenticate' do
		content_type "text/plain"

		if session[:challenge]
			target = Worker.first :name => params[:name]

			if target and params[:response] == OpenSSL::HMAC.hexdigest(OpenSSL::Digest::SHA256.new, target.authenticator, session[:challenge])
				session[:worker]        = target.id
				session[:authenticator] = target.authenticator
				session[:challenge]     = nil
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

		jobs = Job.all :worker => nil, :group => { :kind => params[:kinds].split( ',' ) }

		unless params[:blacklist].to_s.empty?
			jobs = jobs.all :id.not => params[:blacklist].split( ',' ).map( &:to_i )
		end

		job = jobs.first

		if job.nil?
			halt 204, JSON.dump( :error => "no jobs available" )
		else
			job.update :worker => worker, :assigned_at => Time.now

			warn "\e[1m> \e[0mJob #{job.to_color} \e[1;33massigned to \e[0m#{worker.to_color}"

			%{{"job":#{job.to_json( :relationships => { :group => { :exclude => [:output_dir] } } )}}}
		end
	end

	post '/job/:id' do
		content_type "application/json"

		worker = get_worker!

		job = Job.first :id => params[:id], :worker => worker

		if job.nil?
			halt 404, JSON.dump( :error => "job not found" )
		else
			params[:files].each do |file|
				begin
					path = join_relative job.group.output_dir, file["name"]
					FileUtils.mkdir_p File.dirname( path )
					IO.copy_stream file["data"][:tempfile], path
				rescue PathIsOutside
					halt 400, JSON.dump( :error => "path leads outside of output directory" )
				rescue Exception
					halt 500, JSON.dump( :error => $!.to_s )
				ensure
					file["data"][:tempfile].close
				end
			end unless params[:files].nil?

			job.update :completed_at => Time.now

			warn "\e[1m> \e[0mJob #{job.to_color} \e[1;32mcompleted by \e[0m#{worker.to_color}"

			JSON.dump( :success => true )
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

			warn "\e[1m> \e[0mJob #{job.to_color} \e[1;31mforfeited by \e[0m#{worker.to_color}"

			JSON.dump( :success => true )
		end
	end
end

Maru::Master.run! if __FILE__ == $0
