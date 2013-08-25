#!/usr/bin/env ruby

require 'redis'
require 'yaml'
require 'bcrypt'

config = YAML.load_file("network_manager.yaml")

redis = Redis.new(config["redis"])

key = ->(name) {
  config["redis"]["key_prefix"] + name
}

redis.hmset(key.("user:admin"), ["password", BCrypt::Password.create("admin"), "is_admin", "true"])

puts <<-EOF
Admin account created:

    username: admin
    password: admin

It is recommended that you use this account to create a
new administrator account and delete this one, for security
purposes. At the very least, you should change the password.
EOF
