module Devyn
  class EchoWorker < Maru::Worker::Plugin
    def self.job_type
      "me.devyn.maru.Echo"
    end

    def initialize(config)
    end

    def prerequisites_for(description)
      if description["external"]
        description["external"].map do |result_name, info|
          {url: info["url"], sha256: info["sha256"]}
        end
      else
        []
      end
    end

    def process_job(job)
      job.description["results"].each do |file, body|
        job.info "Add result: #{file}"

        job.result file, body
      end

      if job.description["external"]
        job.description["external"].each do |result_name, info|
          job.info "Add external result: #{result_name}"

          job.result result_name, File.open(job.prerequisites[info["url"]], 'r')
        end
      end

      job.submit
    end
  end
end
