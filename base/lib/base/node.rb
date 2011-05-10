# Copyright (c) 2009-2011 VMware, Inc.
require 'nats/client'
require 'vcap/component'

$:.unshift(File.dirname(__FILE__))
require 'base'

class VCAP::Services::Base::Node < VCAP::Services::Base::Base

  def initialize(options)
    super(options)
    @node_id = options[:node_id]
  end

  def flavor
    return "Node"
  end

  def on_connect_node
    @logger.debug("#{service_description}: Connected to node mbus")
    @node_nats.subscribe("#{service_name}.provision.#{@node_id}") { |msg, reply|
      EM.defer { on_provision(msg, reply) }
    }
    @node_nats.subscribe("#{service_name}.unprovision.#{@node_id}") { |msg, reply|
      on_unprovision(msg, reply)
    }
    @node_nats.subscribe("#{service_name}.bind.#{@node_id}") { |msg, reply|
      on_bind(msg, reply)
    }
    @node_nats.subscribe("#{service_name}.unbind.#{@node_id}") { |msg, reply|
      on_unbind(msg, reply)
    }
    @node_nats.subscribe("#{service_name}.restore.#{@node_id}") { |msg, reply|
      EM.defer { on_restore(msg, reply) }
    }
    @node_nats.subscribe("#{service_name}.discover") { |_, reply|
      on_discover(reply)
    }
    send_node_announcement
    EM.add_periodic_timer(30) {
      send_node_announcement
    }
  end

  def on_provision(msg, reply)
    @logger.debug("#{service_description}: Provision request: #{msg} from #{reply}")
    provision_message = Yajl::Parser.parse(msg)
    plan = provision_message["plan"]
    credentials = provision_message["credentials"]
    response = provision(plan, credentials)
    response["node_id"] = @node_id
    @logger.debug("#{service_description}: Successfully provisioned service for request #{msg}: #{response.inspect}")
    @node_nats.publish(reply, encode_success(response))
  rescue => e
    @logger.warn(e)
    @node_nats.publish(reply, encode_failure(e))
  end

  def on_unprovision(msg, reply)
    @logger.debug("#{service_description}: Unprovision request: #{msg}.")
    unprovision_message = Yajl::Parser.parse(msg)
    name     = unprovision_message["name"]
    bindings = unprovision_message["bindings"]
    response = unprovision(name, bindings)
    @node_nats.publish(reply, encode_success(response))
  rescue => e
    @logger.warn(e)
    @node_nats.publish(reply, encode_failure(e))
  end

  def on_bind(msg, reply)
    @logger.debug("#{service_description}: Bind request: #{msg} from #{reply}")
    bind_message = Yajl::Parser.parse(msg)
    name      = bind_message["name"]
    bind_opts = bind_message["bind_opts"]
    credentials = bind_message["credentials"]
    response = bind(name, bind_opts, credentials)
    @node_nats.publish(reply, encode_success(response))
  rescue => e
    @logger.warn(e)
    @node_nats.publish(reply, encode_failure(e))
  end

  def on_unbind(msg, reply)
    @logger.debug("#{service_description}: Unbind request: #{msg} from #{reply}")
    unbind_message = Yajl::Parser.parse(msg)
    response = unbind(unbind_message)
    @node_nats.publish(reply, encode_success(response))
  rescue => e
    @logger.warn(e)
    @node_nats.publish(reply, encode_failure(e))
  end

  def on_restore(msg, reply)
    @logger.debug("#{service_description}: Restore request: #{msg} from #{reply}")
    restore_message = Yajl::Parser.parse(msg)
    instance_id = restore_message["instance_id"]
    backup_path = restore_message["backup_path"]
    response = restore(instance_id, backup_path)
    @node_nats.publish(reply, encode_success(response))
  rescue => e
    @logger.warn(e)
    @node_nats.publish(reply, encode_failure(e))
  end

  def on_discover(reply)
    send_node_announcement(reply)
  end

  def send_node_announcement(reply = nil)
    @logger.debug("#{service_description}: Sending announcement for #{reply || "everyone"}")
    a = announcement
    a[:id] = @node_id
    @node_nats.publish(reply || "#{service_name}.announce", Yajl::Encoder.encode(a))
  rescue
    @logger.warn(e)
  end

  def varz_details()
    # Service Node subclasses may want to override this method to
    # provide service specific data beyond what is returned by their
    # "announcement" method.
    return announcement
  end

  # Service Node subclasses must implement the following methods

  # provision(plan) --> {name, host, port, user, password}
  abstract :provision

  # unprovision(name) --> void
  abstract :unprovision

  # bind(name, bind_opts) --> {host, port, login, secret}
  abstract :bind

  # unbind(credentials)  --> void
  abstract :unbind

  # announcement() --> { any service-specific announcement details }
  abstract :announcement

  # service_name() --> string
  # (inhereted from VCAP::Services::Base::Base)

end