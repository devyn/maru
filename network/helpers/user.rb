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
end
