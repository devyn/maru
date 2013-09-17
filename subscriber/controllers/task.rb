module Maru
  class Subscriber
    configure do
      set :tasks_subscribers, []

      # keepalive
      Thread.start do
        loop do
          begin
            settings.tasks_subscribers.each do |out|
              out << ":\n"
            end
          rescue
          end
          sleep 20
        end
      end
    end

    helpers do
      def task_event(event, data)
        event_text = "event: #{event}\ndata: #{data.to_json}\n\n"

        settings.tasks_subscribers.each do |out|
          out << event_text
        end
      end
    end

    post %r{/task/([A-Za-z0-9]{32})/submit(?:/(.*))?} do |secret, name|
      if @task = Task.find(secret: secret)
        @job = Job.new(task: @task, name: name, submitted_at: Time.now)

        @job.type        = request.env["HTTP_X_MARU_JOB_TYPE"]
        @job.description = request.env["HTTP_X_MARU_JOB_DESCRIPTION"]
        @job.worker      = request.env["HTTP_X_MARU_WORKER_ID"]

        files = []
        params[:results].each do |filename, result|
          if @task.save_result(filename, result)
            files << filename
          end
        end

        @job.files = files.join("\n")

        if @job.save
          task_event "jobsubmitted", {
            task_id:      @task.id, 
            name:         @job.name,
            files:        @job.files,
            worker:       @job.worker,
            type:         @job.type,
            submitted_at: @job.submitted_at.utc.strftime("%Y-%m-%dT%H:%M:%SZ")
          }

          200
        else
          [400, {errors: @job.errors.to_json}]
        end
      else
        halt 404
      end
    end

    post "/tasks" do
      content_type 'application/json'

      if params[:total_jobs] and params[:total_jobs].to_i < 1
        params[:total_jobs] = nil
      end

      @task = Task.new(
        name:       params[:name],
        secret:     "%032x" % rand(16**32),
        total_jobs: params[:total_jobs]
      )

      if @task.save
        task_event "taskcreated", {id: @task.id, name: @task.name, total_jobs: @task.total_jobs}

        {id: @task.id, secret: @task.secret, submit_to: URI.join(request.url, "/task/#{@task.secret}/submit")}.to_json
      else
        [400, {errors: @task.errors.to_json}]
      end
    end

    helpers do
      def dump_all_tasks
        Task.all.map { |task|
          submitted_jobs = Job.filter(task: task).exclude(submitted_at: nil).order(Sequel.desc(:submitted_at))

          {
            id:             task.id,
            name:           task.name,
            total_jobs:     task.total_jobs,
            submitted_jobs: submitted_jobs.count,
            recent_jobs:    submitted_jobs.limit(10).all.map { |job|
              {
                name:         job.name,
                files:        job.files,
                worker:       job.worker,
                type:         job.type,
                submitted_at: job.submitted_at.utc.strftime("%Y-%m-%dT%H:%M:%SZ")
              }
            }
          }
        }
      end
    end

    get "/tasks" do
      content_type 'application/json'

      dump_all_tasks.to_json
    end

    get "/tasks.event-stream" do
      content_type "text/event-stream"

      stream :keep_open do |out|
        out << "event: reload\ndata: #{dump_all_tasks.to_json}\n\n"

        settings.tasks_subscribers << out

        out.callback do
          settings.tasks_subscribers.delete out
        end
        out.errback do
          settings.tasks_subscribers.delete out
        end
      end
    end
  end
end
