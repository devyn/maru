module Maru
  VERSION = [1, 0, "devel"]

  class << VERSION
    def to_s
      inject("") { |str, part|
        if part.is_a? Integer
          str << (str.empty? ? "" : ".") << part.to_s
        else
          str << (str.empty? ? "" : "-") << part.to_s
        end
      }
    end
  end
end
