require 'json'
require 'yaml'
require 'uri'
require 'rest_client'
require 'fileutils'
require 'openssl'

require_relative 'plugin'
require_relative 'log'

module Maru
	class MasterLink
		class CanNotAuthenticate < Exception; end
		class NoJobsAvailable < Exception; end

		def initialize(url, worker_name, worker_key)
			@resource    = RestClient::Resource.new( url )
			@worker_name = worker_name
			@worker_key  = worker_key
		end

		def authenticate
			auth      = @resource[:"worker/authenticate"]
			challenge = auth.get
			response  = OpenSSL::HMAC.hexdigest(OpenSSL::Digest::SHA256.new, @worker_key, challenge)
			result    = auth.post( { :name => @worker_name, :response => response }, "Cookie" => cookie(challenge.cookies) )

			@resource.options[:headers]         ||= {}
			@resource.options[:headers]["Cookie"] = cookie(result.cookies)

			Log.info "Authenticated with #@resource"
			true
		rescue RestClient::Forbidden
			Log.info "#@resource refused our credentials"
			false
		end

		def request_job(params={})
			with_authentication do
				res = @resource[:job].get(:params => params)
				case res.code
				when 200
					JSON.parse(res)["job"]
				when 204
					raise NoJobsAvailable
				end
			end
		end

		def complete_job(id, result)
			with_authentication { @resource[:job][id].post result }
		end

		def forfeit_job(id)
			with_authentication { @resource[:job][id][:forfeit].post nil }
		end

		def to_s
			@resource.to_s
		end

		def id
			OpenSSL::Digest::SHA1.hexdigest( @resource.to_s )
		end

		def uri
			URI.parse(@resource.url)
		end

		private

		def with_authentication &blk
			blk.call
		rescue RestClient::Forbidden
			if authenticate
				blk.call
			else
				raise CanNotAuthenticate, @resource.to_s
			end
		end

		def cookie(h)
			# RestClient appears to handle escaped cookies weirdly,
			# so we correct that by setting the "Cookie" header ourselves.
			# The keys and values are already escaped, but when passing them
			# through to :cookies, they seem to become unescaped.
			h.map { |k,v| "#{k}=#{v}" }.join( ';' )
		end
	end

	class Worker
		attr_accessor :masters, :kinds, :temp_dir

		DEFAULTS = {
			name:         "A Worker",
			masters:      [{"url" => "http://maru.example.org/", "key" => "totally secret key"}],
			temp_dir:     "/tmp/maru.#$$",
			group_expiry: 7200
		}

		class NothingToDo  < Exception; end
		class Inconsistent < Exception; end

		def initialize( config={} )
			config = DEFAULTS.dup.merge( config )

			@name         = config[:name]
			@masters      = config[:masters].map { |m| Maru::MasterLink.new( m["url"], @name, m["key"] ) }
			@temp_dir     = config[:temp_dir]
			@group_expiry = config[:group_expiry]
			@blacklist    = {}
			@robin        = 0
		end

		def work
			raise NothingToDo if @masters.empty?

			passed = []
			got_work = false
			until passed.include? @robin or got_work
				m = @masters[@robin]

				opt = {}
				opt[:kinds]     = Maru::Plugin::PLUGINS.map( &:machine_name ).join( ',' )
				opt[:blacklist] = @blacklist[m].join( ',' ) if @blacklist[m]

				begin
					job = m.request_job(opt)
					got_work = true

					begin
						Log.info "#{format_job job, m} processing" do
							with_group job["group"], m do
								process_job job, m
							end
						end
						Log.info "#{format_job job, m} completed"
					rescue Exception
						Log.warn "#{format_job job, m} forfeiting: #$!"
						m.forfeit_job job["id"]

						Log.warn "Blacklisting #{m.uri.host}##{job["id"]}"
						@blacklist[m] ||= []
						@blacklist[m] << job["id"]

						raise $!
					end
				rescue Errno::ECONNREFUSED
					Log.warn "Can not connect to #{m}"
				rescue Maru::MasterLink::NoJobsAvailable
				rescue SystemExit
					raise $!
				rescue Exception
					Log.exception $!
				end

				passed << @robin
				if @robin >= @masters.length - 1
					@robin = 0
				else
					@robin += 1
				end
			end

			raise NothingToDo unless got_work
		end

		def cleanup
			if File.directory? @temp_dir
				Dir.entries( @temp_dir ).each do |d|
					if d =~ /^master-/
						Dir.entries( File.join( @temp_dir, d ) ).each do |d2|
							if d2 =~ /^group-/
								if Time.now - File.mtime( File.join( @temp_dir, d, d2 ) ) > @group_expiry
									FileUtils.rm_r File.join( @temp_dir, d, d2 )
								end
							end
						end
					end
				end
			end
		end

		private

		def process_job job, master
			plugin = Maru::Plugin[job["group"]["kind"]]

			if plugin.respond_to? :process_job
				job["prerequisites"].each do |pre|
					download_prerequisite pre
				end if job["prerequisites"]

				files = plugin.process_job( job ).map { |f| {"name" => f, "data" => File.new( f ), "sha256" => OpenSSL::Digest::SHA256.file( f ).hexdigest} }

				Log.info "Uploading results..."

				master.complete_job job["id"], :files => files

				files.each do |f|
					File.unlink(f["name"])
				end

				job["prerequisites"].each do |pre|
					File.unlink(pre["destination"]) if verify_path(pre["destination"]) and File.file? pre["destination"]
				end if job["prerequisites"]
			end
		end

		def format_job job, master
			"#{master.uri.host}##{job["id"]} (#{job["group"]["name"]} / #{job["name"]} - #{job["group"]["user"]["email"]})"
		end

		def with_group group, master
			FileUtils.mkdir_p( path = File.join( @temp_dir, "master-#{master.id}", "group-#{group["id"]}" ) )

			Dir.chdir path do
				group["prerequisites"].each do |pre|
					download_prerequisite pre
				end if group["prerequisites"]

				yield
			end
		end

		def download_prerequisite(pre)
			return unless verify_path( pre["destination"] )

			if File.file? pre["destination"]
				return if check_consistency pre["destination"], pre["sha256"]
			end

			Log.info "Downloading #{pre["destination"]} from #{pre["source"]}..."

			RestClient::Resource.new( pre["source"], :raw_response => true ).get do |response,request,result,&block|
				if response.code == 200
					File.open pre["destination"], 'w' do |f|
						IO::copy_stream response.file, f
					end

					if pre["sha256"] and check_consistency( pre["destination"], pre["sha256"] ) == false
						raise Inconsistent, "#{pre["destination"]} does not match the checksum."
					end
				else
					response.return! request, result, &block
				end
			end
		end

		def check_consistency path, sha256
			Log.info "Checking #{path} for consistency..."

			sha256 == OpenSSL::Digest::SHA256.file( path ).hexdigest
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

			trap( :INT  ) { exit }
			trap( :TERM ) { exit }

			at_exit do
				Log.info "Waiting for child processes..."
				Process.waitall
				Log.info "Cleaning up..."
				unless options[:keep_temp]
					FileUtils.rm_rf w.temp_dir
				end
			end

			loop do
				begin
					w.cleanup
					w.work
				rescue Maru::Worker::NothingToDo
					sleep options[:wait_time] || 30
				rescue SystemExit
					raise $!
				rescue Exception
					Log.exception $!
				end
			end
		end
	end
end
