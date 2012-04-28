require 'rubygems'
require 'eventmachine'
require 'ros/utils'
require 'ros/master'
require 'ros/tcpros'

module ROS
  # Managing Pub/Sub communication
  class TopicManager

    def initialize(node)
      @node = node
      @master_proxy = MasterProxy.new(@node.get_master_uri)
      @publications = {}
      @subscriptions = {}
      @port = nil
      @server = nil
    end

    attr_reader :port, :publications, :subscriptions

    def invoke_callbacks
      @subscriptions.each_value do |topic|
        topic.invoke_callbacks
      end
    end

    def start
      @port = ROS.get_local_port()
      EM.next_tick do
        @server = EM.start_server(@node.get_ip, @port, TCPROSPubSubInboundConnection,
                                  @node.get_name, self)
        Diag.log("TCPROSPubSubServer started.")
      end
    end

    def shutdown
      @publications.each { |name, topic| topic.shutdown }
      @subscriptions.each { |name, topic| topic.shutdown }
      EM.next_tick do
        EM.stop_server(@server)
        Diag.log("TCPROSPubSubServer stopped.")
      end
    end

    def lookup_publication(name)
      @publications[name]
    end

    def remove_publication(topic)
      @publications.delete(topic.name)
      num_unregistered = @master_proxy.unregister_publisher(@node.get_name,
                                                            topic.name,
                                                            @node.get_node_uri)
    end

    def lookup_subscription(name)
      @publications[name]
    end

    def remove_subscription(topic)
      @subscriptions.delete(topic.name)
      num_unregistered = @master_proxy.unregister_subscriber(@node.get_name,
                                                             topic.name,
                                                             @node.get_node_uri)
    end

    def create_publisher(topic, msg_type, options)
      latching = (options[:latching] or false)
      resolved_topic = @node.resolve_name(topic)
      if @publications.has_key? resolved_topic
        pub = @publications[resolved_topic]
        if pub.type_match? msg_type::TYPE, msg_type::MD5SUM
          return Publisher.new(pub)
        else
          pub.shutdown
        end
      end
      pub = PubTopic.new(self, resolved_topic, msg_type, latching)
      sub_uris = @master_proxy.register_publisher(@node.get_name,
                                                  pub.name,
                                                  msg_type::TYPE,
                                                  @node.get_node_uri)
      @publications[resolved_topic] = pub 
      Publisher.new(pub)
    end

    def create_subscriber(topic, msg_type, options, callback)
      resolved_topic = @node.resolve_name(topic)
      if @subscriptions.has_key? resolved_topic
        sub = @subscriptions[resolved_topic]
        if sub.type_match? msg_type::TYPE, msg_type::MD5SUM
          return Subscriber.new(sub)
        else
          sub.shutdown
        end
      end
      sub = SubTopic.new(self, topic, msg_type, callback)
      publishers = @master_proxy.register_subscriber(@node.get_name,
                                                     sub.name,
                                                     msg_type::TYPE,
                                                     @node.get_node_uri)
      Diag.log(publishers)
      @subscriptions[topic] = sub
      publishers.each { |pub_url| connect_to_publisher(sub, pub_url) }
      Subscriber.new(sub)
    end

    def publisher_update(topic_name, publishers)
      if not @subscriptions.has_key? topic_name
        raise ROSError.new("Unknown topic #{topic_name} update is notified.")
      end
      topic = @subscriptions[topic_name]

      new_pubs = publishers.select do |pub_url|
        Diag.log("pub_url=#{pub_url}")
        ps = topic.connections.select { |conn| conn.peer == pub_url }
        ps.length ==  0
      end
      new_pubs.each do |pub_url|
        connect_to_publisher(topic, pub_url)
      end

      dead_conns = topic.connections.select do |conn| 
        ps = publishers.select { |pub_url| conn.peer == pub_url }
        ps.length == 0
      end
      dead_conns.each do |conn|
        EM.next_tick do 
          conn.close_connection
        end
        topic.connections.delete_if! { |item| item == conn }
      end
    end
    
    private
    
    def connect_to_publisher(topic, pub_url)
      uri = URI(pub_url)
      protocols = []
      protocols.push(["TCPROS"])
      client = XMLRPC::Client.new(uri.host, "/", uri.port)
      Diag.log("Call ROS master API requestTopic(#{@node.get_name}, #{topic.name}, #{protocols})")
      code, status_message, protocol = client.call("requestTopic",
                                                   @node.get_name,
                                                   topic.name,
                                                   protocols)
      Diag.log("requestTopic => #{protocol}")
      if code == 1 and protocol.length > 0 and protocol[0] == "TCPROS"
        proto, host, port = protocol
        EM.next_tick do
          Diag.log("Connecting #{host}:#{port}")
          EM.connect(host, port, TCPROSPubSubOutboundConnection,
                     @node.get_name, topic, pub_url)
        end
      end
    end
  end

  class PubTopic
    def initialize(manager, topic, msg_type, latching)
      @manager = manager
      @name = topic 
      @msg_type = msg_type
      @mutex = Mutex.new
      @connections = []
      @latching = latching
      @latched_msg = nil
      @valid = true
    end

    attr_accessor :name, :type, :msg_type, :latching

    def type_match?(type_name, md5sum)
      type_name == @msg_type::TYPE and md5sum == @msg_type::MD5SUM
    end

    def num_subscribers
      @mutex.synchronize do
        @connections.length
      end
    end

    def add_connection(conn)
      @connections.push(conn)
      if @latching and @latched_msg
        conn.send_data(data)
      end
    end

    def remove_connection(conn)
      @mutex.synchronize do
        @connections.delete(conn)
      end
    end

    def publish(msg)
      @mutex.synchronize do
        raise ROSInvalidTopicError until @valid
        sio = StringIO.new
        msg.serialize(sio)
        data = sio.string
        @connections.each do |conn|
          conn.send_data([data.bytesize].pack("V"))
          conn.send_data(data)
        end
        @latched_msg = data
      end
    end

    def shutdown
      @mutex.synchronize do
        force_shutdown
      end
    end

    private

    def force_shutdown
      return unless @valid
      @connections.each do |conn|
        EM.next_tick { conn.close_connection }
      end
      @connections = []
      @valid = false
      @manager.remove_publication(self)
    end
  end

  # Expose minimum publisher interface to users.
  class Publisher
    def initialize(impl)
      @topic = impl
    end

    def valid?
      @topic.valid?
    end

    def num_subscribers
      @topic.num_subscribers
    end

    def publish(msg)
      @topic.publish(msg)
    end

    def shutdown
      @topic.shutdown
    end
  end

  class SubTopic 
    def initialize(manager, topic, msg_type, callback)
      @manager = manager
      @name = topic
      @msg_type = msg_type
      @mutex = Mutex.new
      @connections = []
      @tcp_nodelay = false
      @valid = true
      @callbacks = [callback]
      @queue_mutex = Mutex.new
      @callback_queue = []
    end

    attr_reader :name, :msg_type, :connections

    def type_match?(type_name, md5sum)
      type_name == @msg_type::TYPE and md5sum == @msg_type::MD5SUM
    end

    def num_publishers
      @mutex.synchronize do
        @connections.length
      end
    end

    def add_connection(conn)
      @mutex.synchronize do
        @connections.push(conn)
      end
    end

    def remove_connection(conn)
      @mutex.synchronize do
        @connections.delete(conn)
      end
    end

    def add_callback(callback)
      @mutex.synchronize do
        @callbacks.push(callback)
      end
    end

    # Called at event thread
    def push_message(data)
      @queue_mutex.synchronize do
        @callbacks.each do |callback|
          @callback_queue.push([callback, data])
        end
      end
    end

    # Called at main thread
    def invoke_callbacks
      callbacks = nil
      @queue_mutex.synchronize do
        callbacks = @callback_queue
        @callback_queue = []
      end
      callbacks.each do |item|
        callback, data = item
        msg = @msg_type.new
        msg.deserialize(data)
        callback.call(msg)
      end
    end

    def shutdown
      @mutex.synchronize do
        force_shutdown
      end
    end

    def valid?
      @mutex.synchronize do
        @valid
      end
    end

    private

    def force_shutdown
      return unless @valid
      @connections.each do |conn|
        EM.next_tick { conn.close_connection }
      end
      @connections = []
      @callbacks = []
      @valid = false
      @manager.remove_subscription(self)
    end
  end

  # Expose minimum subscriber interface to users.
  class Subscriber
    def initialize(impl)
      @topic = impl
    end

    def num_publishers
      @topic.num_publishers
    end

    def shutdown
      @topic.shutdown
    end

    def valid?
      @topic.valid?
    end
  end
end
