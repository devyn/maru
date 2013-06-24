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
      200
    else
      [400, @job.errors.to_json]
    end
  else
    halt 404
  end
end
