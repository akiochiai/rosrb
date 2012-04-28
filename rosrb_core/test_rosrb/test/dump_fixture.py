import roslib
roslib.load_manifest("test_rosrb")
import rospy

from test_rosrb.msg import Builtins
from test_rosrb.msg import WithHeader
from test_rosrb.msg import Arrays
from test_rosrb.msg import Nest2

def make_builtin_sample():
    msg = Builtins()
    msg.b = True
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
    return msg


def generate_builtins():
    msg = make_builtin_sample()
    with open('Builtins.data', 'wb') as f:
        msg.serialize(f)

def generate_with_header():
  msg = WithHeader()
  msg.header.seq = 0x01234567
  msg.header.stamp.secs = 0x89ABCDEF
  msg.header.stamp.nsecs = 0x76543210 
  msg.header.frame_id = "I'm WithHeader"
  msg.i = 0x01234567
  msg.h.seq = 0x89ABCDEF
  msg.h.stamp.secs = 0x76543210 
  msg.h.stamp.nsecs = 0xFEDCBA98
  with open('WithHeader.data', 'wb') as f:
      msg.serialize(f)

def make_nest2_sample():
  msg = Nest2()
  msg.builtin = make_builtin_sample()
  msg.nest1.header.seq = 0xCAFEBABE
  msg.nest1.header.stamp.secs = 0xDEADBEEF
  msg.nest1.header.stamp.nsecs = 0xFACEFEED
  msg.nest1.header.frame_id = "This is Nest2"
  msg.nest1.builtin = make_builtin_sample()
  return msg 


def generate_nest():
  msg = make_nest2_sample()
  with open('Nest2.data', 'wb') as f:
    msg.serialize(f)

def generate_arrays():
  msg = Arrays()
  msg.bs.extend(bool(x % 2) for x in range(10))
  #msg.cs = ''.join(chr(i) for i in range(10))
  msg.cs.extend(i for i in range(10))
  msg.i8s.extend(i for i in range(10))
  msg.u8s = ''.join(chr(i) for i in range(10))
  msg.i16s.extend(i for i in range(10))
  msg.u16s.extend(i for i in range(10))
  msg.i32s.extend(i for i in range(10))
  msg.u32s.extend(i for i in range(10))
  msg.i64s.extend(i for i in range(10))
  msg.u64s.extend(i for i in range(10))
  msg.f32s.extend(i for i in range(10))
  msg.f64s.extend(i for i in range(10))
  msg.strs.extend("Hello %d" % i for i in range(10))
  msg.ts.extend(rospy.Time(i, i) for i in range(10))
  msg.ds.extend(rospy.Duration(i, i) for i in range(10))
  msg.n2s.extend(make_nest2_sample() for i in range(10))
  
  with open('Arrays.data', 'wb') as f:
    msg.serialize(f)


if __name__ == '__main__':
  generate_builtins()
  generate_with_header()
  generate_arrays()
  generate_nest()



