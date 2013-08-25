class User
  class << self
    attr_accessor :redis, :key_prefix
  end

  def self.redis_key(string)
    key_prefix.to_s + string
  end

  def self.[](username)
    if redis.exists(redis_key("user:#{username}"))
      new(username)
    else
      nil
    end
  end

  def initialize(username)
    @name = username
  end

  attr_reader :name

  def is_admin
    redis.hget(user_data_key, "is_admin") == "true"
  end

  alias is_admin? is_admin

  def is_admin=(value)
    redis.hset(user_data_key, "is_admin", value ? "true" : "false")
  end

  def password
    if encrypted_password = redis.hget(user_data_key, "password")
      BCrypt::Password.new(encrypted_password)
    else
      nil
    end
  end

  def password=(password)
    encrypted_password = BCrypt::Password.create(password)

    redis.hset(user_data_key, "password", encrypted_password)

    return encrypted_password
  end

  def clients
    client_names = redis.smembers(redis_key("user(clients):#@name"))

    if client_names.empty?
      []
    else
      client_names.zip(redis.hmget(redis_key("clients"), client_names)).map { |(client_name, client_json)|
        client_json ? Client.new(client_name, client_json) : nil
      }.reject(&:nil?)
    end
  end

  def owns_client?(client_name)
    redis.sismember(redis_key("user(clients):#@name"), client_name)
  end

  def user_data_key
    redis_key("user:#@name")
  end

  def redis
    self.class.redis
  end

  def key_prefix
    self.class.key_prefix
  end

  def redis_key(string)
    self.class.redis_key(string)
  end
end
