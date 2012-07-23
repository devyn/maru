require 'fileutils'
require 'etc'

require_relative 'log'

module Process
	def running? pid
		Process.getpgid(pid) != -1
	rescue Errno::EPERM
		true
	rescue Errno::ESRCH
		false
	end
	module_function :running?
end

module Maru
	class Operator
		DEFAULTS = {
			"workers" => [],
			"plugins" => [],
			"env"     => {}
		}

		def initialize(config)
			@config = DEFAULTS.merge(config)

			Log.log_level = @config["log_level"] if @config["log_level"]

			@config["plugins"].each { |pl| require pl }

			@config["env"].each do |k,v|
				ENV[k] = v.gsub("$#{k}", ENV[k].to_s)
			end
		end

		def start_services(*names)
			names = (@config["master"] ? ["master"] : []) + @config["workers"].map { |w| w["name"] } if names.empty?

			names.inject(true) do |success, name|
				if name =~ /^master$/i
					success && start_master
				else
					success && start_worker(name)
				end
			end
		end

		def stop_services(*names)
			names = (@config["master"] ? ["master"] : []) + @config["workers"].map { |w| w["name"] } if names.empty?

			names.inject(true) do |success, name|
				stop_service(name) && success
			end
		end

		def restart_services(*names)
			stop_services(*names) && start_services(*names)
		end

		def start_master
			config = @config["master"]

			if config.nil?
				puts ">> Config for master does not exist."
				return false
			end

			if service_pid("master")
				puts ">> master is already running"
				return true
			end

			detach do
				$0 = "maru master"

				output_to_log "master"

				switch_user_and_group(config["user"]  || @config["user"],
					                    config["group"] || @config["group"]) { |uid, gid|
					write_pid_file "master", uid
				}

				require 'rack/builder'
				require 'thin'

				app = Rack::Builder.new

				rackup = config["rackup"] || "config.ru"

				begin
					app.instance_eval File.read(rackup), rackup
				rescue Errno::ENOENT
					Log.critical "Rackup file (#{rackup}) does not exist. Can not start."
					exit 1
				rescue Exception
					Log.critical "Can not start:" do
						Log.critical_exception $!
					end
				end

				if config["socket"]
					Thin::Server.start(config["socket"], app)
				elsif config["host"] and config["port"]
					Thin::Server.start(config["host"], config["port"], app)
				else
					Log.critical "No socket, host or port specified. Can not start."
					exit 1
				end
			end

			true
		end

		def start_worker(name)
			config = @config["workers"].find { |w| w["name"].downcase == name.downcase }

			if config.nil?
				puts "!! Config for #{name} does not exist"
				return false
			end

			name = config["name"]

			if service_pid(name)
				puts ">> #{name} is already running"
				return true
			end

			detach do
				$0 = "maru worker #{name}"

				output_to_log name

				switch_user_and_group(config["user"]  || @config["user"],
					                    config["group"] || @config["group"]) { |uid, gid|
					write_pid_file name, uid
				}

				require_relative 'worker'

				Maru::Worker.new(config).run
			end
		end

		def stream_logs(*names)
			require 'eventmachine'
			require 'eventmachine-tail'

			if names.delete("--all")
				startpos = 0
			else
				startpos = -1
			end

			names = (@config["master"] ? ["master"] : []) + @config["workers"].map { |w| w["name"] } if names.empty?

			len = names.sort { |n1,n2| n2.length <=> n1.length }.first
			len = len ? len.length : 0

			EM.run do
				names.each do |name|
					establish = proc do
						begin
							EM.file_tail(File.join(log_dir, name + ".log"), nil, startpos) do |tail, line|
								printf "\e[%sm%-#{len+2}s\e[0m%s\n", (name == "master" ? "35" : "36"), name, line
							end
						rescue Errno::ENOENT
							EM.add_timer 1, &establish
						end
					end
					establish.call
				end
			end
		rescue Interrupt
			true
		end

		def log_dir
			d = @config["log_dir"] || "log"
			FileUtils.mkdir_p(d)
			File.expand_path(d)
		end

		def pid_dir
			d = @config["pid_dir"] || "pid"
			FileUtils.mkdir_p(d)
			File.expand_path(d)
		end

		private

		def output_to_log(name)
			f = File.open(File.join(log_dir, name + ".log"), 'a')
			f.sync = true
			$stdout.reopen(f)
			$stderr.reopen(f)
			$stdin.close
		end

		def write_pid_file(name, uid=nil)
			File.open(path = File.join(pid_dir, name + ".pid"), 'w') do |f|
				f.puts $$
				f.chmod 0644
				f.chown uid, nil if uid
			end

			at_exit do
				File.unlink(path) rescue nil
			end
		end

		def switch_user_and_group(user=nil, group=nil)
			gid = group =~ /^\d+$/ ? group.to_i : Etc.getgrnam(group).gid if group
			uid = user  =~ /^\d+$/ ? user.to_i  : Etc.getpwnam(user).uid  if user

			yield uid, gid if block_given?

			if user
				Process.initgroups(user, group)
				Process::GID.change_privilege(gid) if gid
				Process::UID.change_privilege(uid)
			end
		end

		def detach
			fork do
				Process.setsid
				fork { yield }
			end
		end

		def delete_pid_file_if_stale(path)
			if File.file? path
				pid = File.read(path).to_i
				if not Process.running? pid
					puts ">> Deleting stale pid file #{path}"
					File.unlink(path)
				end
			end
		end

		def service_pid(name)
			path = File.join(pid_dir, name + ".pid")
			delete_pid_file_if_stale(path)
			File.file?(path) ? File.read(path).to_i : nil
		end

		def stop_service(name)
			if pid = service_pid(name)
				quit_process pid
			else
				puts ">> #{name} is not running"
				true
			end
		end

		def quit_process(pid)
			puts ">> Sending INT signal to process #{pid}... (^C to force)"

			Process.kill :INT, pid

			sleep 0.1 while Process.running? pid
			true
		rescue Interrupt
			puts ">> Sending KILL signal to process #{pid}..."

			Process.kill :KILL, pid

			sleep 0.1 while Process.running? pid
			true
		rescue Errno::ESRCH
			puts "!! No such process"
			false
		rescue Errno::EPERM
			puts "!! Process is not ours to kill"
			false
		end
	end
end
