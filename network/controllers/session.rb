get '/session/login' do
  if logged_in?
    redirect '/'
  else
    haml :'user/login'
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
        return_error "Invalid username or password."
      end
    else
      return_error "Invalid username or password."
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
