# vim:et:ts=2:sw=2

source 'https://rubygems.org'

gem 'eventmachine', '~> 1.0.0'

group :master do
  gem 'redis', '~> 3.0.1'
end

group :worker do
end

group :network do
  gem 'redis', '~> 3.0.1'
end

group :manager do
  gem 'redis', '~> 3.0.1'
  gem 'thin', '~> 1.4.1'
  gem 'sinatra', '~> 1.3.3'
end

group :test do
  gem 'minitest', '~> 3.4.0'
end
