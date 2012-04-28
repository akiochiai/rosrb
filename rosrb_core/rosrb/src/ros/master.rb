require 'xmlrpc/client'
require 'xmlrpc/server'
require 'ros/exceptions'

module ROS
  class MasterProxy

    def initialize(master_uri)
      uri = URI(master_uri)
      @client = XMLRPC::Client.new(uri.host, "/", uri.port)
    end

    def register_service(caller_id, service, service_api, caller_api)
      result = @client.call("registerService", caller_id, service, service_api, caller_api)
      code, message, ignore = result
      raise ROSRPCError.new(code, message) unless code == 1
      nil
    end
    
    def unregister_service(caller_id, service, service_api)
      result = @client.call("unregisterService", caller_id, service, service_api)
      code, message, ignore = result
      raise ROSRPCError.new(code, message) unless code == 1
      nil
    end

    def register_subscriber(caller_id, topic, topic_type, caller_api)
      Diag.log("Call master API registerSubscriber(#{caller_id}, #{topic}, #{topic_type}, #{caller_api})")
      result = @client.call("registerSubscriber", caller_id, topic, topic_type, caller_api)
      code, message, publishers = result
      raise ROSRPCError.new(code, message) unless code == 1
      publishers
    end

    def unregister_subscriber(caller_id, topic, caller_api)
      Diag.log("Call master API unregisterSubscriber(#{caller_id}, #{topic}, #{caller_api})")
      result = @client.call("unregisterSubscriber", caller_id, topic, caller_api)
      code, message, num_unregistered = result
      raise ROSRPCError.new(code, message) unless code == 1
      num_unregistered
    end

    def register_publisher(caller_id, topic, topic_type, caller_api)
      Diag.log("Call master API registerPublisher(#{caller_id}, #{topic}, #{topic_type}, #{caller_api})")
      result = @client.call("registerPublisher", caller_id, topic, topic_type, caller_api)
      code, message, subscriber_apis = result
      Diag.log("#{code}, #{message}, #{subscriber_apis}")
      raise ROSRPCError.new(code, message) unless code == 1
      subscriber_apis
    end

    def unregister_publisher(caller_id, topic, caller_api)
      Diag.log("Call master API unregisterPublisher(#{caller_id}, #{topic}, #{caller_api})")
      result = @client.call("unregisterPublisher", caller_id, topic, caller_api)
      code, message, num_unregistered = result
      raise ROSRPCError.new(code, message) unless code == 1
      num_unregistered
    end

    def lookup_node(caller_id, node_name)
      result = @client.call("lookupNode", caller_id, node_name)
      code, message, uri = result
      raise ROSRPCError.new(code, message) unless code == 1
      uri 
    end

    def get_publisher_topics(caller_id, subgraph)
      result = @client.call("getPublisherTopics", caller_id, subgraph)
      code, message, topics = result
      raise ROSRPCError.new(code, message) unless code == 1
      topics 
    end

    def get_system_state(caller_id)
      result = @client.call("getSystemState", caller_id)
      code, message, system_state = result
      raise ROSRPCError.new(code, message) unless code == 1
      system_state
    end

    # Get the URI of the master.
    def get_uri(caller_id)
      result = @client.call("getUri", caller_id)
      code, message, master_uri = result
      raise ROSRPCError.new(code, message) unless code == 1
      master_uri
    end

    # Lookup all provider of a particular service.
    def lookup_service(caller_id, service)
      result = @client.call("lookupService", caller_id, service)
      code, message, service_uri = result
      raise ROSRPCError.new(code, message) unless code == 1
      service_uri
    end

    def delete_param(caller_id, key)
      result = @client.call("deleteParam", caller_id, key)
      code, message, retval = result
      raise ROSRPCError.new(code, message) unless code == 1
      retval
    end

    def set_param(caller_id, key, value)
      result = @client.call("setParam", caller_id, key, value)
      code, message, retval = result
      raise ROSRPCError.new(code, message) unless code == 1
      retval
    end

    def get_param(caller_id, key)
      result = @client.call("getParam", caller_id, key)
      code, message, retval = result
      raise ROSRPCError.new(code, message) unless code == 1
      retval
    end

    def search_param(caller_id, key)
      result = @client.call("searchParam", caller_id, key)
      code, message, retval = result
      if code == 1
        retval
      else
        nil
      end
    end

    def has_param(caller_id, key)
      result = @client.call("hasParam", caller_id, key)
      code, message, retval = result
      raise ROSRPCError.new(code, message) unless code == 1
      retval
    end

    def get_param_names(caller_id)
      result = @client.call("getParamNames", caller_id)
      code, message, retval = result
      raise ROSRPCError.new(code, message) unless code == 1
      retval
    end
  end
end
