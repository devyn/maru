get '/users' do
  must_be_admin!

  @users = User.all

  haml :users
end

post '/users' do
  must_be_admin!

  if params[:username].to_s.strip.empty?
    return_error "Username must not be blank."
  end
  if params[:password].to_s.strip.empty?
    return_error "Password must not be blank."
  end

  begin
    user = User.create(params[:username], params[:password], params[:role] == "admin")
  rescue
    return_error "Could not create user: #$!"
  end

  return_success "User created successfully."
end

get '/my/*' do |splat|
  must_be_logged_in!

  redirect "/user/#{@user.name}/#{splat}"
end

post '/user/:name/delete' do
  must_be_admin!

  target_user_is(:name)

  if @target_user == @user
    return_error "You can not delete yourself!"
  end

  begin
    @target_user.delete
  rescue
    return_error "Could not delete user: #$!"
  end

  return_success "User deleted successfully."
end

get '/user/:name/password/change' do
  must_be_logged_in!

  target_user_is(:name)
  must_be_admin_to_target_others!

  haml :'user/password/change'
end

post '/user/:name/password/change' do
  must_be_logged_in!

  target_user_is(:name)
  must_be_admin_to_target_others!

  if @user == @target_user
    # then old password is required

    unless @user.password == params[:old_password]
      return_error "Your current password does not match the old password provided."
    end
  end

  new_password     = params[:new_password].to_s
  confirm_password = params[:confirm_password].to_s

  if new_password != confirm_password
    return_error "The new password and confirm password fields differ."
  end

  if new_password.empty?
    return_error "Can not use an empty password."
  end

  @target_user.password = new_password

  return_success "Password changed."
end
