#!/usr/bin/env ruby

$:.unshift(File.join(File.dirname(__FILE__), "..", "lib"))

require 'optparse'
require 'eventmachine'

require 'maru/producer'

job = {
  type: "me.devyn.maru.Echo",
  destination: nil,
  description: {}
}

result_name   = nil
result_sha256 = nil

host = "localhost"
port = 8490
client_name = nil
client_key = nil

repeat = 1

job_file = nil
cancel   = false

opts = OptionParser.new

opts.on "-N", "--network HOST[:PORT]", "Network address" do |hostport|
  host, port = hostport.split(":")
  port       = port ? port.to_i : 8490
end

opts.on "-l", "--client-name STRING", "Client name" do |name|
  client_name = name
end

opts.on "-k", "--client-key STRING", "Client key" do |key|
  client_key = key
end

opts.on "-d", "--destination URL", "Job destination URL" do |destination|
  job[:destination] = destination
end

opts.on "--name STRING", "Name a result" do |n|
  result_name = n
end

opts.on "--result STRING", "Add a result" do |r|
  if result_name
    job[:description][:results] ||= {}
    job[:description][:results][result_name] = r

    result_name = nil
  else
    abort "result name required"
  end
end

opts.on "--sha256 STRING", "Set the SHA-256 sum for an external result (optional)" do |sha256|
  result_sha256 = sha256
end

opts.on "--external URL", "Add an external result" do |url|
  if result_name
    job[:description][:external] ||= {}
    job[:description][:external][result_name] = {url: url, sha256: result_sha256}

    result_name   = nil
    result_sha256 = nil
  else
    abort "result name required"
  end
end

opts.on "--repeat N", "Number of times to submit the job" do |number|
  repeat = number.to_i
end

opts.on "--job-file FILE", "File to input/output jobs from/to (depending on operation)" do |f|
  job_file = f
end

opts.on "--cancel", "Performs cancel operation instead (must specify --job-file)" do
  cancel = true
end

opts.on_tail "-h", "--help", "Print this message and exit" do
  puts opts
  exit
end

opts.parse!(ARGV)

class String
  def decode_irle
    split(",").inject([]) { |o, pair|
      if pair =~ /(\d+)\.\.(\d+)/
        o += ($1.to_i .. $2.to_i).to_a
      end
      o
    }
  end
end

class Array
  def encode_irle
    o = []
    range = nil

    sort.each do |num|
      next unless num.is_a? Integer

      if range
        if num == range.end + 1
          range = range.begin .. num
        else
          o << range
          range = num .. num
        end
      else
        range = num .. num
      end
    end

    o << range if range

    return o.map { |r| "#{r.begin}..#{r.end}" }.join(",")
  end
end

EventMachine.run do
  if cancel
    jobs = File.read(job_file).decode_irle

    Maru::Producer.connect(host, port, client_name, client_key, [:cancel] + jobs) do |producer|
      producer.callback do |errors|
        errors.each do |error|
          warn "Warning: #{error["id"]} cancel failed (#{error["name"]}: #{error["message"]})"
        end
        exit
      end.errback do |message|
        abort "Failed: #{message}"
      end
    end
  else
    Maru::Producer.connect(host, port, client_name, client_key, [:submit, [job] * repeat]) do |producer|
      producer.callback do |errors, jobs|
        errors.each do |error|
          warn "Warning: job submission failed (#{error["name"]}: #{error["message"]}): #{error["job"].to_json}"
        end

        if job_file
          File.open(job_file, "w") do |f|
            f.puts jobs.encode_irle
          end
        end

        exit
      end.errback do |message|
        abort "Failed: #{message}"
      end
    end
  end
end
