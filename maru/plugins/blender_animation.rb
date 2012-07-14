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
				group.name params[:name]

				initial_frame, final_frame = params[:initial_frame].to_i, params[:final_frame].to_i

				group.details "initial frame" => initial_frame, "final frame" => final_frame, ".blend file" => params[:blend_file][:filename], "output name" => params[:output_name]

				group.prerequisite :source => params[:blend_file][:tempfile], :destination => params[:blend_file][:filename]

				(initial_frame..final_frame).each do |frame_number|
					group.job do |job|
						job.name    "frame #{frame_number}"
						job.details "frame number" => frame_number
					end
				end
			end

			def process_job(job)
				n = job["details"]["frame number"]
				f = job["group"]["details"][".blend file"]
				o = job["group"]["details"]["output name"]

				if spawn "blender", "--background", File.expand_path(f), "--render-output", File.expand_path(o), "--threads", "1", "--render-frame", n.to_s
					files( o.sub( /#+/ ) { |s| "%0#{s.length}d" % n } )
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
