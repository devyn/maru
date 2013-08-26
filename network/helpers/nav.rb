before do
  @nav_links = []

  if logged_in?
    @nav_links << ["My clients", "/user/clients"]

    if @user.is_admin?
      @nav_links << ["Users",    "/users"]
    end

    @nav_links << ["Log out", "/user/logout"]
  else
    @nav_links << ["Log in", "/user/login"]
  end
end
