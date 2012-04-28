require 'socket'
module ROS
  def self.get_local_port()
    s = TCPServer.new("")
    port = s.addr[1]
    s.close
    port
  end
end
