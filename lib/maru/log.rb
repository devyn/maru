module Maru
	module Log
		extend self

		LOG_LEVELS = ["DEBUG", "INFO", "WARN", "ERROR", "CRITICAL"]

		attr_accessor :log_level

		def log level, *msgs, &blk
			@indent    ||= 0
			@log_level ||= $DEBUG ? "DEBUG" : "INFO"

			return if LOG_LEVELS.include?(level.upcase) and LOG_LEVELS.index(level.upcase) < LOG_LEVELS.index(@log_level.upcase)

			msgs.each do |msg|
				printf "%s [%s] %s%s\n", Time.now.utc.strftime("%Y-%m-%d %H:%M:%S"), level.upcase, "    "*@indent, msg
			end

			if blk
				@indent += 1
				begin
					blk.call
				ensure
					@indent -= 1
				end
			end
		end

		def debug *msgs, &blk
			log "DEBUG", *msgs, &blk
		end

		def info *msgs, &blk
			log "INFO", *msgs, &blk
		end

		alias write info

		def warn *msgs, &blk
			log "WARN", *msgs, &blk
		end

		def error *msgs, &blk
			log "ERROR", *msgs, &blk
		end

		def exception e, &blk
			error "#{e.class.name}: #{e}" do
				error *e.backtrace
			end
		end

		def critical *msgs, &blk
			log "CRITICAL", *msgs, &blk
		end

		def critical_exception e, &blk
			critical "#{e.class.name}: #{e}" do
				critical *e.backtrace
			end
		end
	end
end
