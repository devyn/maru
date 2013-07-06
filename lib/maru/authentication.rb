require 'openssl'

module Maru
  module Authentication
    class Challenge
      def initialize(key)
        @key              = key
        @challenge_string = "%064x" % rand(2**256) # 64 random hexadecimal
      end

      def verify(response)
        response == Maru::Authentication.respond(@challenge_string, @key)
      end

      def to_s
        @challenge_string
      end
    end

    def self.respond(challenge_string, key)
      OpenSSL::HMAC.hexdigest(OpenSSL::Digest::SHA256.new, key, challenge_string)
    end
  end
end
