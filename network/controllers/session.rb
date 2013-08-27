get '/session/login' do
  if logged_in?
    redirect '/'
  else
    erb :'user/login'
  end
end

post '/session/login' do
  if logged_in?
    redirect '/'
  else
    if user = User[params[:username]]
      if user.password == params[:password]
        session[:username] = user.name

        redirect(params[:redirect] || '/')
      else
        @error = "Invalid username or password."
        erb :'user/login'
      end
    else
      @error = "Invalid username or password."
      erb :'user/login'
    end
  end
end

get '/session/logout' do
  if logged_in?
    session[:username] = nil

    redirect(params[:redirect] || '/')
  else
    redirect '/'
  end
end
