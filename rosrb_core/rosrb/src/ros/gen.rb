require 'digest/md5'
require 'yaml'
require 'ros/exceptions'

module ROS
  class MessageSpec
    @@loaded_messages = {}
    def initialize(pacakge, typename)
      @package = package
      @typename = typename
      @md5sum = nil
      @fields = []
      @consts = []
    end

    attr_accessor :package, :typename, :md5sum, :fields, :consts

    BUILTIN_TYPES = ['bool', 'int8', 'uint8', 'int16', 'uint16',
                     'int32', 'uint32', 'int64', 'uint64',
                     'float32', 'float64', 'string', 'time', 'duration']
    CONST_TYPES = ['bool', 'int8', 'uint8', 'int16', 'uint16',
                     'int32', 'uint32', 'int64', 'uint64',
                     'float32', 'float64', 'string']

    def fullname
      "#{@package}/#{@typename}"
    end

    def self.parse(package, typename, source)
      spec = MessageSpec.new(package, typename)
      @md5sum = Digest::MD5.hexdigest(source)
      source.each_line do |line|
        s = line.strip
        next if s.length == 0 # skip empty line
        next if s[0] == '#'   # skip comment line
        if s =~ /^((?:[a-zA-Z]\w*\/)?[a-zA-Z]\w*(?:\[\d+\])?)\s+([a-zA-Z]\w*)(?:=(.*)$)?/
          field_type = $1
          field_name = $2
          const_value = $3
          if const_value.nil?
            type = MsgType.new(field_type)
            field = Field.new(type, field_name)
            spec.fields.push(field)
          else
            if field_type == 'string'
              value = const_value
            else
              value = YAML.load(const_value)
            end
            const = Const.new(field_type, field_name, value)
            spec.consts.push(const)
          end
        else
          raise ROSMessageSyntaxError.new("Syntax error at '#{s}'")
        end
      end
      @@loaded_messages[spec.fullname] = spec
      spec
    end

    def self.registered?(name)
      @@loaded_messages.has_key?(name)
    end

    def self.get_registered(name)
      @@loaded_messages[name]
    end

    def self.load(filename)
      abs_path = File.asbolute_path(filename)
      typename = File.basename(abs_path, '.msg')
      package = File.basename(File.dirname(File.dirname(abs_path)))
      self.parse(package, typename, File::read(abs_path))
    end

    def self.parse_type(type)
      if type =~ /^(?:([a-zA-Z][a-zA-Z0-9_]*)\/)?([a-zA-Z][a-zA-Z0-9_]*)(\[(\d*)\])?$/
        namespace = $1
        if namespace
          typename = "#{namespace}/#{$2}"
        else
          base_type = $2
          is_array = (not $3.nil?)
          array_length = $4.to_i unless $4.nil?
          [base_type, is_array, array_length]
        end
      else
        raise ROSMessageSyntaxError.new("#{type} is not a valid type name.")
      end
    end
  end

  class MsgType
    def initialize(type_text)
      if type_text =~ /^(?:([a-zA-Z][a-zA-Z0-9_]*)\/)?([a-zA-Z][a-zA-Z0-9_]*)(\[(\d*)\])?$/
        @package = $1
        @base_type = $2
        @is_array = (not $3.nil?)
        if @is_array
          @array_length = $4.to_i unless $4.nil?
          @is_header = false
          @is_builtin = false
        else
          @is_header = (@package.nil? or @package == "std_msgs") and @name == "Header"
          @is_builtin = MessageSpec::BUILTIN_TYPES.any? { |t| t == @base_type }
        end
      else
        raise ROSMessageSyntaxError.new("#{type} is not a valid type name.")
      end
    end

    def package
      @pacakge
    end

    def base_type
      @base_type
    end

    def qualified_base_type
      if @package.nil?
        @base_type
      else
        "#{@package}/#{@base_type}"
      end
    end

    def fullname
      if @is_array
        if @array_length.nil?
          "#{qualified_base_type}[]"
        else
          "#{qualified_base_type}[#{@array_length}]"
        end
      else
        qualified_base_type
      end
    end

    def array?
      @is_array
    end

    def array_length
      @array_length
    end

    def header?
      @is_header
    end

    def builtin?
      @is_builtin
    end

    def registered?
      MessageSpec.registered?(fullname)
    end

    def to_s
      "#<ROS::MsgType #{fullname}>"
    end
  end

  class Field
    def initialize(type, name)
      @type = type
      @name = name
    end

    attr_reader :type, :name

    def to_s
      "#<ROS::Field #{@type} #{@name}>"
    end
  end

  class Const
    def initialize(type, name, value)
      @type = type
      @name = name
      @value = value
    end

    attr_reader :type, :name, :value

    def to_s
      "#<ROS::Const #{@type} #{@name}=#{@value}>"
    end
  end

  class MessageFactory
    # @return [Message] a message class from spec
    def build(spec)
      package = spec.package.split('_').each { |w| w.captialize }.join
      typename = spec.typename.split('_').each { |w| w.captialize }.join
      if Object.const_defined?(package)
        pkg_module = Object.const_get(package)
        if pkg_module.const_defined?(:Msg)
          msg_module = pkg_module.const_get(:Msg)
        else
          msg_module = Module.new
          pkg_module.const_set(:Msg, msg_module)
        end
      else
        pkg_module = Module.new
        Object.const_set(package, pkg_module)
        msg_module = Module.new
        pkg_module.const_set(:Msg, msg_module)
      end

      cls = Class.new(ROS::Message)
      cls.const_set(:MD5SUM, spec.md5sum)
      cls.const_set(:TYPE, spec.fullname)
      cls.const_set(:HAS_HEADER, spec.has_header)
      cls.const_set(:FIELDS, spec.fields.each { |f| f.name })
      cls.const_set(:FIELD_TYPES, spec.fields.each { |f| f.type.fullname })
      cls.const_set(:FULL_TEXT, spec.full_text)

      sio = StringIO.new

      cls.class_eval(def_initialize)

      cls.class_exec do
        def [](key)
          method_name = FIELDS[key]
          self.__send__(method_name)
        end

        def []=(key, value)
          method_name = "#{FIELDS[key]}="
          self.__send__(method_name, value)
        end
      end

      for name in spec.names
        cls.class_exec do
          attr_accessor name
        end
      end

      for const in spec.constants
        const_set(const.name, const.value)
      end

      define_initialize(cls, spec)
      define_serialize(cls, spec)
      define_deserialize(cls, spec)
    end

    private

    def ruby_default_value(type)
      if type.array?
        return "[]"
      elsif type.builtin?
        case type.fullname
        when 'byte', 'char', 'int8', 'uint8', 'int16', 'uint16', 'int32', 'uint32', 'int64', 'uint64'
          return '0'
        when 'float32', 'float64'
          return '0.0'
        when 'bool'
          return 'false'
        when 'string'
          return '""'
        when 'time'
          return '::ROS::Time.new(0, 0)'
        when 'duration'
          return '::ROS::Duration.new(0, 0)'
        else
          raise ROSError.new("")
        end
      elsif type.header?
        return '::StdMsgs::Msg::Header.new()'
      elsif type.registered?
        pkg = field.type.package.split('_').each { |w| w.capitalize }.join
        msg = field.type.base_type.split('_').each { |w| w.capitalize }.join
        return "#{pkg}::Msg::#{msg}.new()"
      else
        raise ROSError.new("")
      end
    end

    def define_initialize(cls)
      io = StringIO.new
      io.write "def initialize(*args)\n"
      io.write "  kwargs = (::Hash === args.last ? args.pop : {})\n"
      for field in spec.fields
        io.write "  kwargs[#{field.name}] = args.shift unless args.empty?\n"
      end
      for field in spec.fields
        io.write "  value = kwargs[#{field.name}]\n"
        if field.type.array?
          cond = "::Array === value"
        elsif field.type.builtin?
          case field.type.fullname
          when "byte", "char", "int8", "uint8", "int16", "uint16", "int32", "uint32", "int64", "uint64"
            cond = "::Integer === value"
          when "float32", "float64"
            const = "::Float == value"
          when "bool"
            cond = "::TrueClass === value or ::FalseClass === value"
          when "string"
            cond = "::String === value"
          when "time"
            cond = "::ROS::Time === value"
          when "duration"
            cond = "::ROS::Duration === value"
          else
            raise ROSError.new("")
          end
        elsif field.type.header?
          cond = "::StdMsgs::Msg::Header === value"
        elsif field.type.registered?
          pkg = field.type.package.split('_').each { |w| w.capitalize }.join
          msg = field.type.base_type.split('_').each { |w| w.capitalize }.join
          cond = "#{pkg}::Msg::#{msg} === value"
        else
          raise ROSError.new("")
        end
        io.write " @#{field.name} = (#{cond}) ? value : #{default_value(field.type)}\n"
      end

      io.write "end\n"
    end

    def define_serialize(cls, spec)
      io = StringIO.new
      write_serialize(io, spec)
      cls.class_eval(io.string)
    end

    def define_deserialize(cls, spec)
      io = StringIO.new
      write_deserialize(io, spec)
      cls.class_eval(io.string)
    end

    def little_endian?
      [1].pack('s')[0] == "\x01"
    end

    def write_serialize(io, spec)
      io.write("def serialize(o)\n")
      write_serialize_complex(io, "self", spec, 1)
      io.write("end\n")
    end

    def write_serialize_complex(io, name, spec, depth)
      for field in spec.parsed_fields
        if field.type.array?
          write_serialize_array(io, "#{name}.#{field.name}", field.type, depth)
        elsif field.type.builtin?
          write_serialize_builtin(io, "#{name}.#{field.name}", field.type, depth)
        elsif field.type.header?
          write_serialize_header(io, "#{name}.#{field.name}", depth)
        else
          subspec = MessageSpec.get_registered(field.type.fullname)
          write_serialize_complex(io, "#{name}.#{field.name}", subspec, depth)
        end
      end
    end

    def write_serialize_builtin(io, name, type, depth)
      indent = "  " * depth
      case type.fullname
      when 'char', 'int8'
        io.write("#{indent}o.write([#{name}].pack('c'))\n")
      when 'byte', 'uint8'
        io.write("#{indent}o.write([#{name}].pack('C'))\n")
      when 'int16'
        if little_endian?
          io.write("#{indent}o.write([#{name}].pack('s'))\n")
        else
          io.write("#{indent}o.write([#{name}].pack('s').reverse())\n")
        end
      when 'uint16'
        io.write("#{indent}o.write([#{name}].pack('v'))\n")
      when 'int32'
        if little_endian?
          io.write("#{indent}o.write([#{name}].pack('i'))\n")
        else
          io.write("#{indent}o.write([#{name}].pack('i').reverse())\n")
        end
      when 'uint32'
        io.write("#{indent}o.write([#{name}].pack('V'))\n")
      when 'int64'
        if little_endian?
          io.write("#{indent}o.write([#{name}].pack('q'))\n")
        else
          io.write("#{indent}o.write([#{name}].pack('q').reverse())\n")
        end
      when 'uint64'
        if little_endian?
          io.write("#{indent}o.write([#{name}].pack('Q'))\n")
        else
          io.write("#{indent}o.write([#{name}].pack('Q').reverse())\n")
        end
      when 'float32'
        io.write("#{indent}o.write([#{name}].pack('e')))\n")
      when 'float64'
        io.write("#{indent}o.write([#{name}].pack('E')))\n")
      when 'string'
        io.write("#{indent}o.write([#{name}.bytesize].pack('V')))\n")
        io.write("#{indent}o.write(#{name})\n")
      when 'time', 'duration'
        io.write("#{indent}o.write([#{name}.secs, #{name}.nescs].pack('VV')))\n")
      else
        raise ROSerializationError.new("Unkown field type #{type}.")
      end
    end

    def write_serialize_array(io, name, type, depth)
      indent = "  " * depth
      io.write "#{indent}o.write([#{name}.length].pack('V'))\n"
      io.write "#{indent}#{name}.each do |elem|\n"
      elem_type = MsgType.new(type.qualified_base_type)
      if elem_type.array?
        write_serialize_array(io, "elem", elem_type, depth + 1)
      elsif elem_type.builtin?
        write_serialize_builtin(io, "elem", elem_type, depth + 1)
      elsif elem_type.header?
        write_serialize_header(io, "elem", depth + 1)
      elsif elem_type.registered?
        elem_spec = MessageSpec.get_registered(elem_type)
        write_serialize_complex(io, "elem", elem_spec, depth + 1)
      else
        raise ROSError.new("")
      end
      io.write "end\n"
    end

    def write_serialize_header(io, name, depth)
      indent = "  " * depth
      io.write "#{indent}o.write([#{name}.seq, #{name}.stamp.secs, #{name}.stamp.nsecs].pack('VVV'))\n"
      io.write "#{indent}o.write([#{name}.frame_id.bytesize].pack('V'))\n"
      io.write "#{indent}o.write([#{name}.frame_id])\n"
    end

    def write_deserialize(io, spec)
      io.write "def deserialize(str)\n"
      write_deserialize_complex(io, "self", spec, 1)
      io.write "end\n"
    end

    def write_deserialize_complex(io, name, spec, depth)
      indent = "  " * depth
      for field in spec.fields
        if field.type.array?
          write_deserialize_array(io, "#{name}.#{field.name}", field.type, depth)
        elsif field.type.builtin?
          write_deserialize_builtin(io, "#{name}.#{field.name}", field.type, depth)
        elsif field.type.header?
          io.write "#{indent}#{name}.#{field.name} = StdMsgs::Msg::Header.new() if #{name}.#{field.name}.nil?\n"
          write_deserialize_header(io, "#{name}.#{field.name}", depth)
        else
          subspec = MessageSpec.get_registered(field.type.fullname)
          target = "#{name}.#{field.name}"
          pkg = field.type.package.split('_').each { |w| w.capitalize }.join
          msg = field.type.base_type.split('_').each { |w| w.capitalize }.join
          io.write "#{indent}#{target} = #{pkg}::Msg::#{msg}.new() if #{target}.nil?\n"
          write_deserialize_complex(io, target, subspec, depth)
        end
      end
    end

    def write_deserialize_array(io, name, type, depth)
      indent = "  " * depth
      io.write "#{indent}length = str.byteslice(head, 4).unpack('V')[0]\n"
      io.write "#{indent}head += 4\n"
      io.write "#{indent}#{name} = ::Array.new(length, nil)\n"
      io.write "#{indent}for i in 0..length-1\n"
      elem_type = MsgType.new(type.qualified_base_type)
      if elem_type.array?
        write_deserialize_array(io, "#{name}[i]", elem_type.fullname, depth + 1)
      elsif elem_type.builtin?
        write_deserialize_builtin(io, "#{name}[i]", elem_type, depth + 1)
      elsif elem_type.header?
        io.write "#{indent}#{name}[i] = StdMsgs::Msg::Header.new()\n"
        write_deserialize_header(io, "#{name}[i]", depth + 1)
      elsif elem_type.registered?
        elem_spec = MessageSpec.get_registered(elem_type.fullname)
        pkg = field.type.package.split('_').each { |w| w.capitalize }.join
        msg = field.type.base_type.split('_').each { |w| w.capitalize }.join
        io.write "#{indent}#{name}[i] = #{pkg}::Msg::#{msg}.new()\n"
        write_deserialize_complex(io, "#{name}[i]", elem_spec, depth + 1)
      else
        raise ROSError.new("")
      end
      io.write "#{indent}end\n"
    end

    def write_deserialize_builting(io, name, type, depth)
      indent = "  " * depth
      case type.fullname
      when 'int8', 'char'
        io.write "#{indent}#{name} = str.byteslice(head, 1).unpack('c')[0]\n"
        io.wirte "#{indent}head += 1"
      when 'uint8', 'byte'
        io.write "#{indent}#{name} = str.byteslice(head, 1).unpack('C')[0]\n"
        io.wirte "#{indent}head += 1"
      when 'bool'
        io.write "#{indent}#{name} = str.byteslice(head, 1).unpack('C')[0] != 0\n"
        io.wirte "#{indent}head += 1"
      when 'int16'
        if little_endian?
          io.write "#{indent}#{name} = str.byteslice(head, 2).unpack('s')[0]\n"
        else
          io.write "#{indent}#{name} = str.byteslice(head, 2).reverse.unpack('s')[0]\n"
        end
        io.wirte "#{indent}head += 2"
      when 'uint16'
        io.write "#{indent}#{name} = str.byteslice(head, 2).unpack('v')[0]\n"
        io.wirte "#{indent}head += 2"
      when 'int32'
        if little_endian?
          io.write "#{indent}#{name} = str.byteslice(head, 4).unpack('i')[0]\n"
        else
          io.write "#{indent}#{name} = str.byteslice(head, 4).reverse.unpack('i')[0]\n"
        end
        io.wirte "#{indent}head += 4"
      when 'uint32'
        io.write "#{indent}#{name} = str.byteslice(head, 4).unpack('V')[0]\n"
        io.wirte "#{indent}head += 4"
      when 'int64'
        if little_endian?
          io.write "#{indent}#{name} = str.byteslice(head, 8).unpack('q')[0]\n"
        else
          io.write "#{indent}#{name} = str.byteslice(head, 8).reverse.unpack('q')[0]\n"
        end
        io.wirte "#{indent}head += 8"
      when 'uint64'
        if little_endian?
          io.write "#{indent}#{name} = str.byteslice(head, 8).unpack('Q')[0]\n"
        else
          io.write "#{indent}#{name} = str.byteslice(head, 8).reverse.unpack('Q')[0]\n"
        end
        io.wirte "#{indent}head += 8"
      when 'float32'
        io.write "#{indent}#{name} = str.byteslice(head, 4).unpack('e')[0]\n"
        io.wirte "#{indent}head += 4"
      when 'float64'
        io.write "#{indent}#{name} = str.byteslice(head, 8).unpack('E')[0]\n"
        io.wirte "#{indent}head += 8"
      when 'string'
        io.write "#{indent}length = str.byteslice(head, 4).unpack('V')[0]\n"
        io.write "#{indent}head += 4\n"
        io.write "#{indent}#{name} = str.byteslice(head, length)\n"
        io.write "#{indent}head += lenght\n"
      when 'time', 'duration'
        io.write "#{indent}#{name}.secs, #{name}.nsecs = str.byteslice(head, 8).unpack('VV')\n"
        io.write "#{indent}head += 8\n"
      else
        raise ROSError.new("")
      end
    end

    def write_deserialize_header(io, name, depth)
      indent = "  " * depth
      io.write "#{indent}#{name}.seq, #{name}.stamp.secs, #{name}.stamp.nsecs = str.byteslice(head, 12).unpack('VVV')\n"
      io.write "#{indent}head += 12\n"
      io.write "#{indent}length = str.byteslice(head, 4).unpack('V')[0]\n"
      io.write "#{indent}head += 4"
      io.write "#{indent}#{name}.frame_id = str.byteslice(head, length)\n"
      io.write "#{indent}head += length\n"
    end
  end

  class ServiceBuilder
    def initialize
    end
  end
end # end module ROS
