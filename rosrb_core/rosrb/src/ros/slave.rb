require 'webrick'
require 'xmlrpc/server'
require 'date'
require 'eventmachine'
require 'socket'

module ROS
  class XMLRPCConnection < EM::Connection
    def initialize(*args)
      @servlet = args.shift
      @buffer = ""
      @state = :header
    end

    class Request
      def initialize(method, path, proto)
        @request_method = method
        @path = path
        @proto = proto
        @header = {}
        @body = nil
      end

      def [](key)
        @header[key.downcase]
      end

      def []=(key, value)
        @header[key.downcase] = value.to_s
      end

      attr_reader :header
      attr_accessor :request_method, :path, :proto, :peeraddr, :body
    end

    HTTP_PROTOCOL = "HTTP/1.0"
    SERVER_NAME = "rosrb/1.0"

    class Response
      def initialize(status, status_message)
        @status = status
        @status_message = status_message
        @header = {}
        @body = nil
        self['content-type'] = 'text/plain'
        self['content-length'] = 0
        self['server'] = "#{SERVER_NAME}"
        self['connection'] = "close"
      end

      def [](key)
        @header[key.downcase]
      end

      def []=(key, value)
        @header[key.downcase] = value.to_s
      end

      def to_data
        data = ""
        data << "#{HTTP_PROTOCOL} #{@status} #{@status_message}" << CRLF
        time = ::Time.now.gmtime.strftime("%a, %d %b %Y %H:%M:%S GMT")
        data << "date: #{time}" << CRLF
        @header.each do |k, v|
          data << "#{k}: #{v}" << CRLF
        end
        data << CRLF
        data << @body unless @body.nil?
        data
      end

      attr_reader :header
      attr_accessor :body, :status, :status_message
    end

    CRLF = "\r\n"

    def receive_data(data)
      @buffer += data
      loop do
        case @state
        when :header
          if @buffer =~ /\r\n\r\n/
            header, rest = @buffer.split("\r\n\r\n", 2)
            fields = header.split("\r\n")
            req_line = fields.shift
            if req_line =~ /^(\S+)\s(\S+)\s(\S+)$/
              method, path, proto = $1, $2, $3
              if method != "POST"
                res = Response.new(400, "Bad Request")
                send_data(res.to_data)
                return
              end
            else
              res = Response.new(400, "Bad Request")
              send_data(res.to_data)
              return
            end
            @request = Request.new(method, path, proto)
            port, ip = Socket.unpack_sockaddr_in(get_peername)
            @request.peeraddr = Socket.getaddrinfo(ip, port)
            for field in fields 
              if field =~ /^([\w-]+):\s*(.*)$/
                @request[$1] = $2.strip
              end
            end
            @content_length = @request.header['content-length'].to_i
            @buffer = rest
            @state = :body
          end
        when :body
          if @buffer.bytesize >= @content_length
            @request.body = @buffer.byteslice(0, @content_length)
            @buffer = @buffer.byteslice(@content_length, 
                                        @buffer.bytesize - @content_length)
            @state = :header

            operation = proc do
              response = Response.new(200, "OK")
              begin
                @servlet.service(@request, response)
                response.to_data
              rescue => e
                response = Response.new(500, "Internal Server Error")
                response.to_data
              end
            end
            callback = proc do |res|
              send_data(res)
              close_connection_after_writing()
            end
            EM.defer(operation, callback)
          end
          return
        end
      end
    end
  end


  # Implement ROS XMLRPC slave API with a dedicated thread
  class SlaveServer
    IGNORED = 0
    def initialize(node, topic_manager, service_manager)
      @node = node
      @topic_manager = topic_manager
      @service_manager = service_manager
      master_uri = @node.get_master_uri
      @client = XMLRPC::Client.new(master_uri, "")
      @port = ROS.get_local_port()

      servlet = XMLRPC::WEBrickServlet.new

      servlet.add_handler("getBusStats") do |caller_id|
        [0, "Not implemented", IGNORED]
      end

      servlet.add_handler("getBusInfo") do |caller_id|
        [0, "Not implemented", IGNORED]
      end

      servlet.add_handler("getMasterUri") do |caller_id|
        [1, "", master_uri]
      end

      servlet.add_handler("shutdown") do |caller_id, msg|
        Node.isntance.shutdown
        [1, "", IGNORED]
      end

      servlet.add_handler("getPid") do |caller_id|
        [1, "", @pid]
      end

      servlet.add_handler("getSubscriptions") do |caller_id|
        result = []
        @topic_manager.subscriptions.each do |pub|
          result.push([pub.name, pub.msg_type::TYPE])
        end
        [1, "", result]
      end

      servlet.add_handler("getPublications") do |caller_id|
        result = []
        @topic_manager.publications.each do |pub|
          result.push([pub.name, pub.msg_type::TYPE])
        end
        [1, "", result]
      end

      servlet.add_handler("paramUpdate") do |caller_id, parameter_key, parameter_value|
        # Not implemented
        [1, "", IGNORED]
      end

      servlet.add_handler("publisherUpdate") do |caller_id, topic, publishers|
        Diag.log("Handle slave API publisherUpdate(#{caller_id}, #{topic}, #{publishers})")
        @topic_manager.publisher_update(topic, publishers)
        [1, "", IGNORED]
      end

      # Currently only support TCPROS
      servlet.add_handler("requestTopic") do |caller_id, topic, protocols|
        Diag.log("Handle slave API requestTopic(#{caller_id}, #{topic}, #{protocols})")
        result = nil
        protocols.each do |protocol|
          protocol_name = protocol.shift
          pub = @topic_manager.lookup_publication(topic)
          if protocol_name == "TCPROS" and pub
            result = [1, "Protocol matched.", ["TCPROS", @node.get_ip, @topic_manager.port]]
            Diag.log("Protocol matched. #{result}")
          end
        end
        if result
          result
        else
          [0, "Requested topic is not found.", IGNORED]
        end
      end

      @servlet = servlet
      # To prevent XMLRPC::Server from install its own signal handler, 
      # We use WEBRick::HTTPServer.
      #@server = WEBrick::HTTPServer.new(:Port => port, :BindAddress => @node.ip)
      #@server.mount("/", servlet)
    end

    attr_reader :port

    #def start
    #  @thread = Thread.new do
    #    #@server.start
    #  end
    #end

    #def shutdown
    #  @server.shutdown
    #  @thread.join
    #  Diag.log("Slave server shutdown complete.")
    #end
    #
    def start
      @port = ROS.get_local_port()
      EM.next_tick do
        @server = EM.start_server(@node.get_ip, @port, XMLRPCConnection, @servlet)
        Diag.log("SlaveServer started at port #{@port}")
      end
    end

    def shutdown
      EM.next_tick do
        EM.stop_server(@server)
        Diag.log("SlaveServer stopped.")
      end
    end
  end
end
