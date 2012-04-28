#!/usr/bin/env ruby
require 'ros'
ROS.load_manifest('test_rosrb')

require 'std_msgs/msg'

ROS.init_node("listener", :anonymous => true)

sub = ROS.subscribe("/chatter",StdMsgs::Msg::String) do |msg|
  puts msg.data
end

ROS.spin


