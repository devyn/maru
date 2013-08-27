get '/users' do
  must_be_admin!

  @users = User.all

  erb :users
end

post '/users' do
  must_be_admin!

  error = ->(code, message) {
    @error = message
    @users = User.all

    halt code, erb(:users)
  }

  if params[:username].to_s.strip.empty?
    error.(400, "Username must not be blank.")
  end
  if params[:password].to_s.strip.empty?
    error.(400, "Password must not be blank.")
  end

  begin
    user = User.create(params[:username], params[:password], params[:role] == "admin")
  rescue
    error.(409, "Could not create user: #$!")
  end

  redirect request.referrer
end

get '/my/*' do |splat|
  must_be_logged_in!

  redirect "/user/#{@user.name}/#{splat}"
end

get '/user/:name/clients' do
  must_be_logged_in!

  if !(@target_user = User[params[:name]])
    halt 404
  end

  if @user != @target_user
    must_be_admin!
  end

  erb :'user/clients'
end

post '/user/:name/clients' do
  must_be_logged_in!

  if !(@target_user = User[params[:name]])
    halt 404
  end

  if @user != @target_user
    must_be_admin!
  end

  client_name = params[:client_name].to_s.strip
  permissions = params[:permissions].to_s.split(",").map(&:strip)

  if client_name.empty?
    @error = "Client name must not be empty."

    halt 400, erb(:'/user/clients')
  end

  if permissions.empty?
    @error = "Must specify at least one permission."

    halt 400, erb(:'/user/clients')
  end

  if Client[@target_user.name + "/" + client_name]
    @error = "You have already registered a client with that name."

    halt 409, erb(:'/user/clients')
  else
    client = Client.new(@target_user.name + "/" + params[:client_name])
    
    client.user        = @target_user.name
    client.permissions = params[:permissions] ? params[:permissions].split(",") : []
    client.save

    redirect request.referrer
  end
end
