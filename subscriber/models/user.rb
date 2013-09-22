require 'bcrypt'

module Maru
  class Subscriber
    class User < Sequel::Model
      one_to_many :task_relationships, :class => :'Maru::Subscriber::TaskUserRelationship', :key => :user_name
      one_to_many :clients, :key => :user_name

      def password
        BCrypt::Password.new(super)
      end

      def password=(pass)
        super(BCrypt::Password.create(pass))
      end
    end
  end
end
