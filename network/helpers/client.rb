helpers do
  def client_url(client)
    if @target_user and client.name =~ /^#{Regexp.escape(@target_user.name)}\/([^\/]+)$/
      client_name = $1
      "/user/#{escape @target_user.name}/client/#{escape client_name}"
    else
      "/client/#{escape client.name}"
    end
  end
end
