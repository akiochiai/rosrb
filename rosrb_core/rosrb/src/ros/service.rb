require 'ros/master'
require 'ros/tcpros'
require 'socket'

module ROS

  #
  #= ROS service server
  #
  # 
  class ServiceManager

    def initialize(node)
      @node = node
      @endpoints = {}
      @port = nil
      @server = nil
      @master_proxy = MasterProxy.new(@node.get_master_uri)
    end

    attr_reader :endpoints, :port

    def start
      @port = ROS.get_local_port()
      EM.next_tick do
        @server = EM.start_server(@node.get_ip, @port, TCPROSServiceInboundConnection,
                                  @node.get_name, self)
        Diag.log("TCPROSServiceServer started.")
      end
    end

    def shutdown
      @endpoints.each { |service, ep| ep.shutdown }
      EM.next_tick do
        EM.stop_server(@server)
        Diag.log("TCPROSServiceServer stopped.")
      end
    end

    def invoke_callbacks
      @endpoints.each_value do |ep|
        ep.invoke_callbacks
      end
    end

    def lookup_endpoint(key)
      @endpoints[key]
    end

    def remove_endpoint(endpoint)
      @endpoints.delete(endpoint.name)
      service_api = "rosrpc://#{@node.get_ip}:#{@port}"
      @master_proxy.unregister_service(@node.get_name, endpoint.name, service_api)
    end

    def create_endpoint(service, srv_type, options, block)
      resolved_service = @node.resolve_name(service)
      if @endpoints.has_key? resolved_service
        service = @endpoints[service]
        # shutdown old service
        service.shutdown
      end
      service = ServiceEndpoint.new(self, service, srv_type, block)
      service_api = "rosrpc://#{@node.get_ip}:#{@port}"
      Diag.log(service_api)
      @master_proxy.register_service(@node.get_name,
                                     resolved_service,
                                     service_api,
                                     @node.get_node_uri)
      @endpoints[resolved_service] = service
      service
    end

    def create_proxy(service, srv_type, options)
      persistent = (options[:persistent] or false)
      resolved_service = @node.resolve_name(service)
      master = MasterProxy.new(@node.get_master_uri)
      service_uri = master.lookup_service(@node.get_name, resolved_service)
      uri = URI(service_uri)
      TCPServiceProxy.new(uri.host, uri.port, @node.get_name,
                          service, srv_type, persistent)
    end
  end


  class ServiceEndpoint
    def initialize(manager, service, srv_type, callback)
      @manager = manager
      @name = service
      @srv_type = srv_type
      @callback = callback
      @callback_queue = []
      @queue_mutex = Mutex.new
      @connections = []
      @valid = true
    end

    attr_reader :name, :srv_type

    def push_request(conn, request)
      @queue_mutex.synchronize do
        @callback_queue.push([conn, @callback, request])
      end
    end

    def remove_connection(conn)
      Diag.log("remove_conection #{conn}`")
      @connections.delete(conn)
    end

    def add_connection(conn)
      Diag.log("add_conection #{conn}`")
      @connections.push(conn)
    end

    def type_match?(type_name, md5sum)
      Diag.log("type_match? #{@srv_type::TYPE}=#{type_name} #{@srv_type::MD5SUM}=#{md5sum}")
      # rospy doesn't send 'type' field.
      (md5sum == '*' or @srv_type::MD5SUM == md5sum)
    end

    def invoke_callbacks
      callbacks = nil
      @queue_mutex.synchronize do
        callbacks = @callback_queue
        @callback_queue = []
      end
      callbacks.each do |item|
        conn, callback, request = item
        Diag.log("invoke_esrvice")
        req = @srv_type::Request.new
        req.deserialize(request)
        Diag.log(req)
        begin
          res = callback.call(req)
          sio = StringIO.new
          res.serialize(sio)
          data = sio.string
          conn.send_data([1, data.bytesize].pack("CV"))
          conn.send_data(data)
        rescue
          error = "message call failed."
          conn.send_data([0, error.bytesize, error].pack("CVa"))
        end
      end
    end

    def shutdown
      return unless @valid
      @connections.each do |conn|
        EM.next_tick do
          conn.close_connection
        end
      end
      @connections = []
      @valid = false
      @manager.remove_endpoint(self)
    end
  end


  # Locks are only exclusive with event thread.
  # Do not share this object in multiple threads.
  class ServiceProxy
    def initialize(service, srv_type, persistent)
      @name = service
      @srv_type = srv_type
      @connection = nil
      @state = :created
      @state_cond = ConditionVariable.new
      @state_mutex = Mutex.new
      @persistent = persistent
      @response = nil
      @completed_cond = ConditionVariable.new
      @completion_mutex = Mutex.new
    end

    attr_reader :name, :srv_type

    # Called from event thread
    def connection_result(state, value)
      @state_mutex.synchronize do
        @value = value
        @state = state
        @state_cond.signal
      end
    end

    def wait_connection
      Diag.log("wait_connection")
      @state_mutex.synchronize do
        while @state == :created
          @state_cond.wait(@state_mutex)
        end
        if @state != :ready
          Diag.log("connection failed!")
          raise ROSServiceCallError.new(@connection)
        end
        Diag.log("success!")
        @connection = @value
        @value = nil
      end
    end

    def vaild?
      @state_mutex.synchronize do
        @state != :closed
      end
    end

    # Blocking service call
    def call(*args)
      Diag.log("call #{args}")
      @state_mutex.synchronize do
        if @state != :ready
          raise ROSServiceCallError.new()
        end
        req = @srv_type::Request.new(*args)
        Diag.log(req)
        sio = StringIO.new
        req.serialize(sio)
        data = sio.string
        @connection.send_data([data.bytesize].pack("V"))
        @connection.send_data(data)
        @state = :wait_response

        while @state == :wait_response
          @state_cond.wait(@state_mutex)
        end
        result = @value
        @value = nil
        Diag.log("@state=#{@state}")
        if @state == :success
          if @persistent
            @state = :ready
          else
            EM.next_tick do
              @connection.close_connection
            end
          end
          res = @srv_type::Response.new
          res.deserialize(result)
          res
        else
          if @persistent
            @state = :ready
          else
            EM.next_tick do
              @connection.close_connection
            end
          end
          raise result
        end
      end
    end

    def [](*args)
      call(*args)
    end

    # Called from event thread
    def call_completed(state, value)
      @state_mutex.synchronize do
        @value = value
        @state = state
        @state_cond.signal
      end
    end

    # Called from event thread
    def connection_closed
      @state_mutex.synchronize do
        if @state == :created or @state == :wait_response
          @value = ROSServiceCallError.new("Connection closed.")
          @state = :closed
          @state_cond.signal
        else
          @state = :closed
        end
      end
    end

    # Close persistent connection
    def close 
      EM.next_tick do
        @connection.close_connection
      end
    end
  end


  class TCPServiceProxy
    private
    BUF_SIZE = 1024
    public

    def initialize(host, port, caller_id, service, srv_type, persistent)
      @host = host
      @port = port
      @caller_id = caller_id
      @name = service
      @srv_type = srv_type
      @persistent = persistent
      @socket = nil

      ObjectSpace.define_finalizer(self) do
        close
      end

      connect_service
    end

    def connect_service
      @socket = TCPSocket.new(@host, @port)
      fields = {}
      fields["callerid"] = @caller_id
      fields["service"] = @name
      fields["md5sum"] = @srv_type::MD5SUM
      fields["type"] = @srv_type::TYPE
      fields["persistent"] = @persistent ? 1 : 0
      num_sent = 0
      data = TCPROSHeader.make_header(fields)
      while num_sent < data.bytesize
        num_sent = @socket.write(data.byteslice(num_sent, data.bytesize))
      end
      Diag.log("header sent.")

      header = TCPROSHeader.new
      buffer = ""
      while not header.done
        Diag.log("1")
        data = @socket.recv(BUF_SIZE)
        Diag.log("received=#{data.bytesize}")
        raise ROSServiceCallError.new("EOF while parsing response header.") if data == 0
        buffer += data
        num_read = header.parse(buffer)
        buffer = buffer.byteslice(num_read, buffer.bytesize - num_read)
        Diag.log("num_read=#{num_read}")
      end
      Diag.log("resposne header received. #{header.fields}")

      if header.fields.has_key? "error"
        raise ROSServiceCallError.new(header.fields["error"])
      elsif not header.fields.has_key? "callerid"
        raise ROSServiceCallError.new("Header response is missing 'callerid'.")
      end
    end

    def call(*args)
      if @persistent
        connect_service unless @socket
      else
        connect_service
      end

      # send request 
      Diag.log("send request")
      req = @srv_type::Request.new(*args)
      sio = StringIO.new
      req.serialize(sio)
      data = sio.string
      Diag.log("data = #{data.bytesize}")
      data = [data.bytesize].pack("V") + data
      num_sent = 0
      while num_sent < data.bytesize
        num_sent = @socket.write(data.byteslice(num_sent, data.bytesize))
      end
      Diag.log("sent = #{num_sent}")

      # receive response 
      Diag.log("receive response")
      req = @srv_type::Request.new(*args)
      data = @socket.read(1)
      raise ROSServiceCallError.new("EOF in response.") unless data
      ok_byte = data.unpack("C")[0] == 1
      data = @socket.read(4)
      raise ROSServiceCallError.new("EOF in response.") unless data
      length = data.unpack("V")[0]
      data = @socket.read(length)
      if ok_byte 
        res = @srv_type::Response.new
        res.deserialize(data)
        res[0]
      else
        raise ROSServiceCallError.new(data)
      end
    ensure
      if not @persistent
        @socket.close 
        @socket = nil
        Diag.log("socket.close")
      end
    end

    def [](*args)
      call(*args)
    end

    def close
      if @socket
        @socket.close 
        @socket = nil
        Diag.log("socket.close")
      end
    end
  end
end
