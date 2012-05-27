require 'json'
require 'yaml'
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

			@masters   = config[:masters].map { |u| RestClient::Resource.new( u ) }
			@kinds     = config[:kinds]
			@temp_dir  = config[:temp_dir]
			@blacklist = {}
			@robin     = 0
		end

		def work
			raise NothingToDo if @masters.empty?

			passed = []
			until passed.include? @robin
				m = @masters[@robin]

				opt = {}
				opt[:kinds]     = @kinds.join( "," )             if @kinds
				opt[:blacklist] = @blacklist[m.to_s].join( ',' ) if @blacklist[m.to_s]

				job = nil

				m['job'].get :params => opt do |response, request, result, &block|
					case response.code
					when 200
						begin
							job = JSON.parse( response )["job"]

							puts "\e[1m> ##{job["id"]} (#{job["group"]["name"]}) \e[33mprocessing\e[0m"

							process_job job, m
							return
						rescue Exception
							puts "\e[1m> ##{job["id"]} (#{job["group"]["name"]}) \e[31mforfeiting:\e[0m #$!"
							m['job'][job['id']]["forfeit"].post :assigned_id => job["assigned_id"]

							puts "\e[1m> \e[0;34mBlacklisting ##{job["id"]}.\e[0m"
							@blacklist[m.to_s] ||= []
							@blacklist[m.to_s] << job["id"]

							raise $!
						end
					when 503
						#puts "\e[1m> \e[0;34m#{m} has no work for us\e[0m"
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

			if plugin.respond_to? :process_job
				files = Hash[plugin.process_job( job ).map { |f| [f, File.new( f )] }]
				puts "\e[1m> ##{job["id"]} (#{job["group"]["name"]}) \e[32mdone\e[0m"

				handle.post :assigned_id => job["assigned_id"], :files => files
			end
		end


		def self.run
			require 'optparse'

			options = {}
			OptionParser.new do |opts|
				opts.banner = "Usage: #{File.basename( $0 )} [options]"

				opts.on "-m", "--master URL", "Add master" do |url|
					options[:masters] ||= []
					options[:masters] << url
				end

				opts.on "-k", "--kinds x,y,z", "Specify list of acceptable job types" do |kinds|
					options[:kinds] = kinds.split( ',' )
				end

				opts.on "-t", "--temp-dir DIR", "Specify directory to use for temporary files. Default: /tmp/maru.<PID>" do |temp_dir|
					options[:temp_dir] = temp_dir
				end

				opts.on "-r", "--require FILE", "Load a ruby script (most likely a plugin) before starting" do |f|
					require f
				end

				opts.on "-c", "--config-file FILE", "Loads a configuration file in YAML format. See README." do |f|
					YAML.load_file( f ).each do |k,v|
						options[k.to_s.to_sym] = v
					end

					if options[:plugins]
						options[:plugins].each { |f| require f }
					end
				end

				opts.on_tail "-h", "--help", "Show this message" do
					puts opts
					exit
				end
			end.parse! ARGV

			w = Maru::Worker.new options

			trap :INT do
				exit
			end

			loop do
				begin
					w.work
				rescue Maru::Worker::NothingToDo
					puts "\e[1m> \e[0;34mNothing to do. Waiting 30 seconds.\e[0m"
					sleep 30
				rescue SystemExit
					raise $!
				rescue Exception
					#warn "\e[1m! \e[31m#{$!.class.name}: \e[0m#{$!.message}"
				end
			end
		end
	end
end
