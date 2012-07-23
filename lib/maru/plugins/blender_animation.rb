require_relative '../plugin'

module Maru
	module Plugins
		module BlenderAnimation
			include Maru::Plugin
			extend self

			def build_group_form(form)
				form.string :name, :label => "Name"

				form.file :blend_file, :label => ".blend file"

				form.integer :initial_frame, :label => "Initial frame number"
				form.integer :final_frame,   :label => "Final frame number"

				form.string  :output_name,   :label => "Output file name (# = frame number)", :default => "####.png"
			end

			def build_group(group, params)
				group.name params.name

				group.details "initial frame" => params.initial_frame, "final frame" => params.final_frame,
				              ".blend file" => params.blend_file.name, "output name" => params.output_name

				group.prerequisite :source => params.blend_file, :destination => params.blend_file.name

				(params.initial_frame..params.final_frame).each do |frame_number|
					group.job do |job|
						job.name    "frame #{frame_number}"
						job.details "frame number" => frame_number
					end
				end
			end

			def process_job(job, result)
				n = job.details["frame number"]
				f = job.group.details[".blend file"]
				o = job.group.details["output name"]

				if spawn "blender", "--background", File.expand_path(f), "--render-output", File.expand_path(o), "--threads", "1", "--render-frame", n.to_s
					result.files( o.sub( /#+/ ) { |s| "%0#{s.length}d" % n } )
				else
					if $?.termsig
						fail "blender interrupted (signal #{$?.termsig})"
					else
						fail "blender failed (exit code #{$?.exitstatus})"
					end
				end
			end
		end
	end
end
