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

opts.on_tail "-h", "--help", "Print this message and exit" do
  puts opts
  exit
end

opts.parse!(ARGV)

EventMachine.run do
  Maru::Producer.connect(host, port, client_name, client_key, [job] * repeat) do |producer|
    producer.callback do |errors|
      errors.each do |error|
        warn "Warning: job submission failed (#{error["name"]}: #{error["message"]}): #{error["job"].to_json}"
      end
      exit
    end.errback do |message|
      abort "Failed: #{message}"
    end
  end
end
