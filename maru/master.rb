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
		property :kind,          String, :required => true
		property :owner,         String
		property :prerequisites, Json,   :required => true, :default => []
		property :output_dir,    String, :required => true

		timestamps :created_at

		has n, :jobs

		self.raise_on_save_failure = true
	end

	class Job
		include DataMapper::Resource

		belongs_to :group

		property :id,           Serial
		property :details,      Json,     :default => {}

		property :expiry,       Integer,  :required => true, :default => 3600 # in seconds after assigned_at

		property :assigned_id,  String
		property :assigned_at,  DateTime

		property :completed_at, DateTime

		self.raise_on_save_failure = true
	end

	DataMapper.finalize

	class PathIsOutside < Exception; end

	configure do
		DataMapper.setup( :default, ENV["DATABASE_URL"] || "sqlite://#{Dir.pwd}/maru.db" )
		DataMapper.auto_upgrade!
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
		# Creates a group
		halt 401
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

			JSON.dump( :success => true )
		end
	end
end

Maru::Master.run! if __FILE__ == $0
