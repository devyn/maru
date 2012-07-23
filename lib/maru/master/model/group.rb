require_relative '../../master'

class Numeric
	def humanize_seconds
		days    = self / 86400
		hours   = self % 86400 / 3600
		minutes = self % 3600 / 60
		seconds = self % 60

		out = []
		out << "#{days.floor} day#{'s' unless days == 1}"          if days    >= 1
		out << "#{hours.floor} hour#{'s' unless hours == 1}"       if hours   >= 1
		out << "#{minutes.floor} minute#{'s' unless minutes == 1}" if minutes >= 1
		out << "%.1f second#{'s' unless seconds == 1}" % seconds   if out.empty? or (hours < 1 and seconds >= 0)

		if out.empty?
			"0 seconds"
		elsif out.size == 1
			out.first
		else
			"#{out[0..-2].join(", ")} and #{out.last}"
		end
	end
end

module Maru
	class Master < Sinatra::Base
		class Group
			include DataMapper::Resource

			belongs_to :user

			has n, :jobs, :constraint => :destroy

			property :id,            Serial
			property :name,          String,  :required => true, :length  => 255
			property :details,       Json,    :default  => {}
			property :paused,        Boolean, :required => true, :default => false

			property :kind,          String,  :required => true, :length  => 255

			property :public,        Boolean, :required => true, :default => false

			property :prerequisites, Json,    :default => []

			property :average_job_time,          Float
			property :average_amount_of_workers, Float

			timestamps :created_at

			def to_s
				"##{self.id} (#{self.name} - #{self.user.email})"
			end

			def estimated_time_left
				current     = jobs(:completed_at => nil).length
				most_recent = jobs(:completed_at.not => nil, :order => [:completed_at.desc]).first

				if current == 0
					"none"
				elsif most_recent.nil? or average_job_time.nil? or average_amount_of_workers.nil?
					"unknown"
				else
					if (t = average_job_time * current / average_amount_of_workers - (Time.now - most_recent.completed_at.to_time)) > 0
						t.humanize_seconds
					else
						"unknown"
					end
				end
			end
		end
	end
end
