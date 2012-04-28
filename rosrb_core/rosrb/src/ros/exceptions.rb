module ROS
  class ROSError < StandardError; end

  class ROSNameError < StandardError; end

  class ROSRPCError < StandardError
    def initialize(code, message)
      super("code=#{code}, message=#{message}")
    end
  end

  class ROSServiceCallError < StandardError; end
end
