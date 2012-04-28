# Modified rospy.cmake


rosbuild_find_ros_package(rosrb)

# Message-generation support.
macro(genmsg_rb)
  rosbuild_get_msgs(_msglist)
  set(_inlist "")
  set(_autogen "")
  set(genmsg_rb_exe ${rosrb_PACKAGE_PATH}/scripts/genmsg_rb.py)

  foreach(_msg ${_msglist})
    # Construct the path to the .msg file
    set(_input ${PROJECT_SOURCE_DIR}/msg/${_msg})
    # Append it to a list, which we'll pass back to gensrv below
    list(APPEND _inlist ${_input})
  
    rosbuild_gendeps(${PROJECT_NAME} ${_msg})
  
    set(_output_rb ${PROJECT_SOURCE_DIR}/src/${PROJECT_NAME}/msg/_${_msg})
    string(REPLACE ".msg" ".rb" _output_rb ${_output_rb})
  
    # Add the rule to build the .rb from the .msg.
    add_custom_command(OUTPUT ${_output_rb} 
                       COMMAND ${genmsg_rb_exe} ${_input}
                       DEPENDS ${_input} ${genmsg_rb_exe} ${gendeps_exe} ${${PROJECT_NAME}_${_msg}_GENDEPS} ${ROS_MANIFEST_LIST})
    list(APPEND _autogen ${_output_rb})
  endforeach(_msg)

  if(_autogen)
    # Set up to create the msg.rb file that will import the .rb
    # files created by the above loop.  It can't run until those files are
    # generated, so it depends on them.
    set(_output_rb ${PROJECT_SOURCE_DIR}/src/${PROJECT_NAME}/msg.rb)
    add_custom_command(OUTPUT ${_output_rb}
                       COMMAND ${genmsg_rb_exe} --generate-root ${_inlist}
                       DEPENDS ${_autogen})

    # A target that depends on generation of the msg.rb
    add_custom_target(ROSBUILD_genmsg_rb DEPENDS ${_output_rb})
    # Make our target depend on rosbuild_premsgsrvgen, to allow any
    # pre-msg/srv generation steps to be done first.
    add_dependencies(ROSBUILD_genmsg_rb rosbuild_premsgsrvgen)
    # Add our target to the top-level genmsg target, which will be fired if
    # the user calls genmsg()
    add_dependencies(rospack_genmsg ROSBUILD_genmsg_rb)

    # Also set up to clean the src/<project>/msg directory
    get_directory_property(_old_clean_files ADDITIONAL_MAKE_CLEAN_FILES)
    list(APPEND _old_clean_files ${PROJECT_SOURCE_DIR}/src/${PROJECT_NAME}/msg)
    list(APPEND _old_clean_files ${PROJECT_SOURCE_DIR}/src/${PROJECT_NAME}/msg.rb)
    set_directory_properties(PROPERTIES ADDITIONAL_MAKE_CLEAN_FILES "${_old_clean_files}")
  endif(_autogen)
endmacro(genmsg_rb)

# Call the macro we just defined.
genmsg_rb()

# Service-generation support.
macro(gensrv_rb)
  rosbuild_get_srvs(_srvlist)
  set(_inlist "")
  set(_autogen "")
  set(gensrv_rb_exe ${rosrb_PACKAGE_PATH}/scripts/gensrv_rb.py)

  foreach(_srv ${_srvlist})
    # Construct the path to the .srv file
    set(_input ${PROJECT_SOURCE_DIR}/srv/${_srv})
    # Append it to a list, which we'll pass back to gensrv below
    list(APPEND _inlist ${_input})
  
    rosbuild_gendeps(${PROJECT_NAME} ${_srv})
  

    set(_output_rb ${PROJECT_SOURCE_DIR}/src/${PROJECT_NAME}/srv/_${_srv})
    string(REPLACE ".srv" ".rb" _output_rb ${_output_rb})
  
    # Add the rule to build the .rb from the .srv
    add_custom_command(OUTPUT ${_output_rb} 
                       COMMAND ${gensrv_rb_exe} ${_input}
                       DEPENDS ${_input} ${gensrv_rb_exe} ${gendeps_exe} ${${PROJECT_NAME}_${_srv}_GENDEPS} ${ROS_MANIFEST_LIST})
    list(APPEND _autogen ${_output_rb})
  endforeach(_srv)

  if(_autogen)
    # Set up to create the srv.rb file that will import the .rb
    # files created by the above loop.  It can't run until those files are
    # generated, so it depends on them.
    set(_output_rb ${PROJECT_SOURCE_DIR}/src/${PROJECT_NAME}/srv/srv.rb)
    add_custom_command(OUTPUT ${_output_rb}
                       COMMAND ${gensrv_rb_exe} --generate-root ${_inlist}
                       DEPENDS ${_autogen})
  
    # A target that depends on generation of the srv.rb
    add_custom_target(ROSBUILD_gensrv_rb DEPENDS ${_output_rb})
    # Make our target depend on rosbuild_premsgsrvgen, to allow any
    # pre-msg/srv generation steps to be done first.
    add_dependencies(ROSBUILD_gensrv_rb rosbuild_premsgsrvgen)
    # Add our target to the top-level gensrv target, which will be fired if
    # the user calls gensrv()
    add_dependencies(rospack_gensrv ROSBUILD_gensrv_rb)

    # Also set up to clean the src/<project>/srv directory
    get_directory_property(_old_clean_files ADDITIONAL_MAKE_CLEAN_FILES)
    list(APPEND _old_clean_files ${PROJECT_SOURCE_DIR}/src/${PROJECT_NAME}/srv)
    list(APPEND _old_clean_files ${PROJECT_SOURCE_DIR}/src/${PROJECT_NAME}/srv.rb)
    set_directory_properties(PROPERTIES ADDITIONAL_MAKE_CLEAN_FILES "${_old_clean_files}")
  endif(_autogen)
endmacro(gensrv_rb)

# Call the macro we just defined.
gensrv_rb()

