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

      # Sets up a user-based resource allowing users who are not admins
      # to access their own resources, and admins to access anyone's
      # resources. Places the resource's target user in @target_user.
      def user_resource(user_name)
        halt 403 unless logged_in?
        if @user.name == user_name
          @target_user = @user
        else
          halt 403 unless @user.is_admin
          halt 404 unless @target_user = User[user_name]
        end
      end
    end
  end
end
