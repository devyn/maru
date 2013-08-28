before do
  @user = User[session[:username]]
end

helpers do
  def logged_in?
    @user ? true : false
  end

  def must_be_logged_in!
    unless logged_in?
      halt redirect("/session/login?redirect=#{CGI.escape(request.fullpath)}")
    end
  end

  def must_be_admin!
    must_be_logged_in!

    unless @user.is_admin?
      halt 403, "You are not an admin."
    end
  end

  def target_user_is(param_name)
    if !(@target_user = User[params[param_name]])
      halt 404
    end
  end

  def must_be_admin_to_target_others!
    must_be_admin! if @user != @target_user
  end
end
