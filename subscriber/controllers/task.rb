module Maru
  class Subscriber
    configure do
      set :tasks_subscribers, {}

      # keepalive
      Thread.start do
        loop do
          begin
            settings.tasks_subscribers.values.each do |streams|
              streams.each do |out|
                EventMachine.next_tick { out << ":\n" }
              end
            end
          rescue
          end
          sleep 20
        end
      end
    end

    helpers do
      def task_event(event, task, data)
        event_text = "event: #{event}\ndata: #{data.to_json}\n\n"

        settings.tasks_subscribers.each do |target, streams|
          if target == :public
            if task.visibility_level <= 0
              streams.each { |out| out << event_text }
            end
          elsif task.visibility_level <= 1
            streams.each { |out| out << event_text }
          elsif task.user_relationships.find { |r| r.user_name == target }
            streams.each { |out| out << event_text }
          end
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
          task_event "jobsubmitted", @task, {
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

      halt 403, {errors: ["You are not logged in"]} unless @user

      if params[:total_jobs] and params[:total_jobs].to_i < 1
        params[:total_jobs] = nil
      end

      @task = Task.new(
        name:               params[:name],
        secret:             "%032x" % rand(16**32),
        total_jobs:         (params[:producer] ? nil : params[:total_jobs]),
        visibility_level:   params[:visibility_level].to_i,
        results_are_public: (params[:results_are_public] ? true : false)
      )

      if @task.save
        @task.add_user_relationship(user: @user, relationship_type: 3) # Set self as owner.

        task_event "taskcreated", @task, {id: @task.id, name: @task.name, total_jobs: @task.total_jobs}

        result = {id: @task.id, secret: @task.secret, submit_to: URI.join(request.url, "/task/#{@task.secret}/submit")}

        if !params[:producer].nil? and !params[:producer].strip.empty? and
           (@producer_task = settings.producer_tasks[params[:producer]])

          run_producer_on(@producer_task, @task) {
            result.to_json
          }
        else
          result.to_json
        end
      else
        [400, {errors: @task.errors.to_json}]
      end
    end

    post '/task/:id/produce' do
      content_type "application/json"

      if @task = Task[params[:id]]
        if @relationship = TaskUserRelationship.filter(user: @user, task: @task)
                                               .where { |r| r.relationship_type >= 2 }.first

          if !params[:producer].nil? and !params[:producer].strip.empty? and
             (@producer_task = settings.producer_tasks[params[:producer]])

            run_producer_on(@producer_task, @task) {
              {success: true}.to_json
            }
          else
            400 # Bad request
          end
        else
          403 # Forbidden
        end
      else
        404 # Not found
      end
    end

    helpers do
      def dump_all_tasks(user)
        # If we have a user, get all tasks that are at most
        # visibility level 1 (members-only). Otherwise,
        # only public tasks will be shown.
        tasks = Task.where { |task| task.visibility_level <= (user ? 1 : 0) }

        if user
          # We don't need to restrict relationship_type, because even
          # the lowest privilege allows the task to be viewed.
          tasks = tasks.union(Task.filter(id: TaskUserRelationship.filter(user: user).select(:task_id)))
        end

        tasks.all.map { |task|
          submitted_jobs = Job.filter(task: task).exclude(submitted_at: nil).order(Sequel.desc(:submitted_at))

          task_description = {
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

          if user
            if relationship = user.task_relationships.find { |r| r.task_id == task.id }
              task[:relationship_to_user] = relationship.relationship_type

              if relationship.relationship_type >= 2
                # Properties only visible to contributors
                task_description[:secret]    = task.secret
                task_description[:submit_to] = url("/task/#{task.secret}/submit")
              end
            end
          end

          task_description
        }.sort { |task1, task2|
          # Sort again with tasks with the most recent job submissions coming first

          if task1[:recent_jobs].empty?
            -1
          elsif task2[:recent_jobs].empty?
            1
          else
            task1[:recent_jobs].first[:submitted_at] <=> task2[:recent_jobs].first[:submitted_at]
          end
        }
      end

      def notify_task_changed_total(task)
        task_event "changetotal", task, {task_id: task.id, total_jobs: task.total_jobs}
      end
    end

    get "/tasks" do
      content_type 'application/json'

      dump_all_tasks(@user).to_json
    end

    get "/tasks.event-stream" do
      content_type "text/event-stream"

      stream :keep_open do |out|
        out << "event: reload\ndata: #{dump_all_tasks(@user).to_json}\n\n"

        streams = settings.tasks_subscribers[@user ? @user.name : :public] ||= []

        streams << out

        out.callback do
          streams.delete out
        end
        out.errback do
          streams.delete out
        end
      end
    end
  end
end
