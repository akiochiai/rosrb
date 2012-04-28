#!/usr/bin/env python
# Software License Agreement (BSD License)
#
# Copyright (c) 2012, Aki Ochiai.
# All rights reserved.
#
# Redistribution and use in source and binary forms, with or without
# modification, are permitted provided that the following conditions
# are met:
#
#  * Redistributions of source code must retain the above copyright
#    notice, this list of conditions and the following disclaimer.
#  * Redistributions in binary form must reproduce the above
#    copyright notice, this list of conditions and the following
#    disclaimer in the documentation and/or other materials provided
#    with the distribution.
#
# THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS
# "AS IS" AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT
# LIMITED TO, THE IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS
# FOR A PARTICULAR PURPOSE ARE DISCLAIMED. IN NO EVENT SHALL THE
# COPYRIGHT OWNER OR CONTRIBUTORS BE LIABLE FOR ANY DIRECT, INDIRECT,
# INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES (INCLUDING,
# BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES;
# LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER
# CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT
# LIABILITY, OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN
# ANY WAY OUT OF THE USE OF THIS SOFTWARE, EVEN IF ADVISED OF THE
# POSSIBILITY OF SUCH DAMAGE.
#

# ROS message source code generation for Ruby
# 
# Converts ROS .msg files in a package into Ruby source code implementations.
#
# This implementation 

import roslib; roslib.load_manifest('rosrb')

import sys
import os
import traceback
import optparse

import roslib.msgs 
import roslib.packages
import roslib.gentools

try:
    import cStringIO as stringio 
except:
    import StringIO as stringio

#-- msg ------------------------------------------------------

def ruby_default_value(type):
    base_type, is_array, array_len = roslib.msgs.parse_type(type)
    if is_array:
        return "[]"
    elif roslib.msgs.is_builtin(base_type):
        if type in ['byte', 'int8', 'int16', 'int32', 'int64',
                    'char', 'uint8', 'uint16', 'uint32', 'uint64']:
            return '0'
        elif type in ['float32', 'float64']:
            return '0.0'
        elif type == 'bool':
            return 'false'
        elif type == 'string':
            return '""'
        elif type == 'time':
            return 'ROS::Time.new(0, 0)'
        elif type == 'duration':
            return 'ROS::Duration.new(0, 0)'
        else:
            raise Exception
    elif roslib.msgs.is_header_type(base_type):
        return "StdMsgs::Msg::Header.new()"
    elif roslib.msgs.is_registered(base_type):
        pkg_msg = base_type.split('/')
        pkg = pkg_msg[0]
        msg = pkg_msg[1]
        return "%s::Msg::%s.new()" % (snake_to_camel(pkg), msg)
    else:
        raise Exception("Unknown type")

def snake_to_camel(snake):
    words = snake.split('_')
    return ''.join([word.capitalize() for word in words])

def write_begins(s):
    s.write("#!/usr/bin/env ruby\n")
    s.write("\n")

def write_common_requires(s, spec):
    s.write("require 'rubygems'\n")
    s.write("require 'ros'\n")
    s.write("\n")

def write_requires(s, spec, written_packages):
    for field in spec.parsed_fields():
        if not field.is_builtin:
            if field.is_header:
                if 'std_msgs' not in written_packages:
                    written_packages.add('std_msgs')
                    s.write("require 'std_msgs/msg'\n")
            else:
                pkg, name = roslib.names.package_resource_name(field.base_type)
                pkg = pkg or spec.package # convert '' to package
                if pkg not in written_packages:
                    written_packages.add(pkg)
                    s.write("require '%s/msg'\n" % pkg)

def write_msg_requires(s, spec):
    write_requires(s, spec, set())
    s.write("\n") 

def write_srv_requires(s, spec):
    written_packages = set()
    write_requires(s, spec.request, written_packages)
    write_requires(s, spec.response, written_packages)
    s.write("\n") 

def write_msg_module_begin(s, package):
    s.write("module %s\n" % snake_to_camel(package))
    s.write("  module Msg\n")

def write_msg_module_end(s, package):
    s.write("  end # Msg\n")
    s.write("end # package\n")

def write_srv_module_begin(s, package):
    s.write("module %s\n" % snake_to_camel(package))
    s.write("  module Srv\n")

def write_srv_module_end(s, package):
    s.write("  end # Srv\n")
    s.write("end # package\n")

def write_class_begin(s, spec):
    s.write("    ")
    s.write("class %s < ROS::Message\n" % spec.short_name)

    gendeps_dict = roslib.gentools.get_dependencies(spec, 
                                                    spec.package,
                                                    compute_files=False)
    md5sum = roslib.gentools.compute_md5(gendeps_dict)
    s.write("      ")
    s.write("MD5SUM = \"%s\"\n" % md5sum)

    s.write("      ")
    s.write("TYPE = \"%s\"\n" % spec.full_name)

    s.write("      ")
    if spec.has_header():
        s.write("HAS_HEADER = true\n")
    else:
        s.write("HAS_HEADER = false\n")

    definition = roslib.gentools.compute_full_text(gendeps_dict)
    s.write("      ")
    s.write("FULL_TEXT = <<-\"EOS\"\n")
    s.write(definition)
    s.write("\n      EOS\n")

    fields = spec.parsed_fields()
    s.write("      ")
    s.write("FIELDS = [%s]\n" % ', '.join([":%s" % field.name for field in fields]))
    s.write("      ")
    s.write("FIELD_TYPES = [%s]\n" % ', '.join(["'%s'" % field.type for field in fields]))

def write_index_accessor(s, spec):
    s.write("      ")
    s.write("def [](key)\n")
    s.write("        m = %s::FIELDS[key]\n" % spec.short_name)
    s.write("        self.__send__(m)")
    s.write("      ")
    s.write("end\n")
    s.write("\n")
    s.write("      ")
    s.write("def []=(key, value)\n")
    s.write("        m = \"#{%s::FIELDS[key]}=\"\n" % spec.short_name)
    s.write("        self.__send__(m)")
    s.write("      ")
    s.write("end\n")
    s.write("\n")


def write_class_end(s, spec):
    s.write("    ")
    s.write("end\n")

def write_constants(s, spec):
    for const in spec.constants:
        s.write("      ")
        s.write("%s = %s\n" % (const.name, const.val))
    s.write("\n")

def write_initialize_method(s, spec):
    s.write("      ")
    s.write("def initialize(*args)\n")
    s.write("        ")
    s.write("kwargs = (::Hash === args.last ? args.pop : {})\n")
    for field in spec.parsed_fields():
        s.write("        ")
        s.write("kwargs[:%s] = args.shift unless args.empty?\n" % field.name)
    for field in spec.parsed_fields():
        s.write("        ")
        s.write("value = kwargs[:%s]\n" % field.name)
        if field.is_array:
            cond = "::Array === value"
        elif field.is_builtin:
            if field.type in ('byte', 'int8', 'int16', 'int32', 'int64',
                              'char', 'uint8', 'uint16', 'uint32', 'uint64'):
                cond = "::Integer === value"
            elif field.type in ('float32', 'float64'):
                cond = "::Float === value"
            elif field.type == 'bool':
                cond = "::TrueClass === value or ::FalseClass === value"
            elif field.type == 'string':
                cond = "::String === value"
            elif field.type == 'time':
                cond = "ROS::Time === value"
            elif field.type == 'duration':
                cond = "ROS::Duration === value"
            else:
                raise Exception("%s is not builtin type!" % field.type)
        elif field.is_header:
            cond = "StdMsgs::Msg::Header === value"
        elif roslib.msgs.is_registered(field.type):
            xs = field.type.split('/')
            pkg = xs[0]
            msg = xs[1]
            cond = "%s::Msg::%s === value" % (snake_to_camel(pkg), msg)
        else:
            raise Exception("Unknown type %s" % field.type)
        s.write("        ")
        s.write("@%s = (%s) ? value : %s\n" % (field.name, cond, ruby_default_value(field.type)))
    s.write("      ")
    s.write("end\n")
    s.write("\n")

def write_accessor(s, spec):
    for name in spec.names:
        s.write("      ")
        s.write("attr_accessor :%s\n" % name)
    s.write("\n")

def write_serialize_array(s, name, elem_type, depth):
    indent = "  " * depth
    s.write(indent)
    s.write("buffer.write([%s.length].pack('V'))\n" % name)
    s.write(indent)
    s.write("%s.each do |elem|\n" % name)
    base_elem_type, is_array, array_len = roslib.msgs.parse_type(elem_type)
    if is_array:
        write_serialize_array(s, "elem", base_elem_type, depth + 1)
    elif roslib.msgs.is_builtin(elem_type):
        write_serialize_builtin(s, 'elem', elem_type, depth + 1)
    elif roslib.msgs.is_header_type(elem_type):
        write_serialize_header(s, 'elem', elem_type, depth + 1)
    elif roslib.msgs.is_registered(elem_type):
        elem_spec = roslib.msgs.get_registered(elem_type)
        write_serialize_complex(s, 'elem', elem_spec, depth + 1)
    else:
        raise Exception
    s.write(indent)
    s.write("end\n")

def write_serialize_builtin(s, name, type, depth):
    indent = "  " * depth
    if type == 'int8' or type == 'char':
        s.write(indent)
        s.write("buffer.write([%s].pack('c'))\n" % name)
    elif type == 'uint8' or type == 'byte':
        s.write(indent)
        s.write("buffer.write([%s].pack('C'))\n" % name)
    elif type == 'bool':
        s.write(indent)
        s.write("buffer.write([%s ? 1 : 0].pack('C'))\n" % name)
    elif type == 'int16':
        s.write(indent)
        if sys.byteorder == 'little':
            s.write("buffer.write([%s].pack('s'))\n" % name)
        else:
            s.write("buffer.write([%s].pack('s').reverse())\n" % name)
    elif type == 'uint16':
        s.write(indent)
        if sys.byteorder == 'little':
            s.write("buffer.write([%s].pack('S'))\n" % name)
        else:
            s.write("buffer.write([%s].pack('S').reverse())\n" % name)
    elif type == 'int32':
        s.write(indent)
        if sys.byteorder == 'little':
            s.write("buffer.write([%s].pack('i'))\n" % name)
        else:
            s.write("buffer.write([%s].pack('i').reverse())\n" % name)
    elif type == 'uint32':
        s.write(indent)
        if sys.byteorder == 'little':
            s.write("buffer.write([%s].pack('I'))\n" % name)
        else:
            s.write("buffer.write([%s].pack('I').reverse())\n" % name)
    elif type == 'int64':
        s.write(indent)
        if sys.byteorder == 'little':
            s.write("buffer.write([%s].pack('q'))\n" % name)
        else:
            s.write("buffer.write([%s].pack('q').reverse())\n" % name)
    elif type == 'uint64':
        s.write(indent)
        if sys.byteorder == 'little':
            s.write("buffer.write([%s].pack('Q'))\n" % name)
        else:
            s.write("buffer.write([%s].pack('Q').reverse())\n" % name)
    elif type == 'float32':
        s.write(indent)
        s.write("buffer.write([%s].pack('e'))\n" % name)
    elif type == 'float64':
        s.write(indent)
        s.write("buffer.write([%s].pack('E'))\n" % name)
    elif type == 'string':
        s.write(indent)
        s.write("buffer.write([%s.bytesize].pack('V'))\n" % name)
        s.write(indent)
        s.write("buffer.write(%s)\n" % name)
    elif type == 'time' or type == 'duration':
        s.write(indent)
        s.write("buffer.write([%s.secs, %s.nsecs].pack('VV'))\n" % (name, name))
    else:
        raise Exception("%s is not a builtin type!" % type)

def write_serialize_header(s, name, depth):
    indent = "  " * depth
    s.write(indent)
    names = (name, name, name)
    s.write("buffer.write([%s.seq, %s.stamp.secs, %s.stamp.nsecs].pack('VVV'))\n" % names)
    s.write(indent)
    s.write("buffer.write([%s.frame_id.bytesize].pack('V'))\n" % name)
    s.write(indent)
    s.write("buffer.write(%s.frame_id)\n" % name)

def write_serialize_complex(s, name, spec, depth):
    indent = "  " * depth
    for field in spec.parsed_fields():
        if field.is_array:
            write_serialize_array(s, "%s.%s" % (name, field.name), field.base_type, depth)
        elif field.is_builtin:
            write_serialize_builtin(s, "%s.%s" % (name, field.name), field.type, depth)
        elif field.is_header:
            write_serialize_header(s, "%s.%s" % (name, field.name), depth)
        else:
            subspec = roslib.msgs.get_registered(field.type)
            write_serialize_complex(s, "%s.%s" % (name, field.name), subspec, depth)

def write_serialize_method(s, spec):
    s.write("      ")
    s.write("def serialize(buffer)\n")
    write_serialize_complex(s, "self", spec, 4)
#    s.write("    ")    
#    s.write("rescue\n")
#    s.write("      ")    
#    s.write("raise Exception\n");
    s.write("      ")
    s.write("end\n")
    s.write("\n")

def write_deserialize_array(s, name, elem_type, depth):
    indent = "  " * depth
    s.write(indent)
    s.write("length = str.byteslice(head, 4).unpack('V')[0]\n")
    s.write(indent)
    s.write("head += 4\n")
    s.write(indent)
    s.write("%s = ::Array.new(length, nil)\n" % name)
    s.write(indent)
    s.write("for i in 0..length-1\n")
    base_elem_type, is_array, array_len = roslib.msgs.parse_type(elem_type)
    if is_array:
        write_deserialize_array(s, "%s[i]" % name, base_elem_type, depth + 1)
    elif roslib.msgs.is_builtin(elem_type):
        write_deserialize_builtin(s, "%s[i]" % name, elem_type, depth + 1)
    elif roslib.msgs.is_header_type(elem_type):
        s.write(indent + "  ")
        s.write("%s[i] = StdMsgs::Msg::Header.new()\n" % name)
        write_deserialize_header(s, "%s[i]" % name, elem_type, depth + 1)
    elif roslib.msgs.is_registered(elem_type):
        elem_spec = roslib.msgs.get_registered(elem_type)
        s.write(indent + "  ")
        vars = (name, snake_to_camel(elem_spec.package), elem_spec.short_name)
        s.write("%s[i] = %s::Msg::%s.new()\n" % vars)
        write_deserialize_complex(s, "%s[i]" % name, elem_spec, depth + 1)
    else:
        raise Exception
    s.write(indent)
    s.write("end\n")

def write_deserialize_builtin(s, name, type, depth):
    indent = "  " * depth
    if type == 'int8' or type == 'char':
        s.write(indent)
        s.write("%s = str.byteslice(head, 1).unpack('c')[0]\n" % name)
        s.write(indent)
        s.write("head += 1\n")
    elif type == 'uint8' or type == 'byte':
        s.write(indent)
        s.write("%s = str.byteslice(head, 1).unpack('C')[0]\n" % name)
        s.write(indent)
        s.write("head += 1\n")
    elif type == 'bool':
        s.write(indent)
        s.write("%s = str.byteslice(head, 1).unpack('C')[0] != 0\n" % name)
        s.write(indent)
        s.write("head += 1\n")
    elif type == 'int16':
        s.write(indent)
        if sys.byteorder == 'little':
            s.write("%s = str.byteslice(head, 2).unpack('s')[0]\n" % name)
        else:
            s.write("%s = str.byteslice(head, 2).reverse.unpack('s')[0]\n" % name)
        s.write(indent)
        s.write("head += 2\n")
    elif type == 'uint16':
        s.write(indent)
        if sys.byteorder == 'little':
            s.write("%s = str.byteslice(head, 2).unpack('S')[0]\n" % name)
        else:
            s.write("%s = str.byteslice(head, 2).reverse.unpack('S')[0]\n" % name)
        s.write(indent)
        s.write("head += 2\n")
    elif type == 'int32':
        s.write(indent)
        if sys.byteorder == 'little':
            s.write("%s = str.byteslice(head, 4).unpack('i')[0]\n" % name)
        else:
            s.write("%s = str.byteslice(head, 4).reverse.unpack('i')[0]\n" % name)
        s.write(indent)
        s.write("head += 4\n")
    elif type == 'uint32':
        s.write(indent)
        if sys.byteorder == 'little':
            s.write("%s = str.byteslice(head, 4).unpack('I')[0]\n" % name)
        else:
            s.write("%s = str.byteslice(head, 4).reverse.unpack('I')[0]\n" % name)
        s.write(indent)
        s.write("head += 4\n")
    elif type == 'int64':
        s.write(indent)
        if sys.byteorder == 'little':
            s.write("%s = str.byteslice(head, 8).unpack('q')[0]\n" % name)
        else:
            s.write("%s = str.byteslice(head, 8).reverse.unpack('q')[0]\n" % name)
        s.write(indent)
        s.write("head += 8\n")
    elif type == 'uint64':
        s.write(indent)
        if sys.byteorder == 'little':
            s.write("%s = str.byteslice(head, 8).unpack('Q')[0]\n" % name)
        else:
            s.write("%s = str.byteslice(head, 8).reverse.unpack('Q')[0]\n" % name)
        s.write(indent)
        s.write("head += 8\n")
    elif type == 'float32':
        s.write(indent)
        s.write("%s = str.byteslice(head, 4).unpack('e')[0]\n" % name)
        s.write(indent)
        s.write("head += 4\n")
    elif type == 'float64':
        s.write(indent)
        s.write("%s = str.byteslice(head, 8).unpack('E')[0]\n" % name)
        s.write(indent)
        s.write("head += 8\n")
    elif type == 'string':
        s.write(indent)
        s.write("length = str.byteslice(head, 4).unpack('V')[0]\n")
        s.write(indent)
        s.write("head += 4\n")
        s.write(indent)
        s.write("%s = str.byteslice(head, length)\n" % name)
        s.write(indent)
        s.write("head += length\n")
    elif type == 'time' or type == 'duration':
        s.write(indent)
        s.write("%s.secs, %s.nsecs = str.byteslice(head, 8).unpack('VV')\n" % (name, name))
        s.write(indent)
        s.write("head += 8\n")
    else:
        raise Exception

def write_deserialize_header(s, name, depth):
    indent = "  " * depth
    s.write(indent)
    s.write("%(name)s.seq, %(name)s.stamp.secs, %(name)s.stamp.nsecs = str.byteslice(head, 12).unpack('VVV')\n" % {'name': name})
    s.write(indent)
    s.write("head += 12\n")
    s.write(indent)
    s.write("length = str.byteslice(head, 4).unpack('V')[0]\n")
    s.write(indent)
    s.write("head += 4\n")
    s.write(indent)
    s.write("%s.frame_id = str.byteslice(head, length)\n" % name)
    s.write(indent)
    s.write("head += length\n")

def write_deserialize_complex(s, name, spec, depth):
    indent = "  " * depth
    for field in spec.parsed_fields():
        if field.is_array:
            write_deserialize_array(s, "%s.%s" % (name, field.name), field.base_type, depth)
        elif field.is_builtin:
            write_deserialize_builtin(s, "%s.%s" % (name, field.name), field.type, depth)
        elif field.is_header:
            s.write(indent)
            s.write("%(name)s = StdMsgs::Msg::Header.new() if %(name)s == nil\n" % {'name': name + "." + field.name})
            write_deserialize_header(s, "%s.%s" % (name, field.name), depth)
        else:
            subspec = roslib.msgs.get_registered(field.type)
            s.write(indent)
            vars = {'name': name + "." + field.name, 'pkg': snake_to_camel(subspec.package), 'msg': subspec.short_name}
            s.write("%(name)s = %(pkg)s::Msg::%(msg)s.new() if %(name)s == nil\n" % vars)
            write_deserialize_complex(s, "%s.%s" % (name, field.name), subspec, depth)


def write_deserialize_method(s, spec):
    s.write("      ")
    s.write("def deserialize(str)\n")
    s.write("        ")
    s.write("head = 0\n")
    write_deserialize_complex(s, "self", spec, 4)
#    s.write("    ")    
#    s.write("rescue\n")
#    s.write("      ")    
#    s.write("raise Exception\n");
    s.write("      ")
    s.write("end\n")

def write_service_definition(s, spec):
    s.write("    ")
    s.write("class %s < ROS::ServiceDefinition\n" % spec.short_name)
    s.write("      ")
    s.write("TYPE = \"%s\"\n" % spec.full_name)
    gendeps_dict = roslib.gentools.get_dependencies(spec, 
                                                    spec.package,
                                                    compute_files=False)
    md5sum = roslib.gentools.compute_md5(gendeps_dict)
    s.write("      ")
    s.write("MD5SUM = \"%s\"\n" % md5sum)
    s.write("      ")
    s.write("Request = %s\n" % spec.request.short_name)
    s.write("      ")
    s.write("Response = %s\n" % spec.response.short_name)
    s.write("    ")
    s.write("end # class %s\n" % spec.short_name)
    s.write("\n")

def generate_message(msg_path, output_dir):
    pkg_dir, pkg_name = roslib.packages.get_dir_pkg(msg_path)
    msg_name, spec = roslib.msgs.load_from_file(msg_path, pkg_name)

    stream = stringio.StringIO()
    
    write_begins(stream)
    write_common_requires(stream, spec)
    write_msg_requires(stream, spec)

    write_msg_module_begin(stream, spec.package)

    write_class_begin(stream, spec)
    write_constants(stream, spec)
    write_accessor(stream, spec)
    write_index_accessor(stream, spec)
    write_initialize_method(stream, spec)
    write_serialize_method(stream, spec)
    write_deserialize_method(stream, spec)
    write_class_end(stream, spec)

    write_msg_module_end(stream, spec.package)

    if not os.path.exists(output_dir):
        os.makedirs(output_dir)
    f = open('%s/_%s.rb' % (output_dir, spec.short_name), 'w')
    f.write(stream.getvalue() + "\n")
    stream.close()

def genmsg_command(args):
    parser = optparse.OptionParser()
    parser.add_option("--generate-root", action="store_true",
                      dest="generate_root")
    parser.add_option("--output-dir", action="store", type="string", dest="output_dir")
    options, args = parser.parse_args(args)
    if options.generate_root:
        pkg_dir, pkg_name = roslib.packages.get_dir_pkg(args[0])
        if options.output_dir:
            output_dir = '%s/%s' % (options.output_dir, pkg_name)
        else:
            output_dir = '%s/src/%s/' % (pkg_dir, pkg_name)
        if not os.path.exists(output_dir):
            os.makedirs(output_dir)
        stream = open('%s/msg.rb' % output_dir, 'wb')
        try:
            for msg_path in args:
                package_dir, package = roslib.packages.get_dir_pkg(msg_path)
                msg_name, spec = roslib.msgs.load_from_file(msg_path, pkg_name)
                stream.write("require File.expand_path(File.dirname(__FILE__) + '/msg/_%s')\n" % spec.short_name)
        finally:
            stream.close()
    else:
        for arg in args:
            pkg_dir, pkg_name = roslib.packages.get_dir_pkg(arg)
            if options.output_dir:
                output_dir = '%s/%s/msg' % (options.output_dir, pkg_name)
            else:
                output_dir =  '%s/src/%s/msg' % (pkg_dir, pkg_name)
            generate_message(arg, output_dir)

def generate_service(srv_path, output_dir):
    pkg_dir, pkg_name = roslib.packages.get_dir_pkg(srv_path)
    srv_name, spec = roslib.srvs.load_from_file(srv_path, pkg_name)

    stream = stringio.StringIO()
    
    write_begins(stream)
    write_common_requires(stream, spec)
    write_srv_requires(stream, spec)

    write_srv_module_begin(stream, spec.package)

    write_class_begin(stream, spec.request)
    write_constants(stream, spec.request)
    write_accessor(stream, spec.request)
    write_index_accessor(stream, spec.request)
    write_initialize_method(stream, spec.request)
    write_serialize_method(stream, spec.request)
    write_deserialize_method(stream, spec.request)
    write_class_end(stream, spec.request)

    stream.write("\n")

    write_class_begin(stream, spec.response)
    write_constants(stream, spec.response)
    write_accessor(stream, spec.response)
    write_index_accessor(stream, spec.response)
    write_initialize_method(stream, spec.response)
    write_serialize_method(stream, spec.response)
    write_deserialize_method(stream, spec.response)
    write_class_end(stream, spec.response)

    stream.write("\n")

    write_service_definition(stream, spec)

    write_srv_module_end(stream, spec.package)

    if not os.path.exists(output_dir):
        os.makedirs(output_dir)
    f = open('%s/_%s.rb' % (output_dir, spec.short_name), 'wb')
    f.write(stream.getvalue() + "\n")
    stream.close()

def gensrv_command(args):
    parser = optparse.OptionParser()
    parser.add_option("--generate-root", action="store_true",
                      dest="generate_root")
    parser.add_option("--output-dir", action="store", type="string", dest="output_dir")
    options, args = parser.parse_args(args)
    if options.generate_root:
        pkg_dir, pkg_name = roslib.packages.get_dir_pkg(args[0])
        if options.output_dir:
            output_dir = '%s/%s' % (options.output_dir, pkg_name)
        else:
            output_dir = "%s/src/%s" % (pkg_dir, pkg_name)
        if not os.path.exists(pkg_dir):
            os.makedirs(output_dir)
        stream = open('%s/srv.rb' % output_dir, 'wb')
        try:
            for srv_path in args:
                package_dir, package = roslib.packages.get_dir_pkg(srv_path)
                srvg_name, spec = roslib.srvs.load_from_file(srv_path, pkg_name)
                stream.write("require File.expand_path(File.dirname(__FILE__) + '/srv/_%s')\n" % spec.short_name)
        finally:
            stream.close()
    else:
        for arg in args:
            pkg_dir, pkg_name = roslib.packages.get_dir_pkg(arg)
            if options.output_dir:
                output_dir = '%s/%s/srv' % (options.output_dir, pkg_name)
            else:
                output_dir =  '%s/src/%s/srv' % (pkg_dir, pkg_name)
            generate_service(arg, output_dir)

