module Maru
  class Subscriber
    class Client < Sequel::Model
      many_to_one :user, :key => :user_name
      one_to_many :produced_jobs, :class => :Job, :key => :produced_by
    end
  end
end
