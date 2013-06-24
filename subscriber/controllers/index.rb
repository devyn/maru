get '/' do
  @tasks = Task.all

  erb :index
end
