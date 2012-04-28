require 'ros/name'

describe ROS::Resolver, "initialize" do
  it "should select ROS args from all arguments" do
    args = ['foo:=bar', '/foo:=bar', '~foo:=/bar', '_foo:=1', 'foo',
            '__name:=my_node', '__log:=my_log', '__ip:=my_ip', '__hostname:=my_hostname',
            '__master:=my_master', '__ns:=my_ns']
    resolver = ROS::Resolver.new("test_node", nil, args)
    resolver.special_keys
    resolver.node_name.should eq("my_node")
    resolver.remappings.should == {"foo" => "bar", "/foo" => "bar", "~foo" => "/bar"}
    resolver.private_params.should == {"foo" => 1}
    resolver.special_keys.should == { "name" => "my_node", "log" => "my_log",
                                      "ip" => "my_ip", "hostname" => "my_hostname",
                                      "master" => "my_master", "ns" => "my_ns" }
    resolver.user_args.should == ['foo']
  end
end

describe ROS::Resolver, "resolve_name" do
  it "should resolve relative name" do
    args = []
    resolver = ROS::Resolver.new("node1", nil, args)
    resolver.namespace.should == "/"
    resolver.resolve_name("bar").should == "/bar"

    args = ["__ns:=/wg/"]
    resolver = ROS::Resolver.new("node2", nil, args)
    resolver.namespace.should == "/wg/"
    resolver.resolve_name("foo").should == "/wg/foo"

    args = ["__ns:=/wg/"]
    resolver = ROS::Resolver.new("node3", nil, args)
    resolver.namespace.should == "/wg/"
    resolver.resolve_name("foo/bar").should == "/wg/foo/bar"
  end

  it "should resolve global name" do
    args = []
    resolver = ROS::Resolver.new("node1", nil, args)
    resolver.namespace.should == "/"
    resolver.resolve_name("/bar").should == "/bar"

    args = ["__ns:=/wg/"]
    resolver = ROS::Resolver.new("node2", nil, args)
    resolver.namespace.should == "/wg/"
    resolver.resolve_name("/foo").should == "/foo"

    args = ["__ns:=/wg/"]
    resolver = ROS::Resolver.new("node3", nil, args)
    resolver.namespace.should == "/wg/"
    resolver.resolve_name("/foo/bar").should == "/foo/bar"
  end

  it "should resolve private name" do
    args = []
    resolver = ROS::Resolver.new("node1", nil, args)
    resolver.namespace.should == "/"
    resolver.resolve_name("~bar").should == "/node1/bar"

    args = ["__ns:=/wg/"]
    resolver = ROS::Resolver.new("node2", nil, args)
    resolver.namespace.should == "/wg/"
    resolver.resolve_name("~foo").should == "/wg/node2/foo"

    args = ["__ns:=/wg/"]
    resolver = ROS::Resolver.new("node3", nil, args)
    resolver.namespace.should == "/wg/"
    resolver.resolve_name("~foo/bar").should == "/wg/node3/foo/bar"
  end

  it "should resolve name 1" do
    args = ["foo:=bar"]
    resolver = ROS::Resolver.new("test_name", nil, args)
    resolver.namespace.should == "/"
    resolver.resolve_name("foo").should == "/bar"
    resolver.resolve_name("/foo").should == "/bar"
  end

  it "should resolve name 2" do
    args = ["__ns:=/baz", "foo:=bar"]
    resolver = ROS::Resolver.new("test_name", nil, args)
    resolver.namespace.should == "/baz/"
    resolver.resolve_name("foo").should == "/baz/bar"
    resolver.resolve_name("/baz/foo").should == "/baz/bar"
  end

  it "should resolve name 3" do
    args = ["/foo:=bar"]
    resolver = ROS::Resolver.new("test_name", nil, args)
    resolver.namespace.should == "/"
    resolver.resolve_name("foo").should == "/bar"
    resolver.resolve_name("/foo").should == "/bar"
  end

  it "should resolve name 4" do
    args = ["__ns:=/baz", "/foo:=bar"]
    resolver = ROS::Resolver.new("test_name", nil, args)
    resolver.namespace.should == "/baz/"
    resolver.resolve_name("/foo").should == "/baz/bar"
  end

  it "should resolve name 5" do
    args = ["__ns:=/baz", "/foo:=/a/b/c/bar"]
    resolver = ROS::Resolver.new("test_name", nil, args)
    resolver.namespace.should == "/baz/"
    resolver.resolve_name("/foo").should == "/a/b/c/bar"
  end
end

