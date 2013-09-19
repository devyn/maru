require 'nokogiri'
require 'maru/producer'

module Maru
  class Subscriber
    set :job_type_friendly_names, {}
    set :producer_tasks, {}

    def self.plugin(name, &block)
      PluginAPI.instance_eval &block

      puts ">> Plugin #{name.inspect} loaded" # FIXME: logging
    end

    module PluginAPI
      extend self

      def job_type_friendly_name(job_type, friendly_name)
        Subscriber.settings.job_type_friendly_names[job_type] = friendly_name
      end

      def producer_task(name, stub, &block)
        task = ProducerTask.new(name, stub)
        ProducerTask::Builder.new(task, &block)

        Subscriber.settings.producer_tasks[stub] = task

        nil
      end
    end

    class NumberSet
      include Enumerable

      def initialize(*ranges)
        @ranges = ranges
      end

      def self.from_string(str)
        ranges = str.split(/\s*,\s*/)
                    .map { |r|
                      r = r.split('-');

                      if r[0]
                        r[0].to_i .. (r[1] ? r[1].to_i : r[0].to_i)
                      else
                        nil
                      end
                    }.reject(&:nil?)
        new(*ranges)
      end

      def each(&block)
        @ranges.each do |range|
          if range.respond_to? :each
            range.each(&block)
          else
            block.call(range) # probably a lone number
          end
        end
      end

      def include?(number)
        @ranges.any? { |range|
          if range.respond_to? :include?
            range.include? number
          else
            range == number
          end
        }
      end

      def count
        @ranges.inject(0) { |sum, range|
          if range.respond_to? :count
            sum + range.count
          else
            sum + 1
          end
        }
      end
      alias length count
      alias size count

      def inspect
        "#<#{self.class} #{
          @ranges.map { |range|
            if range.respond_to? :begin and range.respond_to? :end
              if range.begin == range.end
                range.begin.to_s
              else
                "#{range.begin}-#{range.end}"
              end
            else
              range.to_s
            end
          }.join(",")
        }>"
      end
    end

    class FormattableDestination
      attr_reader :task, :options

      def initialize(task, &format_url)
        @task       = task
        @format_url = format_url
        @options    = {}
      end

      def with_name(name)
        d = dup
        d.options = @options.dup
        d.options[:name] = name
        d
      end

      def to_s
        if options[:name]
          @format_url.("/task/#{@task.secret}/submit/#{Rack::Utils.escape(options[:name]).gsub('+','%20')}")
        else
          @format_url.("/task/#{@task.secret}/submit")
        end
      end

      def to_json(*args)
        to_s.to_json(*args)
      end

      protected

      def options=(h)
        @options = h
      end
    end

    class NetworkActionQueue
      def initialize
        @submit = []
        @cancel = []
      end

      def submit(job)
        @submit << job
        nil
      end

      def cancel(id)
        @cancel << id
        nil
      end

      def execute(network_details, &block)
        Maru::Producer.connect(
          network_details[:host],
          network_details[:port],
          network_details[:client_name],
          network_details[:key]
        ) do |ready|
          ready.callback do |producer|
            remaining_ops = @submit.count + @cancel.count
            total_submit  = 0
            total_cancel  = 0
            errors        = []

            op_done = proc do
              remaining_ops -= 1
              if remaining_ops < 1
                producer.close_connection
                block.(total_submit, total_cancel, errors) if block
              end
            end

            @submit.each do |job|
              producer.submit(job).callback {
                total_submit += 1
                op_done.()
              }.errback { |error|
                errors << [:submit, job, error]
                op_done.()
              }
            end

            @cancel.each do |id|
              producer.cancel(id).callback {
                total_cancel += 1
                op_done.()
              }.errback { |error|
                errors << [:cancel, id, error]
                op_done.()
              }
            end
          end.errback do |error|
            block.(0, 0, [error])
          end
        end
      end
    end

    class ProducerTask
      def initialize(name, slug)
        @name     = name
        @slug     = slug
        @form     = Form.new(@slug) {}
        @generate = proc {}
      end

      attr_accessor :name, :slug, :form, :generate

      def generate(network, params)
        @generate.(network, params)
      end

      class Builder
        def initialize(task, &block)
          @task = task
          instance_eval &block
        end

        def form(&block)
          @task.form = Form.new(@task.slug, &block)
        end

        def generate(&block)
          @task.generate = block
        end
      end

      class Form
        # errors
        class FieldError    < StandardError; end

        class FieldEmpty    < FieldError
          def message
            "'#{super}' is a required field."
          end
        end
        class FieldInvalid  < FieldError
          def message
            "'#{super}' contains an invalid value."
          end
        end
        class URLInvalid    < FieldInvalid
          def message
            super.sub(/value\.$/, 'URL.')
          end
        end
        class SHA256Invalid < FieldInvalid
          def message
            super.sub(/value\.$/, 'SHA-256 checksum.')
          end
        end

        def initialize(root, &block)
          @root  = root
          @block = block
        end

        attr_reader :root

        def to_html
          Builder.new(@root, &@block).to_html
        end
        alias to_s to_html

        def process(params, instructions=nil)
          if instructions.nil?
            instructions = Builder.new(@root, &@block).processing_instructions
            params       = params[@root]
          end

          instructions.inject({}) { |result, instruction|
            type, label, name, options, body = instruction

            p_name = name.to_s

            case type
            when :string, :url, :sha256, :numbers
              # All of these can be optional in the same way
              if params[p_name].nil? or params[p_name].strip.empty?

                if options[:optional]
                  result[name] = nil
                elsif options[:default]
                  result[name] = options[:default]
                else
                  raise FieldEmpty, label
                end
              else
                # We do have to handle them separately once we know
                # they're not empty, though.

                case type
                when :string
                  result[name] = params[p_name].to_s
                when :url
                  begin
                    result[name] = URI.parse(params[p_name])
                  rescue
                    raise URLInvalid, label
                  end
                when :sha256
                  if params[p_name] =~ /^\s*[0-9A-Fa-f]{64}\s*$/
                    result[name] = params[p_name].strip
                  else
                    raise SHA256Invalid, label
                  end
                when :numbers

                  result[name] = NumberSet.from_string(params[p_name])
                end
              end
            when :prerequisite
              begin
                if params[p_name].is_a? Hash
                  result[name] = process(params[p_name], body)
                else
                  raise FieldEmpty, label
                end
              rescue FieldEmpty
                if options[:optional]
                  result[name] = nil
                elsif options[:default]
                  result[name] = options[:default]
                else
                  raise FieldEmpty, label
                end
              end
            end

            result
          }
        end

        class Builder
          def initialize(root, &block)
            @root = root

            @processing_instructions = []
            @processing_stack        = [@processing_instructions]
            @param_stack             = [@root]

            @doc = Nokogiri::HTML::DocumentFragment.parse("")

            Nokogiri::HTML::Builder.with(@doc) do |html|
              @html = html

              instance_eval &block
            end
          end

          attr_reader :root, :processing_instructions

          def string(label, param_name, options={})
            @processing_stack.last.push [:string, label, param_name, options]

            basic_input("string", label, param_name, options)
          end

          def numbers(label, param_name, options={})
            @processing_stack.last.push [:numbers, label, param_name, options]

            basic_input("numbers", label, param_name, options)
          end

          def prerequisite(label, param_name, options={})
            @processing_stack.last.push [:prerequisite, label, param_name, options,
                                         [[:url, "URL", :url, {}],
                                          [:sha256, "SHA-256 checksum", :sha256, optional: true]]]

            @html.div :class => "prerequisite_field_group" do
              @html.label label

              @html.div :class => "group_box" do
                basic_input "prerequisite_url url", "URL", "#{param_name}[url]"
                basic_input "prerequisite_sha256 sha256", "SHA-256 checksum", "#{param_name}[sha256]", optional: true
              end
            end
          end

          def basic_input(css_class, label, param_name, options={})
            param_name = format_param_name(param_name)

            @html.div :class => [
              'field_group',
              ('required' unless options[:optional] or options[:default]),
              css_class
            ].join(' ') do

              @html.label do
                @html.text label
                if options[:example]
                  @html.text  " "
                  @html.small "(e.g. #{options[:example]})", :class => "example"
                end
              end

              @html.input({:name => param_name}.update(options[:default] ? {:placeholder => options[:default]} : {}))
            end
          end

          def format_param_name(param_name)
            (@param_stack + [param_name]).inject("") { |s,b|
              s.empty? ? b : "#{s}[#{b}]"
            }
          end

          def to_html
            @doc.to_html
          end
        end
      end
    end
  end
end

