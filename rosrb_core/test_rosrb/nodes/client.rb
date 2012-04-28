#!/usr/bin/env ruby
require 'ros'
ROS.load_manifest('test_rosrb')

require 'test_rosrb/srv'

ROS.init_node("client", :anonymous => true)

ROS.wait_for_service("/add_two_ints")
begin
  add_two_ints = ROS.service_proxy("/add_two_ints", TestRosrb::Srv::AddTwoInts)
  x = ARGV[0].to_i
  y = ARGV[1].to_i
  res = add_two_ints[x, y] # call
  puts "#{x} + #{y} = #{res}"
rescue => e
  puts "Service call failed: #{e}"
end


