require_relative '../../master'

module Maru
	class Master < Sinatra::Base
		class User
			include DataMapper::Resource

			has n, :workers
			has n, :groups,  :constraint => :destroy

			property :id,            Serial
			property :email,         String, :required => true, :length => 255, :unique => true
			property :password_hash, String, :required => true, :length => 64
			property :password_salt, String, :required => true, :length => 4

			# Permissions
			property :can_own_workers,  Boolean, :required => true, :default => false
			property :can_own_groups,   Boolean, :required => true, :default => false
			property :is_admin,         Boolean, :required => true, :default => false

			# Session revocation
			property :invalid_before, DateTime, :required => true, :default => Time.at(0)

			validates_format_of :email, :as => :email_address

			def password=(pass)
				self.password_salt = rand( 36 ** 4 ).to_s( 36 )
				self.password_hash = OpenSSL::HMAC.hexdigest( OpenSSL::Digest::SHA256.new, self.password_salt, pass )
			end

			def password_is?(pass)
				OpenSSL::HMAC.hexdigest( OpenSSL::Digest::SHA256.new, self.password_salt, pass ) == self.password_hash
			end

			def to_s
				email
			end
		end
	end
end
