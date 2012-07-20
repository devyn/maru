require 'cgi'
require 'uri'

require_relative '../master'

class String
	def numeric?
		!!(gsub(' ','') =~ /^-?[0-9]+(?:\.[0-9]+)?(?:e-?[0-9]+)?$/)
	end

	def integer?
		!!(gsub(' ','') =~ /^-?[0-9]+$/)
	end

	def url?
		URI.parse(self)
		true
	rescue
		false
	end
end

class Object
	def define_meta_method name, *args, &block
		class << self
			self
		end.__send__ :define_method, name, *args, &block
	end
end

module Maru
	class Master < Sinatra::Base
		module PluginSupport
			class GroupFormBuilder
				attr_reader :html, :fields, :restrictions

				def initialize
					@html         = ""
					@restrictions = []
					@fields       = {}
					@stack        = []
				end

				def validate(params)
					errors = []

					@restrictions.each do |restriction|
						target = find_name_in(params, restriction[:name]) if restriction[:name]

						friendly_name = restriction[:label] || restriction[:name]

						if restriction[:empty] == false and (empty = target.to_s.strip.empty?)
							errors << "#{friendly_name} is required."
							next
						elsif restriction[:empty] == true and !empty
							errors << "#{friendly_name} must be empty."
							next
						end

						if restriction[:min_items] and (target.nil? or target.size < restriction[:min_items])
							errors << "Not enough #{(restriction[:label] || restriction[:name]).downcase}."
							next
						end

						if restriction[:max_items] and !target.nil? and target.size > restriction[:max_items]
							errors << "Too many #{(restriction[:label] || restriction[:name]).downcase}."
							next
						end

						case restriction[:verify]
						when "number"
							if target.to_s.numeric?
								if restriction[:min] and target.to_f < restriction[:min]
									errors << "#{friendly_name} must be at least #{restriction[:min]}."
								end

								if restriction[:max] and target.to_f > restriction[:max]
									errors << "#{friendly_name} must be at most #{restriction[:max]}."
								end
							else
								errors << "#{friendly_name} must be numeric."
							end
						when "numbers"
							if target.values.all? &:numeric?
								if restriction[:min] and target.to_a.any? { |x| x.to_f < restriction[:min] }
									errors << "#{friendly_name} must contain numbers of at least #{restriction[:min]}."
								end

								if restriction[:max] and target.to_a.any? { |x| x.to_f > restriction[:max] }
									errors << "#{friendly_name} must contain numbers of at most #{restriction[:max]}."
								end
							else
								errors << "#{friendly_name} must contain only numbers."
							end
						when "integer"
							if target.to_s.integer?
								if restriction[:min] and target.to_i < restriction[:min]
									errors << "#{friendly_name} must be at least #{restriction[:min]}."
								end

								if restriction[:max] and target.to_i > restriction[:max]
									errors << "#{friendly_name} must be at most #{restriction[:max]}."
								end
							else
								errors << "#{friendly_name} must be an integer."
							end
						when "integers"
							if target.values.all? &:integer?
								if restriction[:min] and target.to_a.any? { |x| x.to_i < restriction[:min] }
									errors << "#{friendly_name} must contain integers of at least #{restriction[:min]}."
								end

								if restriction[:max] and target.to_a.any? { |x| x.to_i > restriction[:max] }
									errors << "#{friendly_name} must contain integers of at most #{restriction[:max]}."
								end
							else
								errors << "#{friendly_name} must contain only integers."
							end
						when "url"
							if target.to_s.url?
								if restriction[:schemes] and not restriction[:schemes].include? URI.parse(target).scheme.downcase
									supported_schemes = if restriction[:schemes].size == 1
										restriction[:schemes][0].upcase
									else
										restriction[:schemes][0..-2].map(&:upcase).join(", ") + "or " + restriction[:schemes][-1].upcase
									end
									errors << "#{friendly_name} must be a(n) #{supported_schemes} URL."
								end
							else
								errors << "#{friendly_name} must be a URL."
							end
						when "urls"
							if target.values.all? &:url?
								if restriction[:schemes] and not target.values.all? { |u| restriction[:schemes].include? URI.parse(u).scheme.downcase }
									supported_schemes = if restriction[:schemes].size == 1
										restriction[:schemes][0].upcase
									else
										restriction[:schemes][0..-2].map(&:upcase).join(", ") + "and " + restriction[:schemes][-1].upcase
									end
									errors << "#{friendly_name} must contain only #{supported_schemes} URLs."
								end
							else
								errors << "#{friendly_name} must contain only URLs."
							end
						end
					end

					errors
				end

				def process_params(params)
					parout = Object.new

					@fields.each do |field, type|
						val = field.inject(params) { |pa,i| pa[i.to_s] rescue nil }

						case type
						when :string, :password, :url
							val = val.to_s.freeze
						when :strings, :passwords, :urls
							val = val.map { |k,v| v.to_s.freeze }.freeze
						when :number
							val = val.to_f
						when :numbers
							val = val.map { |k,v| v.to_f }.freeze
						when :integer
							val = val.to_i
						when :integers
							val = val.map { |k,v| v.to_i }.freeze
						when :file
							fn = val[:filename]
							val[:tempfile].define_meta_method(:name) { fn }

							val = val[:tempfile]
						when :files
							val = val.map do |k,v|
								fn = v[:filename]
								v[:tempfile].define_meta_method(:name) { fn }

								v[:tempfile]
							end
						when :selectbox
							val = val.to_s.to_sym
						end if val

						parout.define_meta_method(field.last) { val }
					end

					parout
				end

				def <<(s)
					@html << s
				end

				def section(name, options={})
					@html << %'<div class="section#{" expanded" if options[:expanded]}"><h2 onclick="toggleSection(this.parentNode)">#{CGI.escape_html name}</h2>'

					yield if block_given?

					@html << %'</div>'
				end

				def string(name, options={})
					define_field name, :string unless options[:class]

					label name, options do
						@html << %'<input id="#{cat_id(name)}" class="#{options[:class] || "string"}" name="#{cat_name(name)}"#{%' type="#{options[:type]}"' if options[:type]}#{%' value="#{options[:default]}"' if options[:default]}/>'

						@restrictions << {label: options[:label], name: cat_name(name), empty: false} unless options[:optional]
					end
				end

				def strings(name, options={})
					define_field name, :strings unless options[:class]

					@html << %'<h3>#{CGI.escape_html options[:label]}</h3>' if options[:label]

					@html << %'<ul class="#{options[:class] || "strings"}" id="#{cat_id(name)}">'

					if options[:min_items].respond_to? :times
						@stack.push name

						options[:min_items].times do |x|
							@html << %'<li><input id="#{cat_id(x)}" class="#{options[:el_class] || "string"}" name="#{cat_name(x)}"#{%' type="#{options[:el_type]}"' if options[:el_type]}/> <a onclick="removeFromGroupNewFormList(this);">remove</a></li>'
						end

						@stack.pop

						@restrictions << {label: options[:label], name: cat_name(name), min_items: options[:min_items]}
					end

					@html << %'<li class="add-to-list"><a onclick="addToGroupNewFormList(this);">add</a></li>'

					if options[:max_items]
						@restrictions << {label: options[:label], name: cat_name(name), max_items: options[:max_items]}
					end

					@html << %'</ul>'
				end

				def password(name, options={})
					define_field name, :password unless options[:class]

					string name, {:class => "password", :type => "password"}.merge(options)
				end

				def passwords(name, options={})
					define_field name, :passwords unless options[:class]

					strings name, {:class => "passwords", :el_class => "password", :el_type => "password"}.merge(options)
				end

				def file(name, options={})
					define_field name, :file unless options[:class]

					string name, {:class => "file", :type => "file"}.merge(options)
				end

				def files(name, options={})
					define_field name, :files unless options[:class]

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
					define_field name, :selectbox unless options[:class]

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
					define_field name, :url unless options[:class]

					string name, {:class => "url"}.merge(options)

					if options[:schemes]
						@restrictions << {label: options[:label], name: cat_name(name), verify: "url", schemes: options[:schemes]}
					else
						@restrictions << {label: options[:label], name: cat_name(name), verify: "url"}
					end
				end

				def urls(name, options={})
					define_field name, :urls unless options[:class]

					strings name, {:class => "urls", :el_class => "url"}.merge(options)

					if options[:schemes]
						@restrictions << {label: options[:label], name: cat_name(name), verify: "urls", schemes: options[:schemes]}
					else
						@restrictions << {label: options[:label], name: cat_name(name), verify: "urls"}
					end
				end

				def number(name, options={})
					define_field name, :number unless options[:class] or options[:integer]

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
					define_field name, :numbers unless options[:class] or options[:integer]

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
					define_field name, :integer unless options[:class]

					number name, {:integer => true}.merge(options)
				end

				def integers(name, options={})
					define_field name, :integers unless options[:class]

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
					@html << %'<label for="#{cat_name(name)}">#{CGI.escape_html options[:label]}<br/>' if options[:label]

					yield if block_given?

					@html << "</label>" if options[:label]
				end

				def find_name_in(params, name)
					if md = name.match(/^\[?([A-Za-z0-9_.-]+)\]?/)
						if md.post_match.strip.empty?
							params[md[1]]
						else
							find_name_in params[md[1]], md.post_match
						end
					else
						nil
					end
				end

				def define_field(name, type)
					@fields[@stack + [name]] = type
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
end