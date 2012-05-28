class String
	def to_class_name
		capitalize.gsub( /[_ ]([A-Za-z])/ ) { $1.upcase }
	end
end

module Maru
	module Plugins
		def self.[]( name )
			Maru::Plugins::const_get( name.to_class_name )
		end

		def self.include?( name )
			Maru::Plugins::const_defined?( name.to_class_name )
		end
	end
end
