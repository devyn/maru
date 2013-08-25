get '/user/login' do
  if logged_in?
    redirect '/'
  else
    erb :'user/login'
  end
end

post '/user/login' do
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

get '/user/clients' do
  must_be_logged_in!

  @target_user = @user

  erb :'user/clients'
end

post '/user/clients' do
  must_be_logged_in!

  if Client[@user.name + "/" + params[:client_name]]
    @error = "You have already registered a client with that name."

    [409, erb(:'/user/clients')]
  else
    client = Client.new(@user.name + "/" + params[:client_name])
    
    client.user        = @user.name
    client.permissions = params[:permissions] ? params[:permissions].split(",") : []
    client.save

    redirect request.referrer
  end
end
