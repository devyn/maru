require 'rake/testtask'
require 'yard'

task :default => [:spec, :doc]

Rake::TestTask.new do |t|
  t.name = "spec"
  t.pattern = "spec/**/*_spec.rb"
end

YARD::Rake::YardocTask.new do |t|
  t.name = "doc"
end
