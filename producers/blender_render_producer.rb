#!/usr/bin/env ruby

$:.unshift(File.join(File.dirname(__FILE__), "..", "lib"))

require 'optparse'
require 'uri'

require 'maru/producer'

job = {
  type: "org.blender.Render",
  destination: nil,
  description: {
    output: "####.png",
    output_format: "PNG"
  }
}

frames      = nil
destination = nil

host = "localhost"
port = 8490

opts = OptionParser.new

opts.on "-N", "--network HOST[:PORT]", "Network address" do |hostport|
  host, port = hostport.split(":")
  port       = port ? port.to_i : 8490
end

opts.on "-d", "--destination URL", "Job destination URL. $n will be substituted for frame number" do |dest|
  destination = dest
end

opts.on "-b", "--blend-file URL", ".blend file URL" do |blend_file|
  job[:description][:blend_file_url] = blend_file
end

opts.on "--blend-file-sha256 STRING", ".blend file SHA-256 checksum (optional)" do |sha256|
  job[:description][:blend_file_sha256] = sha256
end

opts.on "-f", "--frames START[-END]", "Range of frames to render" do |range|
  head, last = range.split("-")

  if head and last
    frames = (head.to_i)..(last.to_i)
  else
    frames = (head.to_i)..(head.to_i)
  end
end

opts.on "-o", "--output ####.ext", "Output file format, where consecutive # symbols are replaced with the zero-padded frame number. Default: ####.png" do |output|
  job[:description][:output] = output
end

opts.on "-F", "--output-format FORMAT", "A valid output format accepted by blender. Default: PNG (recommended)" do |output_format|
  job[:description][:output_format] = output_format
end

opts.on_tail "-h", "--help", "Print this message and exit" do
  puts opts
  exit
end

opts.parse!(ARGV)

# validate

unless destination
  puts opts
  abort "E: job destination not specified"
end

begin
  URI.parse(destination.gsub("$n", "0"))
rescue
  abort "E: job destination invalid"
end

unless job[:description][:blend_file_url]
  puts opts
  abort "E: .blend file not specified"
end

unless frames
  puts opts
  abort "E: no frames specified"
end

producer = Maru::Producer.new(host, port)

frames.each do |frame|
  $stdout << "."
  $stdout.flush

  job[:destination] = destination.gsub("$n", frame.to_s)
  job[:description][:frame] = frame

  producer.submit(job)
end
$stdout.puts
