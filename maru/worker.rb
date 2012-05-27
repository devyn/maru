require 'json'
require 'rest_client'

class String
	def to_class_name
		capitalize.gsub( /[_ ]([A-Za-z])/ ) { $1.upcase }
	end
end

module Maru
	class Worker
		attr_accessor :masters

		DEFAULTS = {
			masters:  [],
			kinds:    nil,
			temp_dir: "/tmp/maru.#$$"
		}

		class NothingToDo < Exception; end

		module Plugins; end

		def initialize( config={} )
			config = DEFAULTS.dup.merge( config )

			@masters  = config[:masters].map { |u| RestClient::Resource.new( u ) }
			@kinds    = config[:kinds]
			@temp_dir = config[:temp_dir]
			@robin    = 0
		end

		def work
			raise NothingToDo if @masters.empty?

			passed = []
			until passed.include? @robin
				m = @masters[@robin]

				opt = {}
				opt[:kinds] = @kinds.join[","] if @kinds

				job = nil

				m['job'].get :params => opt do |response, request, result, &block|
					case response.code
					when 200
						job = JSON.parse( response )["job"]

						process_job job, m
						return
					when 503
						puts "\e[1m> \e[0;34m#{m} has no work for us\e[0m"
					else
						response.return! request, result, &block
					end

					passed << @robin
					if @robin >= @masters.length - 1
						@robin = 0
					else
						@robin += 1
					end
				end
			end

			raise NothingToDo
		end

		def process_job job, master
			handle = master["job"][job["id"]]
			plugin = Maru::Worker::Plugins::const_get( job["group"]["kind"].to_class_name )

			puts "\e[1m> ##{job["id"]} (#{job["group"]["name"]}) \e[33mprocessing\e[0m"

			if plugin.respond_to? :process_job
				begin
					files = Hash[plugin.process_job( job ).map { |f| [f, File.new( f )] }]
					puts "\e[1m> ##{job["id"]} (#{job["group"]["name"]}) \e[32mdone\e[0m"

					handle.post :assigned_id => job["assigned_id"], :files => files
				rescue Exception
					puts "\e[1m> ##{job["id"]} (#{job["group"]["name"]}) \e[31mforfeiting\e[0m"
					handle["forfeit"].post :assigned_id => job["assigned_id"]
					raise $!
				end
			end
		end
	end
end
