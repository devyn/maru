module Maru
  class Subscriber
    get '/producer/:slug/form' do
      if task = settings.producer_tasks[params[:slug]]
        task.form.to_html
      else
        404
      end
    end
  end
end
