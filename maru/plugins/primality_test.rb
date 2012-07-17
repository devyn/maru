require_relative '../plugin'

require 'mathn'

module Maru
	module Plugins
		module PrimalityTest
			include Maru::Plugin
			extend self

			def build_group_form(form)
				form.integer :start, :label => "First integer to test"
				form.integer :end, :label => "Last integer to test"
			end

			def build_group(group, params)
				range = params[:start].to_i .. params[:end].to_i

				group.name "Primes from #{range.min} to #{range.max}"
				group.details :start => range.min, :end => range.max

				range.each do |x|
					group.job do |job|
						job.name x.to_s
						job.details :number => x
					end
				end
			end

			def process_job(job, result)
				number = job["details"]["number"]

				if number.prime?
					log.info "#{number} is a prime number"

					File.open("#{number}.prime", "w").close
					result.files "#{number}.prime"
				else
					log.info "#{number} is not a prime number"
				end
			end
		end
	end
end
