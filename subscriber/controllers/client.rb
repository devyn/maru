module Maru
  class Subscriber
    get '/user/:name/clients' do
      content_type 'application/json'

      user_resource(params[:name])

      Client.filter(user: @target_user).to_json(except: [:user_name], naked: true)
    end

    post '/user/:name/clients' do
      user_resource(params[:name])
    end

    delete '/user/:name/client/:id' do
      user_resource(params[:name])
    end
  end
end
