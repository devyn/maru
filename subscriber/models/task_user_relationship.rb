module Maru
  class Subscriber
    class TaskUserRelationship < Sequel::Model
      many_to_one :task
      many_to_one :user, :key => :user_name
    end
  end
end
