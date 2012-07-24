require 'uri'

module Maru
	class BasicFilestore
		attr_accessor :base_path, :base_url

		def initialize(base_path, base_url)
			@base_path, @base_url = base_path, base_url
		end

		def store_prerequisite(input, name, group)
			base        = File.join(@base_path, group.id.to_s, "prerequisites")
			target_path = File.join(base, name)

			if verify_path(base, target_path)
				FileUtils.mkdir_p(File.dirname(target_path))
				IO::copy_stream input, target_path

				File.chmod(0666 & ~File.umask, target_path) # see issue #15 

				url    = @base_url.chomp('/') + "/#{group.id}/prerequisites/#{URI.escape(name)}"
				sha256 = OpenSSL::Digest::SHA256.file(target_path).hexdigest

				return [url, sha256]
			else
				raise SecurityViolation, "The name of the prerequisite to be stored led into a restricted area."
			end
		end

		def delete_prerequisite(name, group)
			base        = File.join(@base_path, group.id.to_s, "prerequisites")
			target_path = File.join(base, name)

			if verify_path(base, target_path)
				File.unlink(target_path) if File.file? target_path
			else
				raise SecurityViolation, "The name of the prerequisite to be stored led into a restricted area."
			end
		end

		def store_result(input, name, group)
			base        = File.join(@base_path, group.id.to_s, "results")
			target_path = File.join(base, name)

			if verify_path(base, target_path)
				FileUtils.mkdir_p(File.dirname(target_path))
				IO::copy_stream input, target_path

				File.chmod(0666 & ~File.umask, target_path) # see issue #15

				url    = @base_url.chomp('/') + "/#{group.id}/results/#{URI.escape(name)}"
				sha256 = OpenSSL::Digest::SHA256.file(target_path).hexdigest

				return [url, sha256]
			else
				raise SecurityViolation, "The name of the result to be stored led into a restricted area."
			end
		end

		def delete_result(name, group)
			base        = File.join(@base_path, group.id.to_s, "results")
			target_path = File.join(base, name)

			if verify_path(base, target_path)
				File.unlink(target_path) if File.file? target_path
			else
				raise SecurityViolation, "The name of the result to be stored led into a restricted area."
			end
		end

		def results_path(group)
			return @base_url.chomp('/') + "/#{group.id}/results/"
		end

		def clean(group)
			path = File.join(@base_path, group.id.to_s)

			if File.directory? path
				FileUtils.rm_r path
			end
		end

		class SecurityViolation < Exception; end

		private

		def verify_path(base, path)
			base, path = File.expand_path(base), File.expand_path(path)

			path[0, base.size] == base
		end
	end
end
