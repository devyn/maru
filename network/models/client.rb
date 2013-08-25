class Client
  class << self
    attr_accessor :redis, :key_prefix
  end

  def self.redis_key(string)
    key_prefix.to_s + string
  end

  def self.[](client_name)
    if redis.hexists(redis_key("clients"), client_name)
      new(client_name)
    else
      nil
    end
  end

  def initialize(client_name, json_string=nil)
    @name = client_name

    # Things are done twice to avoid object sharing

    if json_string or (json_string = redis.hget(redis_key("clients"), client_name))
      @json     = JSON.parse(json_string)
      @old_json = JSON.parse(json_string)
    else
      @json     = {}
      @old_json = {}
    end
  end

  attr_reader :name

  def key
    @json["key"]
  end

  def key=(value)
    @json["key"] = value
  end

  def permissions
    @json["permissions"]
  end

  def permissions=(value)
    @json["permissions"] = value
  end

  def user
    @json["user"]
  end

  def user=(value)
    if value.is_a? User
      @json["user"] = value.name
    else
      @json["user"] = value
    end
  end

  def save
    unless @old_json == @json
      if !@json["key"]
        # client must have a key so add one
        @json["key"] = "%064x" % rand(2**256)
      end

      new_json = @json.to_json

      redis.multi do
        redis.hset(redis_key("clients"), @name, new_json)

        if @json["user"] != @old_json["user"]
          if @old_json["user"]
            # remove ownership from old owner
            redis.srem(redis_key("user(clients):#{@old_json["user"]}"), @name)
          end

          # assign new ownership
          redis.sadd(redis_key("user(clients):#{@json["user"]}"), @name)
        end
      end

      # avoid object sharing by deep cloning via JSON
      @old_json = JSON.parse(new_json)
    end
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
