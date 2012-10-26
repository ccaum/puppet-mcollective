Puppet::Parser::Functions::newfunction(:discover, :type => :rvalue) do |vals|
  require 'mcollective'

  agent = "rpcutil"
  filter = {}

  if vals.size > 0
    if vals[0].is_a?(String)
      agent = vals[0]

      filter = vals[1] if vals[1].is_a?(Hash)
    else
      filter = vals[0]
    end
  end

  options = {:verbose      => false,
             :config       => MCollective::Util.config_file_for_user,
             :progress_bar => false,
             :filter       => MCollective::Util.empty_filter}

  client = MCollective::RPC::Client.new(agent, :configfile => options[:config], :options => options)

  if filter["compound_filter"]
    raise "Compound filters must be strings" unless filter["compound_filter"].is_a?(String)
    client.compound_filter(filter["compound_filter"])
  end

  Array(filter["identity_filter"]).each {|f| client.identity_filter f}
  Array(filter["class_filter"]).each {|f| client.class_filter f}
  Array(filter["fact_filter"]).each {|f| client.fact_filter f}

  Puppet.info("Discovering nodes matching filter using %s method for %d seconds" % [client.client.discoverer.discovery_method, client.discovery_timeout])

  client.discover
end

