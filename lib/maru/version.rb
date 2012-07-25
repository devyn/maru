module Maru
	VERSION = [0,1]

	class << VERSION
		def to_s
			self[0].to_s + self[1..-1].map { |x| x.is_a?(Numeric) ? ".#{x}" : "-#{x}" }.join
		end
	end
end
