module ROS
  class Message
    def initialize(*args)
      # to be overriden
    end


    def serialize(buff)
      # to be overriden
    end

    def deserialize(str)
      # to be overriden
    end

    protected

    def self.little_endian?
       [1].pack("S") == [1].pack("v")
    end
  end

  class Header < Message
    attr_accessor :seq
    attr_accessor :stamp

    def initialize(*args)
      super
      kwargs = Hash === args.last ? args.pop : {}
      kwargs[:seq] = args.shift unless args.empty?
      kwargs[:stamp] = args.shift unless args.empty?
      @seq = Integer === kwargs[:seq] ? kwargs[:seq] : 0
      @stamp = ROS::Time === kwargs[:stamp] ? kwargs[:stamp] : ROS::Time.new
    end

    def serialize(buff)
      buff.write([@seq, @stamp.sec, @stamp.nsec].pack("VVV"))
    end

    def deserialize(str)
      @stamp = ROS::Time.new unless @stamp
      @seq, @stamp.sec, @stamp.nsec = str[0 .. 12].unpack('VVV')
    end

    def to_s
    end
  end
end
