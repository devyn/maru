class String
	def to_const(root=Object)
		split( / *\/ */ ).inject( root ) { |c,e| c.const_get( e.sub( /^([a-z])/ ) { $1.upcase }.gsub( /[ _]([A-Za-z])/ ) { $1.upcase }.gsub( ' ', '' ) ) }
	end
end

class Module
	def human_name
		name.gsub( /(?<=[a-z])([A-Z])/ ) { " #$1" }.gsub( '::', ' / ' )
	end

	def machine_name
		name.gsub( /(?<=[a-z])([A-Z])/ ) { "_#$1" }.gsub( '::', '/' ).downcase
	end
end

module Maru
	module Plugin
		PLUGINS = []

		def self.included(mod)
			PLUGINS << mod
		end

		def self.[](name)
			PLUGINS.include?(c = name.to_const) ? c : nil
		rescue Exception
			nil
		end

		def spawn(*cmd)
			Process.wait( fork { exec *cmd } )
			$?.success?
		end
	end
end
