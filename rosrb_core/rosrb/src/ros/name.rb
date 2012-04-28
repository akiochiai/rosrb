require 'yaml'
require 'socket'
require 'securerandom'

module ROS
  # Managing names with environment variable and remappings.
  # @param [String] node_name non-qualified node name
  # @param [Hash] env environmental variables
  # @param [Array] args command line arguments that contain remmaping 
  class Resolver
    def initialize(node_name, env=nil, args=nil, anonymous=false)
      env ||= ENV
      args ||= ARGV
      @user_args = []
      @remappings = {}
      private_params = {}
      @special_keys = {}
      args.each do |arg|
        if arg =~ /^([a-zA-Z~\/][a-zA-Z0-9_\/]*):=([a-zA-Z~\/][a-zA-Z0-9_\/]*)$/
          @remappings[$1] = $2
        elsif arg =~ /^__(name|log|ip|hostname|master|ns):=([a-zA-Z~\/][a-zA-Z0-9_\/]*)$/
          @special_keys[$1] = $2
        elsif arg =~ /^_([a-zA-Z][a-zA-Z0-9_\/]*):=(.*)$/
          private_params[$1] = YAML.load($2)
        else
          @user_args << arg
        end
      end

      if @special_keys.has_key?('name')
        @node_name = @special_keys['name']
      else
        @node_name = node_name
      end
      if anonymous
        @node_name += "_#{SecureRandom.uuid.gsub(/-/, '_')}"
      end

      if @special_keys.has_key?('ip')
        @ip = @special_keys['ip']
      elsif env.has_key?('ROS_IP')
        @ip = env['ROS_IP']
      else
        @ip = '127.0.0.1'
      end

      if @special_keys.has_key?('log')
        @log_dir = @special_keys['log']
      elsif env.has_key?('ROS_LOG_DIR')
        @log_dir = env['ROS_LOG_DIR']
      elsif env.has_key?('ROS_ROOT') 
        @log_dir = "#{env['ROS_ROOT']}/log"
      else
        @log_dir = "#{env['HOME']}/.ros/log"
      end

      if @special_keys.has_key?('hostname')
        @hostname = @special_keys['hostname']
      elsif env.has_key?('ROS_HOSTNAME')
        @hostname = env['ROS_HOSTNAME']
      else
        @hostname = Socket.gethostname
      end

      if @special_keys.has_key?('master')
        @master = @special_keys['master']
      elsif env.has_key?('ROS_MASTER_URI')
        @master = env['ROS_MASTER_URI']
      else
        @master = nil
      end

      if @special_keys.has_key?('ns')
        @namespace = @special_keys['ns']
      elsif env.has_key?('ROS_NAMESPACE')
        @namespace = env['ROS_NAMESPACE']
      else
        @namespace = '/'
      end
      if not @namespace.end_with?('/')
        @namespace += '/'
      end
      if not @namespace.start_with?('/')
        @namespace = '/' + @namespace
      end

      @private_params = {}
      private_params.each do |k, v|
        name = Resolver.canonicalize_name("#{@namespace}/#{@node_name}/#{k}")
        @private_params[name] = v 
      end
    end

    attr_reader :remappings, :user_args, :private_params, :special_keys

    attr_reader :ip, :hostname, :master, :namespace, :log_dir

    # @return [String] a node name without resolution and remapping
    def node_name
      @node_name 
    end

    # @return [String] fully qualified node name.
    def qualified_node_name
      resolve_name(@node_name)
    end

    # Resolve ROS resource name to fully qualified name.
    # @param [Symbol] valid ROS resouce name
    # @return [String] fully qualified name
    def resolve_name(name)
      name = resolve_name_without_remap(name)
      for k, v in @remappings
        if name.end_with?(k)
          if Resolver.global_name?(v)
            name = v
          else
            if name == k
              name = v
            else
              n = "#{name[0..name.length-k.length-1]}/#{v}"
              name = Resolver.canonicalize_name(n)
            end
          end
          break
        end
      end
      resolve_name_without_remap(name)
    end

    def resolve_name_without_remap(name)
      if Resolver.global_name?(name)
        name = name
      elsif Resolver.private_name?(name)
        name = Resolver.canonicalize_name("#{@namespace}/#{@node_name}/#{name[1..-1]}")
      elsif Resolver.base_name?(name) or Resolver.relative_name?(name)
        name = Resolver.canonicalize_name("#{@namespace}/#{name}")
      else
        raise ROSNameError.new("#{name} is not a valid ROS name.")
      end
    end

    # Remove duplicated slash '/'
    def self.canonicalize_name(name)
      name.gsub(/\/+/, "/")
    end

    def self.base_name?(name)
      name =~ /^[a-zA-Z][a-zA-Z0-9_]*$/
    end

    def self.relative_name?(name)
      name =~ /^[a-zA-Z][a-zA-Z0-9_\/]*$/
    end

    def self.global_name?(name)
      name =~ /^\/[a-zA-Z0-9_\/]*$/
    end

    def self.private_name?(name)
      name =~ /^~[a-zA-Z0-9_\/]*$/
    end
  end
end


