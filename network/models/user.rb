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

  def self.create(username, password, admin=false)
    if redis.exists(redis_key("user:#{username}"))
      raise "user already exists"
    else
      user = new(username)
      user.password = password
      user.is_admin = admin
      return user
    end
  end

  def self.all
    redis.keys(redis_key("user:*")).map do |u|
      new u.match(/user:(.*)$/)[1]
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
    clients_key = redis_key("user(clients):#@name")

    if block_given?
      client_names = yield clients_key
    else
      client_names = redis.smembers(clients_key)
    end

    if client_names.empty?
      []
    else
      client_names.zip(redis.hmget(redis_key("clients"), client_names)).map { |(client_name, client_json)|
        client_json ? Client.new(client_name, client_json) : nil
      }.reject(&:nil?)
    end
  end

  def active_clients
    clients { |key|
      redis.sinter(key, redis_key("active_clients"))
    }
  end

  def clients_count
    redis.scard(redis_key("user(clients):#@name"))
  end

  def owns_client?(client_name)
    redis.sismember(redis_key("user(clients):#@name"), client_name)
  end

  def delete
    redis.multi { nonatomic_delete }
  end

  def nonatomic_delete
    # delete our clients first
    clients.each &:nonatomic_delete

    # delete our own data
    redis.del(redis_key("user(clients):#@name"))
    redis.del(user_data_key)

    # notify server via pubsub
    redis.publish(redis_key("users"), "deleted:#@name")
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
