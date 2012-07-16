require_relative '../../master'

module Maru
	class Master < Sinatra::Base
		class Job
			include DataMapper::Resource

			belongs_to :group
			belongs_to :worker, :required => false

			property :id,            Serial
			property :name,          String,   :required => true, :length => 255
			property :details,       Json,     :default  => {}

			property :expiry,        Integer,  :required => true, :default => 3600 # in seconds after assigned_at

			property :prerequisites, Json,     :default => []

			property :assigned_at,   DateTime
			property :completed_at,  DateTime

			def to_s
				"##{self.id} (#{self.group.name} / #{self.name})"
			end
		end
	end
end
