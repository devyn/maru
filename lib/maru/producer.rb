require_relative 'client'

module Maru
  module Producer
    include Maru::Client

    def self.connect(host, port, client_name, client_key, &block)
      EventMachine.connect(host, port, self, "network", "producer", client_name, client_key, &block)
    end

    def submit(job)
      send_command "submit", job
    end

    def cancel(id)
      send_command "cancel", id
    end
  end
end
