#!/usr/bin/env ruby
require 'ros'
ROS.load_manifest('test_rosrb')

require 'std_msgs/msg'

ROS.init_node("talker", :anonymous => true)

pub = ROS.advertise("/chatter", StdMsgs::Msg::String)

rate = ROS.rate(1)
i = 0
while ROS.ok?
  msg = StdMsgs::Msg::String.new("Hello world #{i}")
  ROS.info("msg=#{msg.data}")
  pub.publish(msg)
  i += 1
  rate.sleep()
end

