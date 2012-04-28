require 'ros'
ROS.load_manifest('test_rosrb')

ROS.init_node("param_sample")

puts ROS.get_param("~foo")
puts ROS.set_param("~pi", 3.14)
puts ROS.has_param?("~pi")
puts ROS.get_param("~pi")
puts ROS.search_param("pi")
ROS.delete_param("~pi")
puts ROS.get_param_names
