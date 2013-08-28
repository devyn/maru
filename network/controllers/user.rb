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
    error.(422, "Username must not be blank.")
  end
  if params[:password].to_s.strip.empty?
    error.(422, "Password must not be blank.")
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

  target_user_is(:name)
  must_be_admin_to_target_others!

  erb :'user/clients'
end

post '/user/:name/clients' do
  must_be_logged_in!

  target_user_is(:name)
  must_be_admin_to_target_others!

  client_name = params[:client_name].to_s.strip
  permissions = params[:permissions].to_s.split(",").map(&:strip)

  if client_name.empty?
    @error = "Client name must not be empty."

    halt 422, erb(:'user/clients')
  end

  if permissions.empty?
    @error = "Must specify at least one permission."

    halt 422, erb(:'user/clients')
  end

  if Client[@target_user.name + "/" + client_name]
    @error = "You have already registered a client with that name."

    halt 409, erb(:'user/clients')
  else
    client = Client.new(@target_user.name + "/" + params[:client_name])
    
    client.user        = @target_user.name
    client.permissions = params[:permissions] ? params[:permissions].split(",") : []
    client.save

    redirect request.referrer
  end
end

get '/user/:name/password/change' do
  must_be_logged_in!

  target_user_is(:name)
  must_be_admin_to_target_others!

  erb :'user/password/change'
end

post '/user/:name/password/change' do
  must_be_logged_in!

  target_user_is(:name)
  must_be_admin_to_target_others!

  if @user == @target_user
    # then old password is required

    unless @user.password == params[:old_password]
      @error = "Your current password does not match the old password provided."

      halt 403, erb(:'user/password/change')
    end
  end

  new_password     = params[:new_password].to_s
  confirm_password = params[:confirm_password].to_s

  if new_password != confirm_password
    @error = "The new password and confirm password fields differ."

    halt 422, erb(:'user/password/change')
  end

  if new_password.empty?
    @error = "Can not use an empty password."

    halt 422, erb(:'user/password/change')
  end

  @target_user.password = new_password

  @success = "Password changed."

  erb :'user/password/change'
end
