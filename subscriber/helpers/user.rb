module Maru
  class Subscriber
    # If a user is logged in, the corresponding User model
    # is automatically loaded and stored in @user on every
    # request. The user's name is stored in session[:user].

    before do
      if session[:user]
        if user = User[session[:user]]
          @user = user
        else
          # The user does not exist in the database, so
          # it makes no sense to leave it in the session
          # data.
          session.delete :user
        end
      end
    end

    helpers do
      def logged_in?
        @user ? true : false
      end
    end
  end
end
