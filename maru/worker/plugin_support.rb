require_relative '../worker'

module Maru
	class Worker
		module PluginSupport
			class JobResultBuilder
				def initialize
					@files = []
				end

				def files *files
					files.each do |file|
						@files << {:name => file, :data => File.new( file ), :sha256 => OpenSSL::Digest::SHA256.file( file ).hexdigest}
					end
				end

				def cleanup
					@files.each do |file|
						File.unlink file[:name] rescue nil
					end
				end

				def to_params
					{:files => Hash[@files.map.with_index {|v,k| [k,v]}]}
				end
			end
		end
	end
end
