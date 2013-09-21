module Maru
  class Subscriber
    class Job < Sequel::Model
      many_to_one :task
      many_to_one :produced_by, :class => :'Maru::Subscriber::Client', :key => :produced_by
    end
  end
end
