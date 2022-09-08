require "debug"
require "sqlite3"
require "concurrent"

class ResponseManager
  def self.response_ractor
    Ractor.new(VMManager.current_vms) do |current_vms|
      loop do
        message = Ractor.receive
      end
    end
  end
end
