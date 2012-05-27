require 'json'
require 'net/http'

module Maru
	class Worker
		attr_accessor :masters

		DEFAULTS = {
			masters:  [],
			temp_dir: "/tmp/maru.#$$"
		}

		def initialize( config={} )
			config = DEFAULTS.dup.merge( config )

			@masters  = config[:masters]
			@temp_dir = config[:temp_dir]
		end

		def do_job
		end
	end
end
