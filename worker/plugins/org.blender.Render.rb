module Maru
  class BlenderRenderWorker < Maru::Worker::Plugin
    def self.job_type
      "org.blender.Render"
    end

    def initialize(config)
      if config["applications"] && config["applications"]["blender"]
        @blender_executable = config["applications"]["blender"]
      else
        @blender_executable = `which blender`.strip
      end

      if not File.file? @blender_executable
        raise "org.blender.Render: no such file: #@blender_executable"
      end

      unless RUBY_PLATFORM =~ /mingw/i
        if not File.executable? @blender_executable
          raise "org.blender.Render: not an executable: #@blender_executable"
        end
      end
    end

    def prerequisites_for(description)
      reqs = []

      # .blend file (required)
      reqs << {url: description["blend_file_url"], sha256: description["blend_file_sha256"]}

      # TODO: extra resources (maybe)

      return reqs
    end

    def process_job(job)
      blend_file    = job.prerequisites[job.description["blend_file_url"]]
      frame         = job.description["frame"]
      output        = job.description["output"]
      output_file   = job.description["output"].sub(/#+/) { |s| "%0#{s.length}d" % frame }
      output_format = job.description["output_format"] || "PNG"

      job.info "Render frame #{frame} of #{job.description["blend_file_url"].split("/").last}"

      IO.popen([@blender_executable, "--background", blend_file, "--render-output", File.basename(output),
                "--render-format", output_format, "--threads", "1", "--render-frame", frame.to_s, {:err => :out}], "r") do |blender|
        while line = blender.gets
          job.info "  #{line.strip}"
        end
      end

      if File.file? File.basename(output_file)
        job.result output_file, File.open(File.basename(output_file), "rb")
        job.submit
      else
        job.error "output file (#{File.basename(output_file)}) not found"
      end
    end
  end
end
