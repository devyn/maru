require_relative '../master'

module Maru
	class Master < Sinatra::Base
		helpers do
			def get_worker
				@worker
			end

			def get_worker!
				get_worker or halt(403, {"Content-Type" => "text/plain"}, "Who are you? Worker, authenticate!")
			end

			def logged_in?
				!@user.nil?
			end

			def must_be_logged_in!
				redirect to('/user/login') if not logged_in?
			end

			def must_be_able_to_own_groups!
				must_be_logged_in!
				redirect to('/') unless @user.is_admin or @user.can_own_groups
			end

			def must_be_able_to_own_workers!
				must_be_logged_in!
				redirect to('/') unless @user.is_admin or @user.can_own_workers
			end

			def must_be_able_to_manage_users!
				must_be_logged_in!
				redirect_to('/') unless @user.is_admin or @user.can_manage_users
			end

			def must_be_admin!
				must_be_logged_in!
				redirect_to('/') unless @user.is_admin
			end

			def update_group_status(group)
				complete   = group.jobs( :completed_at.not => nil ).length
				processing = group.jobs( :worker.not => nil, :completed_at => nil ).map { |job| {:name => job.name, :worker => job.worker.name} }
				total      = group.jobs.length

				settings.group_subscribers.each do |socket|
					next if !group.public and not (socket.user == group.user or socket.user.is_admin)

					socket.send( { type: "groupStatus", groupID: group.id, complete: complete, processing: processing, total: total, estimatedTimeLeft: group.estimated_time_left }.to_json )
				end
			end
		end
	end
end
