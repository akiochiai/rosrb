require 'ros'
require 'test_rosrb/msg'
require 'stringio'

TEST_DIR = File.expand_path(File.dirname(__FILE__))
FLT_EPSILON = 1.192092896e-07

describe ROS::Time, "x" do
  it "b " do
    t = ROS::Time.new
    t.secs.should eq(0)
    t.nsecs.should eq(0)
    u = ROS::Time.new
    t.should eq(ROS::Time.new)
  end
end

describe TestRosrb::Msg::Builtins, "#initialize" do
  it "returns default values without args" do
    builtins = TestRosrb::Msg::Builtins.new
    builtins.b.should be_false
  end
end

describe TestRosrb::Msg::Builtins, "#serialize" do
  it "" do
    msg = TestRosrb::Msg::Builtins.new
    msg.b = true
    msg.c = 0x01
    msg.i8 = 0x01
    msg.u8 = 0x10
    msg.i16 = 0x0123
    msg.u16 = 0x3210
    msg.i32 = 0x01234567
    msg.u32 = 0x76543210
    msg.i64 = 0x0123456789ABCDEF
    msg.u64 = 0xFEDCBA9876543210
    msg.f32 = 3.14
    msg.f64 = 2.78
    msg.str = "Hello, world!"
    msg.t.secs = 12
    msg.t.nsecs = 34
    msg.d.secs = 56
    msg.d.nsecs = 78
    sio = StringIO.new('wb')
    msg.serialize(sio)
    sio.close
    output = sio.string

    file = open(TEST_DIR + "/Builtins.data", 'rb')
    begin
      data = file.read()
    ensure
      file.close
    end
    
    output.bytes.to_a.should =~ data.bytes.to_a
  end
end

describe TestRosrb::Msg::Builtins, "#deserialize" do
  it "should correctly deserialize from binary" do
    file = open(TEST_DIR + "/Builtins.data", 'rb')
    begin
      data = file.read()
    ensure
      file.close
    end
    y = TestRosrb::Msg::Builtins.new
    y.deserialize(data)
    y.b.should be_true
    y.c.should eq(0x01)
    y.i8.should eq(0x01)
    y.u8.should eq(0x10)
    y.i16.should eq(0x0123)
    y.u16.should eq(0x3210)
    y.i32.should eq(0x01234567)
    y.u32.should eq(0x76543210)
    y.i64.should eq(0x0123456789ABCDEF)
    y.u64.should eq(0xFEDCBA9876543210)
    y.f32.should be_within(FLT_EPSILON).of(3.14)
    y.f64.should be_within(Float::EPSILON).of(2.78)
    y.str.should eq("Hello, world!")
    y.t.should eq(ROS::Time.new(12, 34))
    y.d.should eq(ROS::Duration.new(56, 78))
  end
end

describe TestRosrb::Msg::WithHeader, "#initialize" do
  it "should" do
    msg = TestRosrb::Msg::WithHeader.new

    msg.header.seq.should eq(0)
    msg.header.stamp.secs.should eq(0)
    msg.header.stamp.nsecs.should eq(0)
    msg.i.should eq(0)
    msg.h.seq.should eq(0)
    msg.h.stamp.secs.should eq(0)
    msg.h.stamp.nsecs.should eq(0)
  end
end

describe TestRosrb::Msg::WithHeader, "#serialize" do
  it "should" do
    msg = TestRosrb::Msg::WithHeader.new
    msg.header.seq = 0x01234567
    msg.header.stamp.secs = 0x89ABCDEF
    msg.header.stamp.nsecs = 0x76543210
    msg.header.frame_id = "I'm WithHeader"
    msg.i = 0x01234567
    msg.h.seq = 0x89ABCDEF
    msg.h.stamp.secs = 0x76543210
    msg.h.stamp.nsecs = 0xFEDCBA98

    sio = StringIO.new('wb')
    msg.serialize(sio)
    sio.close
    output = sio.string

    file = open(TEST_DIR + "/WithHeader.data", 'rb')
    begin
      data = file.read()
    ensure
      file.close
    end
    
    output.bytes.to_a.should =~ data.bytes.to_a
  end
end

describe TestRosrb::Msg::WithHeader, "#deserialize" do
  it "should" do
    file = open(TEST_DIR + "/WithHeader.data", 'rb')
    begin
      data = file.read()
    ensure
      file.close
    end
    msg = TestRosrb::Msg::WithHeader.new
    msg.deserialize(data)
    msg.header.seq.should eq(0x01234567)
    msg.header.stamp.secs.should eq(0x89ABCDEF)
    msg.header.stamp.nsecs.should eq(0x76543210)
    msg.i.should eq(0x01234567)
    msg.h.seq.should eq(0x89ABCDEF)
    msg.h.stamp.secs.should eq(0x76543210)
    msg.h.stamp.nsecs.should eq(0xFEDCBA98)
  end
end

describe TestRosrb::Msg::Nest2, "#initialize" do
  it "" do
    msg = TestRosrb::Msg::Nest2.new
    msg.builtin.b.should be_false
    msg.builtin.c.should eq(0)
    msg.builtin.i8.should eq(0)
    msg.builtin.u8.should eq(0)
    msg.builtin.i16.should eq(0)
    msg.builtin.u16.should eq(0)
    msg.builtin.i32.should eq(0)
    msg.builtin.u32.should eq(0)
    msg.builtin.i64.should eq(0)
    msg.builtin.u64.should eq(0)
    msg.builtin.f32.should eq(0.0)
    msg.builtin.f64.should eq(0.0)
    msg.builtin.str.should eq("")
    msg.builtin.t.should eq(ROS::Time.new)
    msg.builtin.d.should eq(ROS::Duration.new)
    msg.nest1.header.seq.should eq(0)
    msg.nest1.header.stamp.secs.should eq(0)
    msg.nest1.header.stamp.nsecs.should eq(0)
    msg.nest1.header.frame_id.should eq("")
    msg.nest1.builtin.b.should be_false
    msg.nest1.builtin.c.should eq(0)
    msg.nest1.builtin.i8.should eq(0)
    msg.nest1.builtin.u8.should eq(0)
    msg.nest1.builtin.i16.should eq(0)
    msg.nest1.builtin.u16.should eq(0)
    msg.nest1.builtin.i32.should eq(0)
    msg.nest1.builtin.u32.should eq(0)
    msg.nest1.builtin.i64.should eq(0)
    msg.nest1.builtin.u64.should eq(0)
    msg.nest1.builtin.f32.should eq(0.0)
    msg.nest1.builtin.f64.should eq(0.0)
    msg.nest1.builtin.str.should eq("")
  end
end

describe TestRosrb::Msg::Nest2, "#serialize" do
  it "" do
    msg = TestRosrb::Msg::Nest2.new
    msg.builtin.b = true
    msg.builtin.c = 0x01
    msg.builtin.i8 = 0x01
    msg.builtin.u8 = 0x10
    msg.builtin.i16 = 0x0123
    msg.builtin.u16 = 0x3210
    msg.builtin.i32 = 0x01234567
    msg.builtin.u32 = 0x76543210
    msg.builtin.i64 = 0x0123456789ABCDEF
    msg.builtin.u64 = 0xFEDCBA9876543210
    msg.builtin.f32 = 3.14
    msg.builtin.f64 = 2.78
    msg.builtin.str = "Hello, world!"
    msg.builtin.t = ROS::Time.new(12, 34)
    msg.builtin.d = ROS::Duration.new(56, 78)
    msg.nest1.header.seq = 0xCAFEBABE
    msg.nest1.header.stamp.secs = 0xDEADBEEF
    msg.nest1.header.stamp.nsecs = 0xFACEFEED
    msg.nest1.header.frame_id = "This is Nest2"
    msg.nest1.builtin.b = true
    msg.nest1.builtin.c = 0x01
    msg.nest1.builtin.i8 = 0x01
    msg.nest1.builtin.u8 = 0x10
    msg.nest1.builtin.i16 = 0x0123
    msg.nest1.builtin.u16 = 0x3210
    msg.nest1.builtin.i32 = 0x01234567
    msg.nest1.builtin.u32 = 0x76543210
    msg.nest1.builtin.i64 = 0x0123456789ABCDEF
    msg.nest1.builtin.u64 = 0xFEDCBA9876543210
    msg.nest1.builtin.f32 = 3.14
    msg.nest1.builtin.f64 = 2.78
    msg.nest1.builtin.str = "Hello, world!"
    msg.nest1.builtin.t = ROS::Time.new(12, 34)
    msg.nest1.builtin.d = ROS::Duration.new(56, 78)

    sio = StringIO.new('w')
    msg.serialize(sio)
    sio.close
    output = sio.string

    file = open(TEST_DIR + "/Nest2.data", 'rb')
    begin
      data = file.read()
    ensure
      file.close
    end
    
    output.bytes.to_a.should =~ data.bytes.to_a
  end
end

describe TestRosrb::Msg::Nest2, "#deserialize" do
  it "" do
    file = open(TEST_DIR + "/Nest2.data", 'rb')
    begin
      data = file.read()
    ensure
      file.close
    end
    msg = TestRosrb::Msg::Nest2.new
    msg.deserialize(data)
    msg.builtin.b.should be_true
    msg.builtin.c.should eq(0x01)
    msg.builtin.i8.should eq(0x01)
    msg.builtin.u8.should eq(0x10)
    msg.builtin.i16.should eq(0x0123)
    msg.builtin.u16.should eq(0x3210)
    msg.builtin.i32.should eq(0x01234567)
    msg.builtin.u32.should eq(0x76543210)
    msg.builtin.i64.should eq(0x0123456789ABCDEF)
    msg.builtin.u64.should eq(0xFEDCBA9876543210)
    msg.builtin.f32.should be_within(FLT_EPSILON).of(3.14)
    msg.builtin.f64.should be_within(Float::EPSILON).of(2.78)
    msg.builtin.str.should eq("Hello, world!")
    msg.builtin.t.should eq(ROS::Time.new(12, 34))
    msg.builtin.d.should eq(ROS::Duration.new(56, 78))
    msg.nest1.header.seq.should eq(0xCAFEBABE)
    msg.nest1.header.stamp.secs.should eq(0xDEADBEEF)
    msg.nest1.header.stamp.nsecs.should eq(0xFACEFEED)
    msg.nest1.header.frame_id.should eq("This is Nest2")
    msg.nest1.builtin.b.should be_true
    msg.nest1.builtin.c.should eq(0x01)
    msg.nest1.builtin.i8.should eq(0x01)
    msg.nest1.builtin.u8.should eq(0x10)
    msg.nest1.builtin.i16.should eq(0x0123)
    msg.nest1.builtin.u16.should eq(0x3210)
    msg.nest1.builtin.i32.should eq(0x01234567)
    msg.nest1.builtin.u32.should eq(0x76543210)
    msg.nest1.builtin.i64.should eq(0x0123456789ABCDEF)
    msg.nest1.builtin.u64.should eq(0xFEDCBA9876543210)
    msg.nest1.builtin.f32.should be_within(FLT_EPSILON).of(3.14)
    msg.nest1.builtin.f64.should be_within(Float::EPSILON).of(2.78)
    msg.nest1.builtin.str.should eq("Hello, world!")
    msg.nest1.builtin.t.should eq(ROS::Time.new(12, 34))
    msg.nest1.builtin.d.should eq(ROS::Duration.new(56, 78))
  end
end

describe TestRosrb::Msg::Arrays, "#initialize" do
  it "" do
    msg = TestRosrb::Msg::Arrays.new
  end
end

describe TestRosrb::Msg::Arrays, "#serialize" do
  it "" do
    sio = StringIO.new('w')
    n = TestRosrb::Msg::Arrays.new
    #n.bs.extend(bool(x % 2) for x in range(10))
    #n.cs.extend(i for i in range(10))
    #n.i8s.extend(i for i in range(10))
    #n.u8s = ''.join(chr(i) for i in range(10))
    #n.i16s.extend(i for i in range(10))
    #n.u16s.extend(i for i in range(10))
    #n.i32s.extend(i for i in range(10))
    #n.u32s.extend(i for i in range(10))
    #n.i64s.extend(i for i in range(10))
    #n.u64s.extend(i for i in range(10))
    #n.f32s.extend(i for i in range(10))
    #n.f64s.extend(i for i in range(10))
    #n.strs.extend("Hello %d" % i for i in range(10))
    #n.ts.extend(rospy.Time(i, i) for i in range(10))
    #n.ds.extend(rospy.Duration(i, i) for i in range(10))
    #n.n2s.extend(make_nest2_sample() for i in range(10))
    n.serialize(sio)
    sio.close
    output = sio.string

    file = open(TEST_DIR + "/Arrays.data", 'rb')
    begin
      data = file.read()
    ensure
      file.close
    end
    
    output.bytes.to_a.should =~ data.bytes.to_a
  end
end

describe TestRosrb::Msg::Arrays, "#deserialize" do
  it "" do
    file = open(TEST_DIR + "/Arrays.data", 'rb')
    begin
      data = file.read()
    ensure
      file.close
    end
  end
end

