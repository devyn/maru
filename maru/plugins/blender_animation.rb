require_relative '../plugin'

module Maru
	module Plugins
		module BlenderAnimation
			include Maru::Plugin
			extend self

			def process_job(job)
				n = job["details"]["frame number"]
				f = job["group"]["details"][".blend file"]
				o = job["group"]["details"]["output name"]

				if spawn "blender", "--background", File.expand_path(f), "--render-output", File.expand_path(o), "--threads", "1", "--render-frame", n.to_s
					return [o.sub(/#+/){|s|"%0#{s.length}d" % n}]
				else
					raise "blender failed (exit code #{$?.exitstatus})"
				end
			end

			def validate_group(group)
				{
					".blend file name not specified (details['.blend file'])" =>
						group.details.include?(".blend file"),

					"output file name format not specified (details['output name'])" =>
						group.details.include?("output name"),

					"initial frame number not specified (details['initial frame'])" =>
						group.details.include?("initial frame"),

					"final frame number not specified (details['final frame'])" =>
						group.details.include?("final frame"),

					"no frames to render (range is zero or negative)" =>
						group.details["final frame"].to_i - group.details["initial frame"].to_i > 0,

					"no prerequisites exist with destination matching .blend file name" =>
						group.prerequisites.select { |pre| pre["destination"] == group.details[".blend file"] }.size > 0

				}.reject {|k,v| v}.keys
			end

			def create_jobs_for(group)
				Maru::Master::Job.transaction do
					(group.details["initial frame"].to_i..group.details["final frame"]).each do |frame_number|

						job         = Maru::Master::Job.new
						job.name    = "frame #{frame_number}"
						job.details = {"frame number" => frame_number}
						job.group   = group
						job.expiry  = group.details["expiry"] || 3600
						job.save
					end
				end
			end
		end
	end
end
