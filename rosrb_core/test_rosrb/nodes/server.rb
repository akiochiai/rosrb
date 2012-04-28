#!/usr/bin/env ruby
require 'ros'
ROS.load_manifest('test_rosrb')

require 'test_rosrb/srv'

ROS.init_node("add_two_ints_server", :anonymous => true)

service = ROS.advertise_service("/add_two_ints", TestRosrb::Srv::AddTwoInts) do |req|
  puts "Returning [#{req.a} + #{req.b} = #{req.a + req.b}]"
  TestRosrb::Srv::AddTwoInts::Response.new(req.a + req.b)
end

puts "Ready to add two ints"
ROS.spin

