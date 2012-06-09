require 'eventmachine'
require 'json'
require 'data_mapper'
require 'fileutils'

require_relative 'plugins'
require_relative 'protocol'

module Maru
	class Master
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

			property :offered_at,   DateTime
			property :assigned_at,  DateTime
			property :completed_at, DateTime

			belongs_to :session, :required => false

			def to_color base=37
				"\e[1;35m##{self.id} \e[0;#{base}m(\e[1;36m#{self.group.name} \e[0;#{base}m/ \e[36m#{self.name}\e[#{base}m)\e[0m"
			end

			self.raise_on_save_failure = true
		end

		class Session
			include DataMapper::Resource

			has 1, :job

			property :id, String, :key => true, :default => proc { rand(36**12).to_s(36) }

			property :blacklist, Json, :default => []
			property :kinds,     Json, :default => []

			timestamps :created_at

			self.raise_on_save_failure = false
		end

		DataMapper.finalize

		class PathIsOutside < Exception; end

		attr_accessor :workers

		def initialize(host, port)
			DataMapper.setup :default, ENV['DATABASE_URL'] || "sqlite://#{Dir.pwd}/maru.db"
			DataMapper.auto_upgrade!

			@server  = EventMachine::start_server(host, port, Worker, self)
			@workers = []
		end

		def notify_group(group)
			puts "Offering #{group}"
			p @workers
			@workers.each do |w|
				if w.ready?
					w.offer_group group
				end
			end
		end

		module Worker
			include Maru::Protocol::Host

			attr_reader :session

			def ready?
				@ready
			end

			def initialize(master)
				super()
				@session   = nil
				@ready     = false
				@master    = master
			end

			def post_init
				@master.workers << self
			end

			def unbind
				@master.workers.delete self
			end

			def new_session(&ret)
				@session = Session.create
				ret.((@session ? :ok : :err), @session.id)
			end

			def load_session(id, &ret)
				@session = Session.get(id)
				ret.(@session ? :ok : :err)
			end

			def clear_session(&ret)
				if @session
					if @session.destroy
						@session = nil
						@ready   = false
						ret.(:ok)
					else
						ret.(:err)
					end
				else
					ret.(:err)
				end
			end

			def set_kinds(kinds, &ret)
				if @session and (@session.update(:kinds => kinds) rescue false)
					ret.(:ok)
				else
					ret.(:err)
				end
			end

			def ready(&ret)
				if @session and not @session.kinds.empty? and not @ready
					if job = Job.first(:offered_at => nil, :id.not => @session.blacklist, :group => {:kind => @session.kinds})
						offer job
					else
						@ready = true
					end
					ret.(:ok)
				else
					ret.(:err)
				end
			end

			def offer_group(group)
				if @session.kinds.include?(group.kind) and (job = Job.first(:offered_at => nil, :id.not => @session.blacklist, :group => group))
					offer job
				end
			end

			def offer(job)
				job.update      :offered_at => Time.now
				@session.update :job        => job

				super job.to_json(:relationships => {:group => {:exclude => [:output_dir]}})
			end

			def busy(&ret)
				if @session and @ready
					@ready = false
					if @session.job
						@session.job.update :offered_at => nil
						@session.update     :job        => nil
					end
					ret.(:ok)
				else
					ret.(:err)
				end
			end

			def accept(&ret)
				if @session and @session.job
					@session.job.update :assigned_at => Time.now
					@ready = false
					ret.(:ok)
				else
					ret.(:err)
				end
			end

			def file_output_path(path)
				if @session and @session.job
					File.join(@session.job.group.output_dir, path)
				else
					raise "nothing has been offered"
				end
			end

			def upload_files(files, &ret)
				if @session and @session.job and files
					start_files files.dup do
						j = {"successful" => [], "failed" => []}

						files.each do |file|
							if verify_file file
								j["successful"] << file["name"]
							else
								j["falied"] << file["name"]
							end
						end

						ret.(j["failed"].empty? ? :ok : :err, j)
					end
				else
					ret.(:err)
				end
			end

			def verify_file(file)
				if file["sha256"]
					Digest::SHA256.file(file_output_path(file)).hexdigest == file["sha256"]
				else
					true
				end
			end

			def complete(&ret)
				if @session and @session.job
					job = @session.job

					job.update      :completed_at => Time.now
					@session.update :job          => nil

					ret.(:ok)
				else
					ret.(:err)
				end
			end

			def forfeit(&ret)
				if @session and @session.job
					@session.blacklist << @session.job.id
					@session.save

					@session.job.update :offered_at => nil, :assigned_at => nil, :completed_at => nil

					ret.(:ok)
				else
					ret.(:err)
				end
			end

			def create_group(params, &ret)
				params.delete "id" # just in case

				if params["kind"] and Maru::Plugins.include?(params["kind"])
					group = Group.new(params)

					if group.valid? and Maru::Plugins[group.kind].validate_group(group)
						group.save

						Maru::Plugins[group.kind].create_jobs_for group

						FileUtils.mkdir_p group.output_dir

						@master.notify_group group

						ret.(:ok, group)
					else
						ret.(:err, group.errors.full_messages)
					end
				else
					ret.(:err, ["unsupported kind"])
				end
			end
		end
	end
end
