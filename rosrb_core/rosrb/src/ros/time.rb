module ROS
  class TemporalValue
    private

    def self.canon(secs, nsecs)
      while nsecs >= 1000000000
        secs += 1
        nsecs -= 1000000000
      end
      while nsecs < 0
        secs -= 1
        nsecs += 1000000000
      end
      return secs, nsecs
    end

    public

    def initialize(_secs, _nsecs)
      @secs = _secs 
      @nsecs = _nsecs
    end

    attr_accessor :secs, :nsecs

    def zero?
      @secs == 0 and @nsecs == 0
    end

    def set!(_secs, _nsecs)
      @secs = _secs
      @nsecs = _nsecs
    end

    def canon!
      @secs, @nsecs = canon(@secs, @nsecs)
    end

    def to_sec
      @secs + @nsecs / 1e9
    end

    def to_nsec
      (@secs * 1e9).to_i + @nsecs
    end
  end

  class Time < TemporalValue
    def initialize(_secs=0, _nsecs=0)
      super(_secs, _nsecs)
      #if @secs < 0
      #  raise TypeError("")
    end

    def self.from_sec(float_secs)
    end

    def + (other)
      if Duration === other
        ROS::Time.new(self.secs + other.secs, self.nsecs + other.nsecs)
      else
        raise NotImplementedError
      end
    end

    def - (other)
      if ROS::Time === other
        Duration.new(self.secs - other.secs, self.nsecs - other.nsecs)
      elsif Duration === other
        ROS::Time.new(self.secs - other.secs, self.nsecs - other.nsecs)
      else
        raise NotImplementedError
      end
    end

    def <=> (other)
      if not ROS::Time === other
        return nil
      end
      nsec_diff = self.to_nsec() - other.to_nsec()
      if nsec_diff == 0
        return 0
      elsif nsec_diff > 0
        return 1
      else
        return -1
      end
    end

    def < (other)
      cmp = self <=> other
      cmp < 0
    end

    def <= (other)
      cmp = self <=> other
      cmp <= 0
    end

    def > (other)
      cmp = self <=> other
      cmp > 0
    end

    def >= (other)
      cmp = self <=> other
      cmp >= 0
    end

    def == (other)
      cmp = self <=> other
      cmp == 0
    end

    def != (other)
      cmp = self <=> other
      cmp != 0
    end

    def to_s
      "#<ROS::Time secs=#{self.secs} nsecs=#{self.nsecs}>"
    end
  end

  class Duration < TemporalValue

    def initialize(_secs=0, _nsecs=0)
      super(_secs, _nsecs)
    end

    def self.from_sec(float_secs)
      _secs = float_secs.floor
      _nsecs = ((float_secs - _secs) * 1000000000).floor
      Duration.new(_secs, _nsecs)
    end

    def -@
      @secs = -@secs
      @nsecs = -@nsecs
    end

    def + (other)
      if ROS::Time === other
        return  other + self
      elsif Duraiton === other
        return Duration.new(self.secs + other.secs, self.nsecs + other.nsecs)
      else
        raise NotImplementedError
      end
    end

    def - (other)
      if not Duration === other
        raise NotImplementedError
      end
      Duration.new(self.secs - other.secs, self.nsecs - other.nsecs)
    end

    def * (other)
      if Integer === other
        Duration.new(self.secs * other, self.nsecs * other)
      elsif Float === Float
        Duration.from_sec(self.to_sec / other)
      else
        raise NotImplementedError
      end
    end

    def / (other)
      if Integer === other
        Duration.new(self.secs / other, self.nsecs / other)
      elsif Float === other
        Duration.from_sec(self.to_sec / other)
      else
        raise NotImplementedError
      end
    end

    def <=> (other)
      if not Duration === other
        return nil
      end
      nsec_diff = self.to_nsec() - other.to_nsec()
      if nsec_diff == 0
        return 0
      elsif nsec_diff > 0
        return 1
      else
        return -1
      end
    end

    def < (other)
      cmp = self <=> other
      cmp < 0
    end

    def <= (other)
      cmp = self <=> other
      cmp <= 0
    end

    def > (other)
      cmp = self <=> other
      cmp > 0
    end

    def >= (other)
      cmp = self <=> other
      cmp >= 0
    end

    def == (other)
      cmp = self <=> other
      cmp == 0
    end

    def != (other)
      cmp = self <=> other
      cmp != 0
    end

    def to_s
      "#<ROS::Duration secs=#{self.secs} nsecs=#{self.nsecs}>"
    end
  end

  class Rate
    def initialize(node, hz)
      @node = node
      @last_time = ROS.get_rostime()
      @sleep_dur = Duration.new(0, (1e9/hz).floor)
    end

    def sleep
      curr_time = @node.get_rostime()
      if @last_time > curr_time
        @last_time = curr_time
      end
      elapsed = curr_time - @last_time
      if elapsed > @sleep_dur
        @last_time = curr_time
      else
        sleep_time = (@sleep_dur - elapsed).to_sec
        ::Kernel.sleep(sleep_time)
        @last_time = @last_time + @sleep_dur
      end
    end
  end

  def self.get_walltime
    t = ::Time.now
    return ROS::Time.new(t.sec, t.nsec)
  end

  def self.wall_sleep(secs)
    ::Kernel.sleep(secs)
  end
end

