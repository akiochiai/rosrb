#
#= rosrb: ROS Client Library implementation for ruby
#
#Authors:: Aki Ochiai
#Version:: 0.1.0
#Copyright:: Copyright (C) Aki Ochiai
#License:: BSD(2 clauses)
#
#= ros.rb
# 
# Easy to use interface for rosrb.
#
if ENV.has_key?('HOME') 
  gen_path = File.join(ENV['HOME'], '.ros', 'rosrb_gen')
  if File.directory?(gen_path) and if not $LOAD_PATH.find(gen_path).nil?
      $LOAD_PATH.unshift(gen_path)
    end
  end
end

require 'ros/package'
require 'ros/node'
require 'ros/name'

#$DEBUG = true

module ROS
  @@default_node = nil

  #
  # @param [String] name node name
  # @param [Hash] options node options
  def self.init_node(name, options={})
    resolver = Resolver.new(name, nil, nil, options[:anonymous])
    @@default_node = Node.new(resolver, options)
  end

  # start event processing
  def self.spin()
    @@default_node.spin
  end

  # poll 1 time for events
  def self.spin_once()
    @@default_node.spin_once
  end

  # request shutting down this node
  def self.signal_shutdown
    @@default_node.signal_shutdown(reason)
  end

  # register callback invoked before shutdown
  def self.on_shutdown(&block)
    @@default_node.on_shutdown(block)
  end

  # @return [Array<String>] command line arguments without remapping args
  def self.user_args
    @@default_node.user_args
  end

  # @return [Bool] false if a node start shutdown process
  def self.ok?
    @@default_node.ok?
  end

  def self.advertise(topic, msg_type, options={})
    @@default_node.advertise(topic, msg_type, options)
  end

  # 
  # @param [String] topic topic name
  # @param [ROS::Message] msg_type message class object
  # @param [Hash] options 
  # @param [Proc] block message callback
  # @return [ROS::Subscriber] ROS topic subscriber
  def self.subscribe(topic, msg_type, options={}, &block)
    @@default_node.subscribe(topic, msg_type, options, &block)
  end

  def self.advertise_service(service, srv_type, options={}, &block)
    @@default_node.advertise_service(service, srv_type, options, &block)
  end

  def self.service_proxy(service, srv_type, options={})
    @@default_node.service_proxy(service, srv_type, options)
  end

  def self.wait_for_service(service)
    @@default_node.wait_for_service(service)
  end

  def self.get_rostime
    @@default_node.get_rostime
  end

  def self.rate(hz)
    @@default_node.rate(hz)
  end

  def self.get_param(name)
    @@default_node.get_param(name)
  end

  def self.set_param(name, value)
    @@default_node.set_param(name, value)
  end

  def self.has_param?(name)
    @@default_node.has_param?(name)
  end

  def self.delete_param(name)
    @@default_node.delete_param(name)
  end

  def self.search_param(name)
    @@default_node.search_param(name)
  end

  def self.get_param_names
    @@default_node.get_param_names
  end

  def self.get_name
    @@default_node.get_name
  end

  def self.get_namespace
    @@default_node.get_namespace
  end

  def self.get_node_uri
    @@default_node.get_node_uri
  end

  def self.resolve_name(name)
    @@default_node.resolve_name(name)
  end

  def self.debug(msg)
    @@default_node.debug(msg)
  end
  
  def self.info(msg)
    @@default_node.info(msg)
  end

  def self.warn(msg)
    @@default_node.warn(msg)
  end

  def self.error(msg)
    @@default_node.error(msg)
  end

  def self.fatal(msg)
    @@default_node.fatal(msg)
  end
end
