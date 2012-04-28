require 'ros/utils'

module ROS

  class TCPROSHeader
    def initialize
      @state = :header_length
      @size = nil
      @fields = {}
      @expected_size = 4
      @done = false
      @header_read_size = 0
    end

    attr_reader :size, :fields, :done
    
    def parse(data)
      Diag.log("data.bytesize=#{data.bytesize}")
      num_read = 0
      while data.bytesize >= (num_read + @expected_size) and not @done
        Diag.log("data.bytesize=#{data.bytesize}  (num_read + @expected_size)=#{num_read + @expected_size}")
        case @state
        when :header_length
          @size = data.byteslice(num_read, 4).unpack("V")[0]
          Diag.log("header size = #{@size}")
          num_read += 4
          @expected_size = 4
          @state = :header_field_length
        when :header_field_length
          @expected_size = data.byteslice(num_read, 4).unpack("V")[0]
          Diag.log("field size =#{@expected_size}")
          num_read += 4
          @header_read_size += 4
          @state = :header_field_body
        when :header_field_body
          field = data.byteslice(num_read, @expected_size)
          Diag.log("field.bytesize =#{field.bytesize} field=#{field}")
          name, value = field.split("=")
          @fields[name] = value
          num_read += @expected_size
          @header_read_size += @expected_size
          Diag.log("@header_read_size=#{@header_read_size}")
          if @header_read_size == @size
            @expected_size = 0
            @state = :end
            @done = true
            Diag.log("Header done")
          elsif @header_read_size > @size
            Diag.log("header field error")
            raise TCPROSError.new("?")
          else
            Diag.log("header field done")
            @expected_size = 4
            @state = :header_field_length
          end
        end
      end
      Diag.log("num_read=#{num_read}")
      num_read
    end

    def self.make_header(fields)
      headers = []
      fields.each do |k, v|
        headers << "#{k}=#{v}"
      end 
      Diag.log(headers)
      sum = headers.reduce(0) { |memo, item| memo + item.bytesize + 4 }
      Diag.log(sum)
      data = []
      format = []
      data.push(sum)
      format.push("V")
      headers.each do |item|
        data.push(item.bytesize)
        format.push("V")
        data.push(item)
        format.push("a#{item.bytesize}")
      end
      Diag.log(data)
      Diag.log(format.join)
      output = data.pack(format.join)
      Diag.log(output.bytesize)
      Diag.log(output.unpack(format.join))
      output
    end
  end

  # Base class for all connections
  class TCPROSConnection < EM::Connection
    def initialize(*args)
      super
    end

    def connection_completed
      Diag.log("Connection completed")
    end


    def post_init
      Diag.log("TCPROSConnection#post_init")
      @buffer = ""
      @header = TCPROSHeader.new
      Diag.log("TCPROSConnection#post_init end")
    end

    def receive_data(data)
      Diag.log("receive_data")
      num_read = 0
      @buffer += data 
      if not @header.done
        num_read = @header.parse(@buffer)
        @buffer = @buffer.byteslice(num_read, @buffer.bytesize - num_read)
        if @header.done
          Diag.log("Received header #{@header.fields}")
          on_header(@header)
        end
      else
        num_read = on_body(@buffer)
        @buffer = @buffer.byteslice(num_read, @buffer.bytesize - num_read)
      end
    end

    def unbind
      Diag.log("unbind")
    end

    protected

    def on_header(header)
      0
    end

    def on_body(data)
      0
    end
  end

  # Connection from a remote subscriber to a local publisher
  class TCPROSPubSubInboundConnection < TCPROSConnection
    def initialize(*args)
      super
      @node_id = args.shift
      @topic_manager = args.shift
      @topic = nil
    end

    def on_header(header)
      Diag.log("on header #{header}")
      fields = header.fields
      if fields.has_key? "topic"
        name = fields["topic"]
        topic = @topic_manager.lookup_publication(name)
        if topic.type_match?(fields["type"], fields["md5sum"])
          topic.add_connection(self)
          send_publisher_reply(topic.msg_type::TYPE, topic.msg_type::MD5SUM,
                               @node_id, topic.latching)
          @topic = topic
        else
          reply_fields = {}
          reply_fields["error"] = "type mismatch."
          send_data(TCPROSHeader.make_header(reply_fields))
          close_connection_after_writing
        end
      else
        fields = {}
        fields["error"] = "missing some required fields."
        send_data(TCPROSHeader.make_header(fields))
        close_connection_after_writing
      end
    end

    def on_body(data)
      0
    end

    def unbind
      @topic.remove_connection(self) if @topic
    end

    private

    def send_publisher_reply(type_name, md5sum, callerid=nil, latching=false, msg_def=nil, error=nil)
      fields = {}
      fields["md5sum"] = md5sum
      fields["type"] = type_name
      fields["callerid"] = callerid if callerid
      fields["latching"] = latching if latching
      Diag.log("Send header #{fields}")
      send_data(TCPROSHeader.make_header(fields))
    end
  end

  # Connection from a local subscriber to a remote publisher
  class TCPROSPubSubOutboundConnection < TCPROSConnection
    def initialize(*args)
      super
      @callerid = args.shift
      @topic = args.shift
      @peer = args.shift
      @tcp_nodelay = args.shift
    end

    def post_init
      super
      fields = {}
      fields["callerid"] = @callerid
      fields["topic"] = @topic.name
      fields["md5sum"] = @topic.msg_type::MD5SUM
      fields["type"] = @topic.msg_type::TYPE
      fields["tcp_nodelay"] = 1 if @tcp_nodelay
      Diag.log("Send header #{fields}")
      send_data(TCPROSHeader.make_header(fields))
      Diag.log("header sent")
      @expected_size = 4
      @state = :message_length
      Diag.log("TCPROSPubSubOutboundConnection#post_init done")
    end

    attr_reader :peer

    def on_header(header)
      type = @header.fields["type"]
      md5sum = @header.fields["md5sum"]
      if type and md5sum
        if @topic.type_match?(type, md5sum)
          Diag.log("Type matched. add connection to topic")
          @topic.add_connection(self)
        else
          fields = []
          fields.push("error=type mismatch.")
          send_data(TCPROSHeader.make_header(fields))
          close_connection_after_writing
        end
      else
        fields = []
        fields.push("error=missing some required fields.")
        send_data(TCPROSHeader.make_header(fields))
        close_connection_after_writing
      end
    end

    def on_body(data)
      #Diag.log("on_body data.bytesize=#{data.bytesize} expected_size=#{@expected_size}")
      num_read = 0
      while data.bytesize >= (num_read + @expected_size)
        case @state
        when :message_length
          @expected_size = data.byteslice(num_read, 4).unpack("V")[0]
          num_read += 4
          #Diag.log(num_read)
          @state = :message_body
          Diag.log("message length = #{@expected_size}")
        when :message_body
          #Diag.log("message_body")
          message = data.byteslice(num_read, @expected_size)
          num_read += @expected_size
          #Diag.log(num_read)
          @expected_size = 4
          @state = :message_length
          #Diag.log("received a message")
          @topic.push_message(message)
        end
      end
      #Diag.log("end on_body")
      num_read
    end

    def unbind
      @topic.remove_connection(self)
    end
  end

  # Connection from a remote client to a local endpoint
  class TCPROSServiceInboundConnection < TCPROSConnection
    def initialize(*args)
      super
      @node_id = args.shift
      @service_manager = args.shift
      @resource = nil
      @state = :message_length
      @expected_size = 4
      @endpoint = nil
    end

    def on_header(header)
      fields = header.fields
      Diag.log(fields)
      if fields.has_key?("service")
        name = fields["service"]
        endpoint = @service_manager.lookup_endpoint(name)
        if not endpoint
          fields = {}
          fields["error"] = "service #{name} not found."
          send_data(TCPROSHeader.make_header(fields))
          close_connection_after_writing
        elsif endpoint.type_match?(fields["type"], fields["md5sum"])
          endpoint.add_connection(self)
          send_service_reply(@node_id, fields["type"], fields["md5sum"])
          @endpoint = endpoint
        else
          fields = {}
          fields["error"] = "type mismatch."
          send_data(TCPROSHeader.make_header(fields))
          close_connection_after_writing
        end
      else
        fields = {}
        fields["error"] = "missing some required fields."
        send_data(TCPROSHeader.make_header(fields))
        close_connection_after_writing
      end
    end

    def on_body(data)
      num_read = 0
      while data.bytesize >= (num_read + @expected_size)
        case @state
        when :message_length
          @expected_size = data.byteslice(num_read, 4).unpack("V")[0]
          num_read += 4
          Diag.log(num_read)
          @state = :message_body
          Diag.log("message length = #{@expected_size}")
        when :message_body
          Diag.log("message_body")
          message = data.byteslice(num_read, @expected_size)
          num_read += @expected_size
          Diag.log(num_read)
          @expected_size = 4
          @state = :message_length
          Diag.log("received a message")
          @endpoint.push_request(self, message)
        end
      end
      #Diag.log("end on_body")
      num_read
    end

    def unbind
      @endpoint.remove_connection(self) if @endpoint
    end

    private

    def send_service_reply(callerid, type, md5sum, msg_def=nil, error=nil)
      fields = {}
      fields["callerid"] = callerid
      fields["type"] = type
      fields["md5sum"] = md5sum
      fields["message_definition"] = msg_def if msg_def
      fields["error"] = error if error
      send_data(TCPROSHeader.make_header(fields))
    end
  end

  # Connection from a local service client to a remote endpoint
  class TCPROSServiceOutboundConnection < TCPROSConnection
    def initialize(*args)
      super
      @callerid = args.shift
      @client = args.shift
      @persistent = args.shift
      @state = :ok_byte
      @expected_size = 1
    end

    def post_init
      super
      fields = {}
      fields["callerid"] = @callerid
      fields["service"] = @client.name
      fields["md5sum"] = @client.srv_type::MD5SUM
      fields["type"] = @client.srv_type::TYPE
      fields["persistent"] = 1 if @persistent
      send_data(TCPROSHeader.make_header(fields))
      Diag.log("send header #{fields}")
    end

    def on_header(header)
      Diag.log("on header")
      if header.fields.has_key? 'error'
        @client.connection_result(:failed, header.fields['error'])
        close_connection
      elsif not header.fields.has_key? "callerid"
        @client.connection_result(:failed, "missing 'callerid' field.")
        close_connection
      end
      @client.connection_result(:ready, self)
    end

    def on_body(data)
      Diag.log("TCPROSServiceOutboundConnection#on_body")
      num_read = 0
      while data.bytesize >= (@expected_size + num_read)
        case @state
        when :ok_byte
          ok_byte = data.byteslice(num_read, 1).unpack("C")[0]
          num_read += 1
          @expected_size = 4
          Diag.log("ok_byte=#{ok_byte}")
          if ok_byte == 1
            @state = :message_length
          else
            @state = :error_length
          end
        when :error_length
          Diag.log(":error_body")
          @expected_size = data.byteslice(num_read, 4).unpack("V")[0]
          num_read += 4
          @state = :error_string
        when :error_string
          Diag.log(":error_body")
          error = data.byteslice(num_read, @expected_size)
          num_read += @expected_size
          @expected_size = 1
          @state = :ok_byte
          @client.call_completed(:fail, ROSServiceCallError.new(error))
        when :message_length
          Diag.log(":message_length")
          @expected_size = data.byteslice(num_read, @expected_size).unpack("V")[0]
          num_read += 4
          @state = :message_body
        when :message_body
          Diag.log(":message_body")
          message = data.byteslice(num_read, @expected_size)
          num_read += @expected_size
          @expected_size = 1
          @state = :ok_byte
          @client.call_completed(:success, message)
        end
      end
      num_read
    end

    def unbind
      @client.connection_closed
    end
  end

end
