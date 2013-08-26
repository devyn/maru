get '/' do
  erb :index
end

# The following are customizable overrides of the default
# static files.

# header.png replacements should be in custom_header.png.
# A header image should be 300x96 pixels in dimension
# and must be PNG format.

get '/header.png' do
  content_type "image/png"

  custom_header = File.expand_path("custom_header.png", settings.public_folder)

  if File.exists? custom_header
    send_file custom_header
  else
    send_file File.expand_path("default_header.png", settings.public_folder)
  end
end

# custom.css will be loaded after main.css and may override
# default styles, if it exists.

get '/custom.css' do
  content_type "text/css"

  custom_css = File.expand_path("custom.css", settings.public_folder)

  if File.exists? custom_css
    send_file custom_css
  else
    # If the custom CSS doesn't exist, we should just send a blank file so that the
    # browser may still cache it.
    ""
  end
end
