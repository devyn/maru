module Maru
	class MultiAccessHash < Hash
		def initialize(base_hash)
			super()

			update base_hash if base_hash

			process = proc do |o|
				case o
				when Hash
					self.class.new(o)
				when Array
					o.map &process
				else
					o
				end
			end

			each do |k,v|
				self[k] = process[v]
			end
		end

		def [](k)
			if include? k
				super k
			elsif include? k.to_s
				super k.to_s
			elsif include? k.to_s.to_sym
				super k.to_s.to_sym
			else
				nil
			end
		end

		def []=(k,v)
			if include? k
				super k, v
			elsif include? k.to_s
				super k.to_s, v
			elsif include? k.to_s.to_sym
				super k.to_s.to_sym, v
			else
				nil
			end
		end

		def method_missing name, *args, &block
			if name.to_s =~ /=$/
				self[name] = args[0]
			else
				self[name]
			end
		end
	end
end
