require 'singleton'
require 'thread'
require 'logger'
require 'eventmachine'
require 'ros/time'

module ROS

  # Global event loop object
  # 
  class EventLoop
    include Singleton

    @@mutex = Mutex.new
    @@running = false
    @@sim_clock = ROS::Time.new

    def start()
      if not @@running
        @@mutex.synchronize do
          if not @@running
            @@running = false
            @node_map = {}

            # register signal handler
            sig_handler = Proc.new do |sig|
              puts("Signal #{sig} received. shutting down ...")
              shutdown
            end 
            [:INT, :TERM, :HUP].each do |sig|
              Signal.trap(sig, sig_handler)
            end

            # register exit handler
            at_exit do
              Diag.log("at_exit called.")
              shutdown
            end
            @@running = true
            @thread = Thread.new do
              EM.error_handler do |e|
                Diag.log(e)
                @@mutex.synchronize do
                  @@running = false
                  @node_map.each do |name, node|
                    if node.ok?
                      node.signal_shutdown 
                      puts("Signal shutdown to node '#{name}'.")
                    end
                  end
                  EM.stop_event_loop
                  Diag.log("Signal stop to event loop.")
                end
              end
              begin
                EM.run
                Diag.log("Event loop stopped.")
              rescue => e
                Diag.log("Event loop stopped with #{e}")
                @@mutex.synchronize do
                  @@running = false
                  @node_map.each do |name, node|
                    if node.ok?
                      node.signal_shutdown 
                      puts("Signal shutdown to node '#{name}'.")
                    end
                  end
                end
              end
            end
          end
        end
      end
    end

    def shutdown() 
      @@mutex.synchronize do
        @@running = false
        @node_map.each do |name, node|
          if node.ok?
            node.signal_shutdown 
            puts("Signal shutdown to node '#{name}'.")
          end
        end
        EM.next_tick do
          EM.stop_event_loop
          Diag.log("Signal stop to event loop.")
        end
      end
    end

    def register_node(name, node)
      @@mutex.synchronize do
        if @node_map.has_key? name
          return false
        else
          @node_map[name] = node
          return true
        end
      end
    end
  end

  module Diag
    @@logger = Logger.new(STDOUT)
    @@logger.level = Logger::FATAL
    def self.log(msg)
      @@logger.debug(msg)
    end
  end
end

