module Maru
  class Subscriber
    get '/' do
      @tasks = Task.all

      haml :index
    end
  end
end
