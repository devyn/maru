module Maru
  class Subscriber
    post '/user/:name/login' do
      content_type 'application/json'

      if user = User[params[:name]]
        if user.password == params[:password]
          session[:user] = user.name
          halt 200, {message: "Successfully logged in"}.to_json
        end
      end
      [403, {message: "Wrong username or password"}.to_json]
    end

    delete '/session' do
      session.delete :user
      200
    end
  end
end
