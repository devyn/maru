require 'cgi'

class String
	def to_const(root=Object)
		split( / *\/ */ ).inject( root ) { |c,e| c.const_get( e.sub( /^([a-z])/ ) { $1.upcase }.gsub( /[ _]([A-Za-z])/ ) { $1.upcase }.gsub( ' ', '' ) ) }
	end

	def machine_name_to_human_name
		gsub( '/', ' / ' ).gsub( '_', ' ' ).gsub( /\b([A-Za-z])/ ) { $1.upcase }
	end
end

class Module
	def human_name
		name.gsub( /(?<=[a-z])([A-Z])/ ) { " #$1" }.gsub( '::', ' / ' )
	end

	def machine_name
		name.gsub( /(?<=[a-z])([A-Z])/ ) { "_#$1" }.gsub( '::', '/' ).downcase
	end
end

module Maru
	module Plugin
		PLUGINS = []

		def self.included(mod)
			PLUGINS << mod
		end

		def self.[](name)
			PLUGINS.include?(c = name.to_const) ? c : nil
		rescue Exception
			nil
		end

		def spawn(*cmd)
			Process.wait( fork { exec *cmd } )
			$?.success?
		end

		def validate_group_params(params)
			f = GroupFormBuilder.new
			self.build_group_form(f)

			errors = []

			f.restrictions.each do |restriction|
				target = find_name_in(params, restriction[:name]) if restriction[:name]

				if restriction[:empty] == false and !(empty = target.to_s.strip.empty?)
					errors << "#{restriction[:label] || restriction[:name]} is required."
				elsif restriction[:empty] == true and empty
					errors << "#{restriction[:label] || restriction[:name]} must be empty."
				end

				case restriction[:verify]
				when "number"
					# TODO
				when "numbers"
					# TODO
				when "integer"
					# TODO
				when "integers"
					# TODO
				when "url"
					# TODO
				when "urls"
					# TODO
				end

				if restriction[:min_items] and target.is_a? Array and target.size < restriction[:min_items]
					errors << "Not enough #{(restriction[:label] || restriction[:name]).downcase}."
				end

				if restriction[:max_items] and target.is_a? Array and target.size > restriction[:max_items]
					errors << "Too many #{(restriction[:label] || restriction[:name]).downcase}."
				end
			end

			errors
		end

		def find_name_in(params, name)
			if md = name.match(/^\[?([A-Za-z0-9_.-]+)\]/)
				if md.post_match.strip.empty?
					params[params.is_a?(Array) ? md[1].to_i : md[1]]
				else
					find_name_in params[params.is_a?(Array) ? md[1].to_i : md[1]], md.post_match
				end
			else
				nil
			end
		end

		def files *args
			# For now, it's just an array. In the future, we may include
			# a way to upload things other than files.
			args
		end

		class GroupFormBuilder
			attr_reader :html, :restrictions

			def initialize
				@html = ""
				@restrictions = []
				@stack = []
			end

			def <<(s)
				@html << s
			end

			def section(name, options={})
				@html << %'<div class="section#{" expanded" if options[:expanded]}"><h2>#{CGI.escape_html name}</h2>'

				yield if block_given?

				@html << %'</div>'
			end

			def string(name, options={})
				label name, options do
					@html << %'<input id="#{cat_id(name)}" class="#{options[:class] || "string"}" name="#{cat_name(name)}"#{%' type="#{options[:type]}"' if options[:type]}#{%' value="#{options[:default]}"' if options[:default]}/>'

					@restrictions << {label: options[:label], name: cat_name(name), empty: false} unless options[:optional]
				end
			end

			def strings(name, options={})
				@html << %'<h3>#{CGI.escape_html options[:label]}</h3>' if options[:label]

				@html << %'<ul class="#{options[:class] || "strings"}" id="#{cat_id(name)}">'

				if options[:min_items].respond_to? :times
					@stack.push name

					options[:min_items].times do |x|
						@html << %'<li><input id="#{cat_id(x)}" class="#{options[:el_class] || "string"}" name="#{cat_name(x)}"#{%' type="#{options[:el_type]}"' if options[:el_type]}/></li>'
					end

					@stack.pop

					@restrictions << {label: options[:label], name: cat_name(name), min_items: options[:min_items]}
				end

				if options[:max_items]
					@restrictions << {label: options[:label], name: cat_name(name), max_items: options[:max_items]}
				end

				@html << %'</ul>'
			end

			def password(name, options={})
				string name, {:class => "password", :type => "password"}.merge(options)
			end

			def passwords(name, options={})
				strings name, {:class => "passwords", :el_class => "password", :el_type => "password"}.merge(options)
			end

			def file(name, options={})
				string name, {:class => "file", :type => "file"}.merge(options)
			end

			def files(name, options={})
				strings name, {:class => "files", :el_class => "file", :el_type => "file"}.merge(options)
			end

			class OptionBuilder
				attr_reader :html

				def initialize(options)
					@options = options
					@html    = ""
				end

				def option(value, name)
					@html << %'<option#{%' selected="selected" ' if value == @options[:default]}value="#{value}">#{CGI.escape_html name}</option>'
				end
			end

			def selectbox(name, options={})
				label name, options do
					@html << %'<select id="#{cat_id(name)}" class="#{options[:class] || "selectbox"}" name="#{cat_name(name)}">"'

					@html << %'<option value="">--- [select one] ---</option>' unless options[:default]

					@restrictions << {label: options[:label], name: cat_name(name), empty: false} unless options[:optional]

					b = OptionBuilder.new(options)

					yield b if block_given?

					@html << b.html << %'</select>'
				end
			end

			def url(name, options={})
				string name, {:class => "url"}.merge(options)

				if options[:schemes]
					@restrictions << {label: options[:label], name: cat_name(name), verify: "url", schemes: options[:schemes]}
				else
					@restrictions << {label: options[:label], name: cat_name(name), verify: "url"}
				end
			end

			def urls(name, options={})
				strings name, {:class => "urls", :el_class => "url"}.merge(options)

				if options[:schemes]
					@restrictions << {label: options[:label], name: cat_name(name), verify: "urls", schemes: options[:schemes]}
				else
					@restrictions << {label: options[:label], name: cat_name(name), verify: "urls"}
				end
			end

			def number(name, options={})
				string name, {:class => "number"}.merge(options)

				r = {label: options[:label], name: cat_name(name), verify: options[:integer] ? "integer" : "number"}

				r[:min] = options[:min] if options[:min]
				r[:max] = options[:max] if options[:max]

				if options[:range].respond_to? :min and options[:range].respond_to? :max
					r[:min], r[:max] = options[:range].min, options[:range].max
				end

				@restrictions << r
			end

			def numbers(name, options={})
				strings name, {:class => "numbers", :el_class => "number"}.merge(options)

				r = {label: options[:label], name: cat_name(name), verify: options[:integer] ? "integers" : "numbers"}

				r[:min] = options[:min] if options[:min]
				r[:max] = options[:max] if options[:max]

				if options[:range].respond_to? :min and options[:range].respond_to? :max
					r[:min], r[:max] = options[:range].min, options[:range].max
				end

				@restrictions << r
			end

			def integer(name, options={})
				number name, {:integer => true}.merge(options)
			end

			def integers(name, options={})
				numbers name, {:integer => true}.merge(options)
			end

			private

			def cat_id(id)
				"field-" + (@stack + [id]).join('-')
			end

			def cat_name(name)
				n = @stack + [name]
				n[0].to_s + n[1..-1].to_a.map { |s| "[#{s}]" }.join
			end

			def label(name, options)
				@html << %'<label for="#{cat_name(name)}">#{CGI.escape_html options[:label]}' if options[:label]

				yield if block_given?

				@html << "</label>" if options[:label]
			end
		end

		class GroupBuilder
			def initialize(group, filestore=nil)
				@group     = group
				@filestore = filestore
				@post_save = []
			end

			def name(name)
				@group.name = name
			end

			def prerequisite(r)
				if r[:source].respond_to? :read
					if @filestore and @filestore.respond_to? :store_prerequisite
						@post_save << proc do
							url, sha256 = @filestore.store_prerequisite r[:source], r[:destination], @group

							r[:source]   = url
							r[:sha256] ||= sha256

							if r[:sha256] != sha256
								@filestore.delete_prerequisite r[:destination], @group
								raise VerificationFailed
							end

							@group.prerequisites ||= []
							@group.prerequisites << r
						end
					else
						raise CanNotStore
					end
				else
					@group.prerequisites ||= []
					@group.prerequisites << r
				end
			end

			def details(d)
				@group.details ||= {}
				@group.details = @group.details.merge(d)
			end

			def job
				j = JobBuilder.new(Maru::Master::Job.new, @filestore)

				yield j

				@post_save << proc do
					j.save(@group)
				end
			end

			def save
				begin
					Maru::Master::Group.transaction do
						raise if !@group.save

						unless @post_save.empty?
							@post_save.each &:call
							raise if !@group.save
						end

						@post_save = []
					end
				rescue
					return false
				end

				true
			end

			class JobBuilder
				def initialize(job, filestore=nil)
					@job       = job
					@filestore = filestore
					@pre_save  = []
				end

				def name(name)
					@job.name = name
				end

				def prerequisite(r)
					if r[:source].respond_to? :read
						if @filestore and @filestore.respond_to? :store_prerequisite
							@pre_save << proc do
								url, sha256 = @filestore.store_prerequisite r[:source], r[:destination], @job.group

								r[:source]   = url
								r[:sha256] ||= sha256

								if r[:sha256] != sha256
									@filestore.delete_prerequisite r[:source], r[:destination], @job.group
									raise VerificationFailed
								end

								@job.prerequisites ||= []
								@job.prerequisites << r
							end
						else
							raise CanNotStore
						end
					else
						@job.prerequisites ||= []
						@job.prerequisites << r
					end
				end

				def details(d)
					@job.details ||= {}
					@job.details = @job.details.merge(d)
				end

				def save(group)
					@job.group = group

					@pre_save.each &:call
					@pre_save = []

					@job.save
				end
			end

			class CanNotStore < Exception
				def message
					"The filestore provided to the builder is incapable of storing prerequisites."
				end

				alias to_s message
			end

			class VerificationFailed < Exception
				def message
					"The calculated checksum does not match the one provided in the builder."
				end

				alias to_s message
			end
		end
	end
end
