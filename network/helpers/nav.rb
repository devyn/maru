before do
  @nav_links = []

  if logged_in?
    @nav_links << ["My clients", "/my/clients"]

    if @user.is_admin?
      @nav_links << ["Users",    "/users"]
    end

    @nav_links << ["Log out", "/session/logout"]
  else
    @nav_links << ["Log in", "/session/login"]
  end
end
