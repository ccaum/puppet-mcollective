require 'puppet/application'
require 'puppet/run'

class Puppet::Application::Orchestrate < Puppet::Application
  run_mode :master

  option("--debug","-d")
  option("--verbose","-v")
  option("--ruby","-r")

  def help
    <<-HELP
puppet-orchestrate(8) -- Orchestrates a series of MCollective RPC requests
======

SYNOPSIS
--------
Parses a Puppet Orchestration script to the local MCollective infrastructure

USAGE
-----
puppet orchestrate [-d|--debug] [-v|--verbose] [-r|--ruby] <file> <var=val> <var=val> ...

DESCRIPTION
-----------
A convenient way to run a Puppet Orchestration script and supply parameters to it
HELP
  end

  def setup
    exit(Puppet.settings.print_configs ? 0 : 1) if Puppet.settings.print_configs?

    Puppet::Util::Log.newdestination(:console) unless options[:logset]

    Signal.trap(:INT) do
      $stderr.puts "Exiting"
      exit(1)
    end

    if options[:debug]
      Puppet::Util::Log.level = :debug
    elsif options[:verbose]
      Puppet::Util::Log.level = :info
    end
  end

  def apply_catalog(catalog)
    configurer = Puppet::Configurer.new
    configurer.run(:catalog => catalog, :pluginsync => false)
  end

  def main
    options[:ruby] ? ruby_main : puppet_main
  end

  def ruby_main
    require 'mcollective'
    require 'mcollective/orchestrate'

    if command_line.args.length > 0
      script = command_line.args.shift

      script = "%s.rb" % script unless script =~ /\.rb$/

      raise("Could not find orchestration script %s" % script) unless ::File.exist?(script)
    else
      raise "Please provide a script to run"
    end

    if command_line.args.length > 0
      while arg = command_line.args.shift
        if arg =~ /\A([a-z_\d]+)\s*=\s*(.+)\Z/
          ENV[$1.upcase] = $2
        end
      end
    end

    begin
      o = MCollective::Orchestrate.new(script)
      o.application.orchestrate
    rescue => e
      puts "Could not complete orchestration: %s" % MCollective::Util.colorize(:red, e)
    end
  end

  def puppet_main
    if command_line.args.length > 0
      klass = command_line.args.shift
      Puppet[:environment] = command_line.args.shift || 'production'

      Puppet[:code] = "include #{klass}"
    else
      raise "Please provide a deployment class to run"
    end

    if command_line.args.length > 0
      while arg = command_line.args.shift
        if arg =~ /\A([a-z_\d]+)\s*=\s*(.+)\Z/
          ENV["FACTER_#{$1}"] = $2
        end
      end
    end

    unless Puppet[:node_name_fact].empty?
      # Collect our facts.
      unless facts = Puppet::Node::Facts.indirection.find(Puppet[:node_name_value])
        raise "Could not find facts for #{Puppet[:node_name_value]}"
      end

      Puppet[:node_name_value] = facts.values[Puppet[:node_name_fact]]
      facts.name = Puppet[:node_name_value]
    end

    # Find our Node
    unless node = Puppet::Node.indirection.find(Puppet[:node_name_value])
      raise "Could not find node #{Puppet[:node_name_value]}"
    end

    # Merge in the facts.
    node.merge(facts.values) if facts

    begin
      Puppet[:parser] = 'future'

      # Compile our catalog
      starttime = Time.now
      catalog = Puppet::Resource::Catalog.indirection.find(node.name, :use_node => node)

      # Translate it to a RAL catalog
      catalog = catalog.to_ral

      catalog.finalize

      catalog.retrieval_duration = Time.now - starttime

      exit_status = apply_catalog(catalog)

      unless exit_status
        exit(1)
      else
        exit(exit_status)
      end
    rescue => detail
      Puppet.log_exception(detail)
      exit(1)
    end
  end
end
