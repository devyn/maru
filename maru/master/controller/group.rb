require_relative '../../master'

module Maru
	class Master < Sinatra::Base
		get '/group/new' do
			must_be_able_to_own_groups!

			@title = "submit work"

			erb :group_new
		end

		get '/group/new/form/*' do |kind|
			content_type "application/x-json-and-html-separated-by-zero-byte"

			halt 404 unless plugin = Maru::Plugin[kind]

			f = Maru::Plugin::GroupFormBuilder.new

			plugin.build_group_form(f)

			%'#{f.restrictions.to_json}\0#{f.html}'
		end

		post '/group/new' do
			must_be_able_to_own_groups!

			if params[:kind].nil? or !(plugin = Maru::Plugin[params[:kind]])
				@error = "- unsupported group kind"
				halt 400, erb(:group_new)
			end

			group        = Group.new
			group.user   = @user
			group.kind   = params[:kind]
			group.public = params[:public] ? true : false

			if !(errors = plugin.validate_group_params(params)).empty?
				@error = errors.map { |e| "- #{e}" }.join("\n")
				halt 400, erb(:group_new)
			end

			group_builder = Maru::Plugin::GroupBuilder.new group, settings.filestore

			plugin.build_group(group_builder, params)

			if group_builder.save
				redirect to('/')
			else
				@error = group.errors.full_messages.map { |e| "- #{e}" }.join("\n")
				halt 400, erb(:group_new)
			end
		end

		get '/group/:id.json' do
			# Returns information about a group in JSON format, for automation purposes
			halt 501
		end

		get '/group/:id/edit' do
			# Form for editing groups
			# Not all group kinds may be editable
			halt 501
		end

		post '/group/:id' do
			# Edits/updates a group
			halt 501
		end

		post '/group/:id/pause' do
			must_be_able_to_own_groups!

			halt 404 unless @group = Group.get(params[:id])
			halt 403 unless @group.user == @user or @user.is_admin

			if @group.update :paused => true
				halt 204
			else
				halt 500
			end
		end

		post '/group/:id/resume' do
			must_be_able_to_own_groups!

			halt 404 unless @group = Group.get(params[:id])
			halt 403 unless @group.user == @user or @user.is_admin

			if @group.update :paused => false
				halt 204
			else
				halt 500
			end
		end

		delete '/group/:id' do
			must_be_able_to_own_groups!

			halt 404 unless @group = Group.get(params[:id])
			halt 403 unless @group.user == @user or @user.is_admin

			if @group.destroy
				if settings.filestore.respond_to? :clean
					settings.filestore.clean @group
				end

				halt 204
			else
				halt 500
			end
		end

		get '/group/:id/details' do
			if @group = Group.get(params[:id])
				erb :details, :layout => false
			else
				halt 404
			end
		end
	end
end
