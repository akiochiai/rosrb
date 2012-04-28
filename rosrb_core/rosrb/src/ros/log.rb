=begin
ros/log.rb

Author:: Aki Ochiai
License:: BSD License (2 clauses)

=end
require 'ros/time'
require 'rosgraph_msgs/msg'

module ROS
  
  class Logger
    def initialize(node_name, log_dir, level=Level::INFO)
      @level = level
      @node_name = node_name
      @mutex = Mutex.new
      if File.directory?(log_dir)
        @file = File.new("#{log_dir}/#{node_name}.log", "w")
      else
        if not Level::WARN < @level 
          time = ROS.get_walltime
          msg = "#{log_dir} is not a valid log directory.\n"
          $stderr.write("[WARN] [#{time}] #{msg}")
        end
        @file = nil
      end
      @publisher = nil
    end

    module Level
      DEBUG = 1
      INFO = 2
      WARN = 4
      ERROR = 8
      FATAL = 16
    end
    include Level

    attr_accessor :publisher 
  
    def log(msg, level)
      return nil if level < @level
      time = ROS.get_walltime
      log = "[#{LEVEL_TEXT[level]}] [#{time}] #{msg}"
      log_nl = "#{log}\n"
      @mutex.synchronize do
        if level < WARN
          $stdout.write(log_nl)
        else
          $stderr.write(log_nl)
        end
        @file.write(log_nl) unless @file.nil?
      end
      ros_log = RosgraphMsgs::Msg::Log.new(log)
      ros_log.header.stamp = time
      ros_log.header.seq = 0
      ros_log.header.frame_id = ""
      ros_log.level = level
      ros_log.name = @node_name
      ros_log.msg = msg
      ros_log.file = ""
      ros_log.function = ""
      ros_log.line = 0
      ros_log.topics = []
      @publisher.publish(ros_log) if @publisher
    end

    def debug(msg)
      log(msg, Level::DEBUG)
    end

    def info(msg)
      log(msg, Level::INFO)
    end

    def warn(msg)
      log(msg, Level::WARN)
    end

    def error(msg)
      log(msg, Level::ERROR)
    end

    def fatal(msg)
      log(msg, Level::FATAL)
    end

    private

    LEVEL_TEXT = {
      Level::DEBUG => "DEBUG",
      Level::INFO => "INFO",
      Level::WARN => "WARN",
      Level::ERROR => "ERROR",
      Level::FATAL => "FATAL"
    }
  end
end # module ROS
