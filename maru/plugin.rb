require_relative 'log'

module Maru
	module Plugin
		PLUGINS = []

		def self.included(mod)
			PLUGINS << mod
		end

		def self.[](name)
			PLUGINS.find { |pl| pl.machine_name == name }
		rescue Exception
			nil
		end

		def spawn(*cmd)
			Process.wait( fork { exec *cmd } )
			$?.success?
		end

		def log
			Maru::Log
		end

		def human_name
			name.gsub( /(?<=[a-z])([A-Z])/ ) { " #$1" }.gsub( '::', ' / ' )
		end

		def machine_name
			name.gsub( /(?<=[a-z])([A-Z])/ ) { "_#$1" }.gsub( '::', '/' ).downcase
		end
	end
end
