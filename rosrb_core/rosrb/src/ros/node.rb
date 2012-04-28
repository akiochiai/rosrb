require 'rubygems'

require 'ros/package'
require 'ros/pubsub'
require 'ros/service'
require 'ros/slave'
require 'ros/master'
require 'ros/msg'
require 'ros/srv'
require 'ros/event_loop'
require 'ros/log'

require 'rosgraph_msgs/msg'

module ROS

  # ROS node instance.
  # rosrb allow multiple node instances in one process.
  class Node
    # @param [Resolver] resolver  name resolver
    # @param [Hash]     options   node options (Anonymous options must be passed to the resolver )
    # @return [Nil]
    def initialize(resolver, options) 
      @resolver = resolver
      if @resolver.master.nil?
        raise ROSError.new("Invalid ROS Master URI.")
      end
      @pid = $$
      @master_proxy = MasterProxy.new(@resolver.master)

      EventLoop.instance.start()

      level = (options[:log_level] or Logger::INFO)
      @logger = Logger.new(@resolver.qualified_node_name, @resolver.log_dir, level)

      @logger.info("Node(#{@resolver.node_name} => #{@resolver.qualified_node_name}) pid=#{@pid} start")
      @logger.info("ROS_MASTER_URI = #{@resolver.master}")

      @topic_manager = TopicManager.new(self)
      @service_manager = ServiceManager.new(self)
      @slave_server = SlaveServer.new(self, @topic_manager, @service_manager)
      @slave_server.start

      @node_uri = URI::HTTP.build(:host => @resolver.ip, :port => @slave_server.port).to_s
      @logger.info("ROS Slave Server start at URI #{@node_uri}")
      @topic_manager.start
      @logger.info("TCPROS PubSub Server start at port #{@topic_manager.port}")
      @service_manager.start
      @logger.info("TCPROS Service Server start at port #{@service_manager.port}")

      @simtime = nil
      @clock_sub = nil
      if @master_proxy.has_param(@resolver.qualified_node_name, "/use_simtime")
        @use_simtime = @master_proxy.get_param(@resolver.qualified_node_name, "/use_simtime")
      else
        @use_simtime = false
      end
      if @use_simtime
        callback = proc { |msg| @simtime = msg.clock }
        @clock_sub = @topic_manager.create_subscriber("/clock", RosgraphMsgs::Msg::Clock, {}, callback)
      end

      # set private paramters
      @resolver.private_params.each do |k, v|
        @master_proxy.set_param(@resolver.qualified_node_name, k, v)
      end

      log_pub = @topic_manager.create_publisher("/rosout", RosgraphMsgs::Msg::Log, {})
      @logger.publisher = log_pub

      @shuttingdown = false
      @mutex = Mutex.new
      @shutdown_hooks = []

      if not EventLoop.instance.register_node(@resolver.qualified_node_name, self)
        raise ROSError.new("Node named #{@resolver.qualified_node_name} is already running!")
      end
    end

    def ok?
      not @shuttingdown
    end

    def spin_once
      @topic_manager.invoke_callbacks
      @service_manager.invoke_callbacks
    end

    def spin
      rate = rate(100)
      while ok?
        spin_once
        rate.sleep
      end
    end

    def on_shutdown(hook)
      @shutdown_hooks << hook
    end

    # Request shutdown
    # This method is callable from other thread.
    def signal_shutdown
      @mutex.synchronize do
        return if @shuttingdown
        @shuttingdown = true
        @shutdown_hooks.each do |hook|
          begin
            hook.call
          rescue => e
            puts e
          end
        end
        @slave_server.shutdown
        @topic_manager.shutdown
        @service_manager.shutdown
      end
    end

    # Get a time in the ROS computation graph.
    # @return [ROS::Time] current time
    # @note Currently only walltime is supported.
    def get_rostime
      if @use_simtime
        @simtime
      else
        ROS.get_walltime()
      end
    end

    def advertise(topic, msg_type, options)
      @topic_manager.create_publisher(topic, msg_type, options)
    end

    def subscribe(topic, msg_type, options, &block)
      @topic_manager.create_subscriber(topic, msg_type, options, block)
    end

    def advertise_service(service, srv_type, options, &block)
      @service_manager.create_endpoint(service, srv_type, options, block)
    end

    def service_proxy(service, srv_type, options)
      @service_manager.create_proxy(service, srv_type, options)
    end

    def wait_for_service(service)
      resolved_service = resolve_name(service)
      @logger.debug("waiting service '#{resolved_service}' ...")
      loop do
        uri = URI(@resolver.master)
        client = XMLRPC::Client.new(uri.host, "/", uri.port)
        code, status, result = client.call("lookupService", @resolver.qualified_node_name,
                                           resolved_service)
        break if code == 1
        sleep(0.1)
      end
      @logger.debug("service '#{resolved_service}' found!")
    end

    def rate(hz)
      Rate.new(self, hz)
    end

    def create_timer(period, options, block)
      Timer.new(period, options, block)
    end

    # Parameter API

    def get_param(key)
      resolved_key = @resolver.resolve_name(key)
      @master_proxy.get_param(@resolver.qualified_node_name, resolved_key)
    end

    def set_param(key, value)
      resolved_key = @resolver.resolve_name(key)
      @master_proxy.set_param(@resolver.qualified_node_name, resolved_key, value)
    end
    
    def has_param?(key)
      resolved_key = @resolver.resolve_name(key)
      @master_proxy.has_param(@resolver.qualified_node_name, resolved_key)
    end

    def delete_param(key)
      resolved_key = @resolver.resolve_name(key)
      @master_proxy.delete_param(@resolver.qualified_node_name, resolved_key)
    end

    def search_param(key)
      if Resolver.relative_name?(key)
        resolved_key = key
      else
        resolved_key = @resolver.resolve_name(key)
      end
      @master_proxy.search_param(@resolver.qualified_node_name, resolved_key)
    end

    def get_param_names
      @master_proxy.get_param_names(@resolver.qualified_node_name)
    end

    def debug(msg)
      @logger.debug(msg)
    end

    def info(msg)
      @logger.info(msg)
    end

    def warn(msg)
      @logger.warn(msg)
    end

    def error(msg)
      @logger.error(msg)
    end

    def fatal(msg)
      @logger.fatal(msg)
    end

    def get_name
      @resolver.qualified_node_name
    end

    def get_namespace
      @resolver.namespace
    end

    def get_node_uri
      @node_uri
    end

    def get_master_uri
      @resolver.master
    end

    def get_ip
      @resolver.ip
    end

    def user_args
      @resolver.user_args
    end

    def resolve_name(name)
      @resolver.resolve_name(name)
    end

    # Only supports wall time
    def sleep(duration)
      secs = duration.to_sec if duration === Duration
      wall_sleep(secs) unless secs < 0
    end

  end
end
