helpers do
  def return_error(message)
    flash[:error] = message

    halt redirect(request.referrer)
  end

  def return_success(message)
    flash[:success] = message

    halt redirect(request.referrer)
  end
end
