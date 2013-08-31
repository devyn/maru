get '/' do
  if settings.app_config["private"]
    must_be_logged_in!
  end

  haml :index
end

# header.png replacements should be in custom_header.png.
# A header image should be 300x96 pixels in dimension
# and must be PNG format.

get '/images/header.png' do
  content_type "image/png"

  custom_header = File.expand_path("images/custom_header.png", settings.public_folder)

  if File.exists? custom_header
    send_file custom_header
  else
    send_file File.expand_path("images/default_header.png", settings.public_folder)
  end
end
