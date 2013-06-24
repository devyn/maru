class Task < Sequel::Model
  one_to_many :jobs

  def self.data_dir=(data_dir)
    @@data_dir = data_dir
  end

  def save_result(filename, result)
    path = File.join(@@data_dir, self.id.to_s, filename)

    if File.exists? path
      return false
    else
      FileUtils.mkdir_p(File.dirname(path))

      if result.is_a? Hash
        FileUtils.cp(result[:tempfile].path, path)
        result[:tempfile].close
      else
        File.open(path, "w") do |f|
          f << result.to_s
        end
      end

      return true
    end
  end
end
