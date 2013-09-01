get '/' do
  @tasks = Task.all

  haml :index
end
