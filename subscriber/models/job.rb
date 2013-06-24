class Job < Sequel::Model
  many_to_one :task
end
