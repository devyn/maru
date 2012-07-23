require_relative '../../master'

module Maru
	class Master < Sinatra::Base
		get '/worker/authenticate' do
			content_type "text/plain"

			session[:challenge] = rand(36**20).to_s(36)
		end

		post '/worker/authenticate' do
			content_type "text/plain"

			if session[:challenge]
				target = Worker.first :name => params[:name], :user.not => nil

				if target and params[:response] == OpenSSL::HMAC.hexdigest(OpenSSL::Digest::SHA256.new, target.authenticator, session[:challenge])
					session[:worker]                  = target.id
					session[:worker_authenticated_at] = Time.now
					session[:challenge]               = nil
					"Authentication successful."
				else
					session[:challenge] = nil
					halt 403, "Authentication failed. You'll have to get another challenge."
				end
			else
				halt 400, "You must first obtain a challenge. (GET /worker/authenticate)"
			end
		end

		get '/job' do
			content_type "application/json"

			worker = get_worker!

			jobs = Job.all :worker => nil, :group => { :kind => params[:kinds].split( ',' ), :paused => false }

			unless params[:blacklist].to_s.empty?
				jobs = jobs.all :id.not => params[:blacklist].split( ',' ).map( &:to_i )
			end

			job = jobs.first :offset => rand(jobs.count)

			if job.nil?
				halt 204, JSON.dump( :error => "no jobs available" )
			else
				job.update :worker => worker, :assigned_at => Time.now

				Log.info "Job #{job} assigned to #{worker}"

				update_group_status job.group

				%{{"job":#{job.to_json( :exclude => [:worker_id, :user_id], :relationships => {:group => {:relationships => {:user => {:only => [:email]}}}} )}}}
			end
		end

		post '/job/:id' do
			content_type "application/json"

			begin
				worker = get_worker!

				job = Job.first :id => params[:id], :worker => worker

				result_url = nil

				if job.nil?
					halt 404, JSON.dump( :error => "job not found" )
				else
					params[:files].each do |index, file|
						begin
							if settings.filestore.respond_to? :store_result
								file["data"][:tempfile].rewind

								result_url, sha256 = settings.filestore.store_result file["data"][:tempfile], file["name"], job.group

								if file["sha256"] and file["sha256"] != sha256
									settings.filestore.delete_result file["name"], job.group
									halt 400, JSON.dump( :error => "SHA256 invalid for #{file["name"]}" )
								end
							else
								# discard it with a warning
								Log.warn "#{job}: result discarded because filestore is unable to store it"
							end
						ensure
							file["data"][:tempfile].close
						end
					end if params[:files]

					job.update :completed_at => Time.now

					group = job.group
					dt    = job.completed_at.to_time - job.assigned_at.to_time
					w     = group.jobs(:worker.not => nil, :completed_at => nil).length + 1

					if group.average_job_time.nil?
						group.average_job_time = dt
					else
						group.average_job_time = group.average_job_time * 0.9 + dt * 0.1
					end

					if group.average_amount_of_workers.nil?
						group.average_amount_of_workers = w
					else
						group.average_amount_of_workers = group.average_amount_of_workers * 0.7 + w * 0.3
					end

					group.save

					Log.info "Job #{job} completed by #{worker}"

					update_group_status job.group

					JSON.dump( :success => true, :result_url => result_url )
				end
			rescue Exception
				Log.error "In completion of job ##{params[:id]}" do
					Log.exception $!
				end

				halt 500, JSON.dump( :error => $!.to_s )
			end
		end

		post '/job/:id/forfeit' do
			content_type "application/json"

			worker = get_worker!

			job = Job.first :id => params[:id], :worker => worker

			if job.nil?
				halt 404, JSON.dump( :error => "job not found" )
			else
				job.update :worker => nil, :assigned_at => nil

				Log.warn "Job #{job} forfeited by #{worker}"

				update_group_status job.group

				JSON.dump( :success => true )
			end
		end
	end
end
