require_relative '../../master'

module Maru
	class Master < Sinatra::Base
		class Worker
			include DataMapper::Resource

			belongs_to :user, :required => false

			has n, :jobs

			property :id,             Serial
			property :name,           String, :required => true, :length => 128, :unique  => true # The name of the worker.
			property :authenticator,  String, :required => true, :length => 24,  :default => proc { rand(36**24).to_s(36) }
																				# The key, but we can't call it that.

			# Session revocation
			property :invalid_before, DateTime, :required => true, :default => proc { Time.now }

			def to_s
				self.name
			end
		end
	end
end
