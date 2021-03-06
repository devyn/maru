module Maru
  class Subscriber
    def run_producer_on(producer_task, task, &block)
      if params[:network] and !params[:network].strip.empty?
        if client = Client.find(user: @user, is_producer: true, id: params[:network])
          network_details = {
            host:        client.remote_host,
            port:        client.remote_port,
            client_name: client.name,
            key:         client.key
          }
        else
          return halt(404, {errors: ["Target network not found."]}.to_json)
        end
      else
        return halt(400, {errors: ["No target network specified."]}.to_json)
      end

      begin
        producer_params = producer_task.form.process(params)
      rescue ProducerTask::Form::FieldError
        return halt(400, {errors: [$!.message]}.to_json)
      end

      producer_params[:destination] = FormattableDestination.new(task) { |rel| url(rel) }

      queue = NetworkActionQueue.new

      producer_task.generate(queue, producer_params)

      stream :keep_open do |out|
        queue.execute(network_details) { |total_created, total_cancelled, errors|
          if params[:increase_total]
            task.total_jobs ||= 0
            task.total_jobs += total_created - total_cancelled
            task.save

            notify_task_changed_total(task)
          end

          out << block.(errors) if block
          out.close
        }
      end
    end
  end
end
