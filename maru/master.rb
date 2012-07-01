require 'sinatra/base'
require 'json'
require 'data_mapper'
require 'fileutils'

require_relative 'plugins'

class Maru::Master < Sinatra::Base
	class Group
		include DataMapper::Resource

		property :id,            Serial
		property :name,          String, :required => true
		property :details,       Json,   :default  => {}

		property :kind,          String, :required => true
		property :owner,         String

		property :prerequisites, Json,   :required => true, :default => []
		property :output_dir,    String, :required => true

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

		property :id,           Serial
		property :name,         String,   :required => true
		property :details,      Json,     :default  => {}

		property :expiry,       Integer,  :required => true, :default => 3600 # in seconds after assigned_at

		property :assigned_id,  String
		property :assigned_at,  DateTime

		property :completed_at, DateTime

		def to_color base=37
			"\e[1;35m##{self.id} \e[0;#{base}m(\e[1;36m#{self.group.name} \e[0;#{base}m/ \e[36m#{self.name}\e[#{base}m)\e[0m"
		end

		self.raise_on_save_failure = true
	end

	DataMapper.finalize

	class PathIsOutside < Exception; end

	configure do
		DataMapper.setup( :default, ENV["DATABASE_URL"] || "sqlite://#{Dir.pwd}/maru.db" )
		DataMapper.auto_upgrade!

		@@expiry_check = Thread.start do
			loop do
				Job.all( :assigned_id.not => nil, :assigned_at.not => nil ).each do |job|
					if Time.now - job.assigned_at > job.expiry
						job.update :assigned_id => nil, :assigned_at => nil
					end
				end
				sleep 60
			end
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
	end

	get '/' do
		# Status page
		halt 501
	end

	get '/group/new/:kind' do
		# Form for creating groups
		halt 501
	end

	put '/group' do
		content_type 'text/json'

		if params[:kind].nil? or !Maru::Plugins.include?( params[:kind] )
			halt 501, {:errors => ["Unsupported group kind"]}.to_json
			next
		end

		group = Group.new( params )
		group.id = nil

		if group.valid? and Maru::Plugins[group.kind].validate_group( group )
			group.save

			Maru::Plugins[group.kind].create_jobs_for group

			warn "\e[1m> \e[0mGroup #{group.to_color}\e[0m created with \e[32m#{group.jobs.length}\e[0m jobs"

			{:group => group}.to_json
		else
			halt 400, {:errors => group.errors.full_messages}.to_json
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

	delete '/group/:id' do
		# Deletes a group
		halt 501
	end

	# The following should check the user agent to ensure it's a Maru worker and not a browser

	get '/job' do
		content_type "application/json"

		jobs = Job.all :completed_at => nil, :assigned_id => nil

		unless params[:kinds].to_s.empty?
			jobs = jobs.all :group => { :kind => params[:kinds].split( ',' ) }
		end

		unless params[:blacklist].to_s.empty?
			jobs = jobs.all :id.not => params[:blacklist].split( ',' ).map( &:to_i )
		end

		job = jobs.first

		if job.nil?
			halt 503, JSON.dump( :error => "no jobs available" )
		else
			job.update :assigned_id => generate_id, :assigned_at => Time.now

			warn "\e[1m> \e[0mJob #{job.to_color} \e[1;33massigned id \e[0;33m#{job.assigned_id}\e[0m"

			%{{"job":#{job.to_json( :relationships => { :group => { :exclude => [:output_dir] } } )}}}
		end
	end

	post '/job/:id' do
		content_type "application/json"

		job = Job.first :id => params[:id], :assigned_id => params[:assigned_id]

		if job.nil?
			halt 404, JSON.dump( :error => "job not found" )
		else
			params[:files].each do |filename,fileinfo|
				begin
					path = join_relative job.group.output_dir, filename
					FileUtils.mkdir_p File.dirname( path )
					IO.copy_stream fileinfo[:tempfile], path
				rescue PathIsOutside
					halt 400, JSON.dump( :error => "path leads outside of output directory" )
				rescue Exception
					halt 500, JSON.dump( :error => $!.to_s )
				ensure
					fileinfo[:tempfile].close
				end
			end unless params[:files].nil?

			job.update :completed_at => Time.now, :assigned_id => nil

			warn "\e[1m> \e[0mJob #{job.to_color} \e[1;32mcompleted\e[0m"

			JSON.dump( :success => true )
		end
	end

	post '/job/:id/forfeit' do
		content_type "application/json"

		job = Job.first :id => params[:id], :assigned_id => params[:assigned_id]

		if job.nil?
			halt 404, JSON.dump( :error => "job not found" )
		else
			job.update :assigned_id => nil, :assigned_at => nil

			warn "\e[1m> \e[0mJob #{job.to_color} \e[1;31mforfeited\e[0m"

			JSON.dump( :success => true )
		end
	end
end

Maru::Master.run! if __FILE__ == $0
