rosrb
============================

Overview
----------------------------

`rosrb` is a [ROS](http://www.ros.org/) client library implementation for [Ruby](http://www.ruby-lang.org/) programming language.

`rosrb` uses [EventMachine](http://rubyeventmachine.com/) as networking infrastructure and utilize its event driven programming functionality.


Features
----------------------------

- Use highly efficient nonblocking socket communication for XMLRPC and TCPROS
- Easy to use module base API (like roscpp/rospy)
- It also support multiple node instances at one process.

Requirements
----------------------------

`rosrb` depends on following software.

- ROS Fuerte Turtle
- Ruby 1.9.3
- EventMachine 0.12.0
- YARD (optional)
- RSpec (optional)

Easy way to install EventMachine, YARD, RSpec is using rubygems. 

     gem install eventmachine yard rspec


Install
----------------------------

1. Install requirements.
2. Checkout rosrb\_core.
3. Add rosrb\_core directory to your `ROS_PACKAGE_PATH`.
3. Put `$(rospack find rosrb)/src` into RUBYLIB environment variable.
4. Generate messages/services required by rosrb runtime.
   Run `ruby $(rospack find rosrb)/scripts/gen_to_home.rb std_msgs rosgraph_msgs`.

Notice
-----------------------------

`rosrb` is under active development and unstable yet.

`rosrb` is tested(not enough!) under following environment:

- Ubuntu 11.10 32bit
- ROS Fuerte Turtle

Message/Service Genration
-----------------------------

We cannot use naming convention for message/service naming conventionin ROS(a package name is used as namespace of generated msg/srv classes), 
as Ruby requires modules must be constant, and constants in Ruby have to start upper case letters.

`rosrb` follows Rails like naming convention. For example if you have a message definition:

    std_msgs/String.msg

`rosrb` message generator translate it into ruby class named:

    StdMsgs::Msg::String

Examples
------------------------------------

### Publisher and Subscriber ###

#### Publisher ####

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

#### Subscriber ####

     #!/usr/bin/env ruby
    require 'ros'
    ROS.load_manifest('test_rosrb')

    require 'std_msgs/msg'

    ROS.init_node("listener", :anonymous => true)

    sub = ROS.subscribe("/chatter",StdMsgs::Msg::String) do |msg|
      puts msg.data
    end

    ROS.spin

### Service and Client ###

### Service ###

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

### Client ###

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


### Parameters ###

    require 'ros'
    ROS.load_manifest('test_rosrb')
    
    ROS.init_node("param_sample")
    
    puts ROS.get_param("~foo")  # Require passing '_foo:=<any value>' to command line
    puts ROS.set_param("~pi", 3.14)
    puts ROS.has_param?("~pi")
    puts ROS.get_param("~pi")
    puts ROS.search_param("pi")
    ROS.delete_param("~pi")
