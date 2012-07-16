require_relative '../../master'

module Maru
	class Master < Sinatra::Base
		get '/user/login' do
			@title = "log in"

			redirect to('/') if logged_in?
			erb :user_login
		end

		post '/user/login' do
			@title = "log in"

			if user = User.first( :email => params[:email] )
				if user.password_is? params[:password]
					session[:user] = user.id
					session[:user_authenticated_at] = Time.now
					redirect to('/')
				else
					@error = "Wrong email or password."
					erb :user_login
				end
			else
				@error = "Wrong email or password."
				erb :user_login
			end
		end

		get '/user/logout' do
			session[:user] = nil
			redirect to('/')
		end

		post '/user/new' do
			must_be_admin!

			@new_user = User.create :email => params[:email], :password => params[:password]

			content_type 'application/json'
			if @new_user.valid?
				%{{"user":#{@new_user.to_json( :only => [ :id, :email, :can_own_groups, :can_own_workers, :is_admin ] )}}}
			else
				# vuuuuub
				halt 400, {:errors => @new_user.errors.full_messages}.to_json
			end
		end

		put '/user/:id/permission/:field' do
			must_be_admin!

			halt 404 unless @target_user = User.get(params[:id])
			halt 404 unless %w(can_own_groups can_own_workers is_admin).include? params[:field]

			request.body.rewind

			@target_user[params[:field]] = request.body.read.strip

			content_type 'application/json'
			if @target_user.save
				halt 204
			else
				halt 400, {:errors => @target_user.errors.full_messages}.to_json
			end
		end

		get '/user/preferences' do
			must_be_logged_in!

			@title       = "preferences"
			@target_user = @user

			erb :user_preferences
		end

		get '/user/:id/login' do
			must_be_admin!

			if user = User.get(params[:id])
				session[:user] = user.id
				session[:authenticated_at] = Time.now
				redirect to('/')
			else
				halt 404, "not found"
			end
		end

		get '/user/:id/preferences' do
			must_be_admin!

			halt 404 unless @target_user = User.get(params[:id])

			erb :user_preferences
		end

		post '/user/:id/password' do
			must_be_logged_in!

			halt 404 unless @target_user = User.get(params[:id])
			halt 400 unless params[:new_password] == params[:confirm_password]

			if @user == @target_user
				if @user.password_is? params[:current_password]
					@user.password = params[:new_password]
					halt 500 if !@user.save
				else
					halt 400
				end
			elsif @user.is_admin
				@target_user.password = params[:new_password]
				halt 500 if !@target_user.save
			else
				halt 403
			end
		end

		post '/user/:id/logout' do
			must_be_logged_in!

			halt 404 unless @target_user = User.get(params[:id])
			halt 403 unless @user == @target_user or @user.is_admin

			if @target_user.update :invalid_before => Time.now
				session[:authenticated_at] = Time.now if @user == @target_user
				halt 204 # no content
			else
				halt 500
			end
		end

		delete '/user/:id' do
			must_be_logged_in!

			halt 404 unless @target_user = User.get(params[:id])
			halt 403 unless @target_user == @user or @user.is_admin

			User.transaction do
				@target_user.workers.each do |worker|
					if worker.destroy == false
						if worker.update :user => nil
							worker.jobs( :completed_at => nil ).update :worker => nil, :assigned_at => nil
						else
							raise
						end
					end
				end

				# No idea why I have to do this. Apparently destroying the workers makes the user object immutable.
				User.get(@target_user.id).destroy or raise
			end

			session[:user] = nil if @target_user == @user

			halt 204
		end
	end
end
