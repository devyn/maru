require_relative '../../master'

module Maru
	class Master < Sinatra::Base
		post '/worker/new' do
			must_be_able_to_own_workers!

			@worker = Worker.new :user => @user, :name => params[:name]

			content_type "application/json"
			if @worker.save
				{:worker => @worker}.to_json
			else
				if w = Worker.get( :name => params[:name], :user => nil )
					@worker = w

					@worker.user = @user

					if @worker.save
						{:worker => @worker}.to_json
					else
						halt 400, {:errors => @worker.errors.full_messages}.to_json
					end
				else
					halt 400, {:errors => @worker.errors.full_messages}.to_json
				end
			end
		end

		post '/worker/:id/key/regenerate' do
			must_be_able_to_own_workers!

			@worker = Worker.get(params[:id])

			halt 404 unless @worker
			halt 403 unless @user.is_admin or @user == @worker.user

			@worker.authenticator = rand(36**24).to_s(36)
			@worker.invalid_before = Time.now

			content_type "application/json"
			if @worker.save
				{:worker => @worker}.to_json
			else
				halt 400, {:errors => @worker.errors.full_messages}.to_json
			end
		end

		delete '/worker/:id' do
			must_be_able_to_own_workers!

			@worker = Worker.get(params[:id])

			halt 404 unless @worker
			halt 403 unless @user.is_admin or @user == @worker.user

			if @worker.destroy
				halt 204 # no content
			else
				# forfeit all jobs the worker is currently working on
				@worker.jobs( :completed_at => nil ).update :worker => nil, :assigned_at => nil

				if @worker.update :user => nil
					halt 204
				else
					halt 500
				end
			end
		end
	end
end
