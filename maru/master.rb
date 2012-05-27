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
		property :details,     Json

		property :expiry,      Integer # in seconds

		property :assigned_id, String
		property :assigned_at, DateTime
	end

	DataMapper.finalize

	configure do
		DataMapper.setup( :default, ENV["DATABASE_URL"] || "sqlite://#{Dir.pwd}/maru.db" )
		DataMapper.auto_upgrade!
	end

	get '/' do
		"Status page coming soon..."
	end

	# The following should check the user agent to ensure it's a Maru worker and not a browser

	get '/job' do
		# Should assign a job to the client
	end

	post '/job/:id' do
		# Should accept the result of a job
	end

	post '/job/:id/forfeit' do
		# Should allow a worker to 'give up' on a job
	end
end

Maru::Master.run! if __FILE__ == $0
