require 'ros/gen'

describe ROS::MessageSpec, "load" do
  it "b " do
    source = <<-"EOS"
    # commene line
      # comment
    Header header
    char x # comment
    int32 value=324
    string str=#commment is ignored
    std_msgs/String str2
    rosgraph_msgs/Log[100] log
    EOS
    
    spec = ROS::MessageSpec.parse("test", "Test", source)
    puts spec.fields
    header = spec.fields[0]
    header.type.base_type.should == "Header"
    header.type.qualified_base_type.should == "Header"
    header.type.full_name.should == "Header"
    header.type.array_length.should be_nil
    header.type.array?.should be_false
    header.type.builtin?.should be_false
    header.type.header?.should be_true

    value = spec.fields[1]
    log = spec.fields[3]
    log.type.base_type.should == "Log"
    log.type.qualified_base_type.should == "rosgraph_msgs/Log"
    log.type.full_name.should == "rosgraph_msgs/Log[100]"
    log.type.array_length.should == 100
    log.type.array?.should be_true
    log.type.builtin?.should be_false
    log.type.header?.should be_false
    puts spec.consts
  end
end
