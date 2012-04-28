require 'ros/time'

module ROS
  class TimeEvent
    def initialize(period)
      @last_expected = ROS.get_walltime() + period
      @last_real = ROS.get_walltime()
      @current_expected = nil
      @current_real = nil
      @last_duration = nil
    end

    attr_accessor :last_expected, :last_real, :current_expected, :current_real, :last_duration
  end

  class Timer
    # Periodic timer 
    # @note Only support walltime currently
    # @param [Numeric]
    # @param [Hash] 
    # @param [Proc] block timer callback
    def initialize(period, options, &block)
      oneshot = (options[:oneshot] or false)
      @period = Duration.new(period)
      @event = TimeEvent.new(@period)

      operation = proc do
        EM.defer do
          @event.current_expected = @event.last_real + @period
          @event.current_real = ROS.get_walltime()
          start_time = ROS.get_walltime()
          block.call(@event)
          end_time = ROS.get_walltime()
          @event.last_expected = @event.current_expected
          @event.last_real = @event.current_real
          @event.last_duration = end_time - start_time
        end
      end

      EM.next_tick do
        if oneshot 
          @timer = EM.add_timer(period, operation)
        else
          @timer = EM.add_periodic_timer(period, operation)
        end
      end
    end

    def shutdown
      @timer.cancel
    end
  end
end
