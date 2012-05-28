require 'json'
require 'yaml'
require 'rest_client'
require 'fileutils'
require 'digest'

class String
	def to_class_name
		capitalize.gsub( /[_ ]([A-Za-z])/ ) { $1.upcase }
	end
end

module Maru
	module Plugins; end

	class Worker
		attr_accessor :masters, :kinds, :temp_dir

		DEFAULTS = {
			masters:      [],
			kinds:        nil,
			temp_dir:     "/tmp/maru.#$$",
			group_expiry: 7200
		}

		class NothingToDo  < Exception; end
		class Inconsistent < Exception; end

		def initialize( config={} )
			config = DEFAULTS.dup.merge( config )

			@masters      = config[:masters].map { |u| RestClient::Resource.new( u ) }
			@kinds        = config[:kinds]
			@temp_dir     = config[:temp_dir]
			@group_expiry = config[:group_expiry]
			@blacklist    = {}
			@robin        = 0
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

				begin
					m['job'].get :params => opt do |response, request, result, &block|
						case response.code
						when 200
							begin
								job = JSON.parse( response )["job"]

								puts "\e[1m> ##{job["id"]} (#{job["group"]["name"]}) \e[33mprocessing\e[0m"

								with_group job["group"] do
									process_job job, m
								end
								return
							rescue Exception
								puts "\e[1m> ##{job["id"]} (#{job["group"]["name"]}) \e[31mforfeiting:\e[0m #$!"
								m['job'][job['id']]["forfeit"].post :assigned_id => job["assigned_id"] rescue nil

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
					end
				rescue Errno::ECONNREFUSED
					warn "\e[1m> \e[0;33mWarning: #{m} may be down.\e[0m"
				rescue Exception
				end

				passed << @robin
				if @robin >= @masters.length - 1
					@robin = 0
				else
					@robin += 1
				end
			end

			raise NothingToDo
		end

		def cleanup
			if File.directory? @temp_dir
				Dir.entries( @temp_dir ).each do |d|
					case d
					when '.', '..'
					when /^group-/
						if Time.now - File.mtime( File.join( @temp_dir, d ) ) > @group_expiry
							FileUtils.rm_r File.join( @temp_dir, d )
						end
					end
				end
			end
		end

		private

		def process_job job, master
			handle = master["job"][job["id"]]
			plugin = Maru::Plugins::const_get( job["group"]["kind"].to_class_name )

			if plugin.respond_to? :process_job
				files = Hash[plugin.process_job( job ).map { |f| [f, File.new( f )] }]

				puts "\e[1m  > \e[0;34mUploading results...\e[0m"

				handle.post :assigned_id => job["assigned_id"], :files => files

				files.each do |f|
					File.unlink f[0]
				end

				puts "\e[1m> ##{job["id"]} (#{job["group"]["name"]}) \e[32mdone\e[0m"
			end
		end

		def with_group group
			FileUtils.mkdir_p( path = File.join( @temp_dir, "group-#{group["id"]}" ) )

			Dir.chdir path do
				group["prerequisites"].each do |pre|
					next unless verify_path( pre["destination"] )

					if File.file? pre["destination"]
						next if check_consistency pre["destination"], pre["sha256"]
					end

					puts "\e[1m  > \e[0;34mDownloading #{pre["destination"]} from #{pre["source"]}...\e[0m"

					RestClient::Resource.new( pre["source"], :raw_response => true ).get do |response,request,result,&block|
						if response.code == 200
							File.open pre["destination"], 'w' do |f|
								IO::copy_stream response.file, f
							end

							if check_consistency( pre["destination"], pre["sha256"] ) == false
								raise Inconsistent, "#{pre["destination"]} does not match the checksum."
							end
						else
							response.return! request, result, &block
						end
					end
				end

				yield
			end
		end

		def check_consistency path, sha256
			puts "\e[1m  > \e[0;34mChecking #{path} for consistency...\e[0m"

			sha256 == Digest::SHA256.file( path ).hexdigest
		end

		def verify_path path
			File.expand_path( path )[0, Dir.pwd.size] == Dir.pwd
		end

		public

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

				opts.on "--[no-]keep-temp", "Keep temp dir on exit. Default: false" do |v|
					options[:keep_temp] = v
				end

				opts.on "-w", "--wait-time N", "Amount of time (in seconds) to wait if there are no jobs available. Default: 30" do |num|
					options[:wait_time] = num.to_i
				end

				opts.on "-e", "--group-expiry N", "Amount of time (in seconds) to keep group files. Default: 7200" do |num|
					options[:group_expiry] = num.to_i
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

			at_exit do
				unless options[:keep_temp]
					FileUtils.rm_rf w.temp_dir
				end
			end

			loop do
				begin
					w.cleanup
					w.work
				rescue Maru::Worker::NothingToDo
					puts "\e[1m> \e[0;34mNothing to do. Waiting #{options[:wait_time] || 30} seconds.\e[0m"
					sleep options[:wait_time] || 30
				rescue SystemExit
					raise $!
				rescue Exception
					#warn "\e[1m! \e[31m#{$!.class.name}: \e[0m#{$!.message}"
				end
			end
		end
	end
end
