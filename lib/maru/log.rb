module Maru
  class Log
    def initialize(out, color=nil)
      @out   = out
      @color = color.nil? ? out.tty? : color
    end

    def info(msg, options={})
      if @color
        @out << "\e[34m[#{time}]\e[0;1m>> \e[0;36m#{msg}\e[0m"
      else
        @out << "[#{time}]>> #{msg.gsub(/\e\[\d{1,2}(?:;\d{1,2})?m/, '')}"
      end

      if options[:newline] == false
        @out.flush
      else
        @out << "\n"
      end
    end

    def warn(msg, options={})
      if @color
        @out << "\e[34m[#{time}]\e[0;1m!! \e[0;33m#{msg}\e[0m"
      else
        @out << "[#{time}]!! #{msg.gsub(/\e\[\d{1,2}(?:;\d{1,2})?m/, '')}"
      end

      if options[:newline] == false
        @out.flush
      else
        @out << "\n"
      end
    end

    def time
      Time.now.utc.strftime("%Y-%m-%dT%H:%M:%SZ")
    end
  end
end
