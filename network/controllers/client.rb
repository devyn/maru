get '/user/:name/clients' do
  must_be_logged_in!

  target_user_is(:name)
  must_be_admin_to_target_others!

  haml :'user/clients'
end

post '/user/:name/clients' do
  must_be_logged_in!

  target_user_is(:name)
  must_be_admin_to_target_others!

  client_name = params[:client_name].to_s.strip
  permissions = params[:permissions].to_s.split(",").map(&:strip)

  if client_name.empty?
    return_error "Client name must not be empty."
  end

  if permissions.empty?
    return_error "Must specify at least one permission."
  end

  if Client[@target_user.name + "/" + client_name]
    return_error "You have already registered a client with that name."
  else
    client = Client.new(@target_user.name + "/" + params[:client_name])
    
    client.user        = @target_user.name
    client.permissions = params[:permissions] ? params[:permissions].split(",") : []
    client.save

    return_success "Client created successfully."
  end
end

post '/user/:name/client/:client_name/delete' do
  must_be_logged_in!

  target_user_is(:name)
  must_be_admin_to_target_others!

  if client = Client[@target_user.name + "/" + params[:client_name]]
    client.delete

    return_success "Client deleted successfully."
  else
    halt 404
  end
end

post '/client/*/delete' do |client_name|
  must_be_logged_in!

  if client = Client[client_name]
    if @user.is_admin? or @user.owns_client? client_name
      @target_user = User[client.user] || @user

      client.delete

      return_success "Client deleted successfully."
    else
      halt 403
    end
  else
    halt 404
  end
end
