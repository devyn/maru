require 'sinatra/base'
require 'json'
require 'data_mapper'

module Maru; end

class Maru::Master < Sinatra::Base
	class Group
		include DataMapper::Resource

		property :id,            Serial
		property :name,          String
		property :kind,          String
		property :owner,         String
		property :prerequisites, Json
		property :output_dir,    String

		timestamps :created_at

		has n, :jobs
	end

	class Job
		include DataMapper::Resource

		belongs_to :group

		property :id,          Serial
		property :complete,    Boolean
		property :details,     Json

		property :expiry,      Integer # in seconds after assigned_at

		property :assigned_id, String
		property :assigned_at, DateTime
	end

	DataMapper.finalize

	configure do
		DataMapper.setup( :default, ENV["DATABASE_URL"] || "sqlite://#{Dir.pwd}/maru.db" )
		DataMapper.auto_upgrade!
	end

	helpers do
		def generate_id
			rand( 36 ** 12 ).to_s( 36 )
		end
	end

	get '/' do
		# Status page
		halt 401
	end

	# The following should check the user agent to ensure it's a Maru worker and not a browser

	get '/job' do
		content_type "application/json"

		jobs = Job.all :complete.not => true, :assigned_id => nil

		unless params[:kinds].to_s.empty?
			jobs = jobs.all :group => { :kind => params[:kinds].split( ',' ) }
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
		# Should accept the result of a job
		halt 401, JSON.dump( :error => "not implemented" )
	end

	post '/job/:id/forfeit' do
		content_type "application/json"

		job = Job.first( :id => params[:id], :assigned_id => params[:assigned_id] )

		if job.nil?
			halt 404, JSON.dump( :error => "job not found" )
		else
			job.update :assigned_id => nil, :assigned_at => nil

			JSON.dump( :success => true )
		end
	end
end

Maru::Master.run! if __FILE__ == $0
