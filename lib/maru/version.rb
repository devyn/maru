module Maru
  # The current version of Maru.
	VERSION = [1,0,"devel"]

	class << VERSION
		def to_s
			self[0].to_s + self[1..-1].map { |x| x.is_a?(Numeric) ? ".#{x}" : "-#{x}" }.join
		end
	end
end
