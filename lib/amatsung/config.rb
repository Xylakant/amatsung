require 'yaml'
require 'fog'
require 'tempfile'
require 'pp'

module Amatsung

  class Config

    attr_accessor :compute, :user, :ssh_opts, :group, :szenario_file
    attr_reader :errors, :nodes, :master

    def initialize(yml)

      l = lambda {|h,k| h[k] = Hash.new &l}
      struct = Hash.new &l

      begin
        struct.merge!(::YAML.load(yml))
      rescue ArgumentError => e
        raise Amatsung::InvalidConfig.new(e.message)
      end 
      pp struct

      @szenario_file = struct[:szenario]

      raise Amatsung::InvalidConfig.new("Szenarion file \"#{@szenario_file}\" is not readable.") unless File.exists?(@szenario_file)

      @compute = struct[:compute]
      @compute[:provider] ||= 'AWS'
      @ssh_opts = struct[:ssh]
      @ssh_opts[:user] ||= 'root'
     
      @group = struct[:nodes][:group] || "default"

      @master = struct[:nodes][:master]
      @slaves = struct[:nodes][:slaves]

      @errors = {}
      @nodes = []
    end

    def valid?
      @errors = {}
      
      @errors[:provider] = "Provider '#{compute[:provider]}' is not a supported provider." unless Amatsung::SUPPORTED_PROVIDERS.include?(compute[:provider]) 
      #@errors[:private_key] = "You must supply a path to a private key" unless (private_key && !private_key.empty?)
      #@errors[:public_key] = "You must supply a path to a public key" unless (public_key && !public_key.empty?)

      @errors.empty?
    end

    # creates the szenario file as needed by tsung including the booted servers
    def szenario

      File.open(szenario_file) do |f|
        doc = Nokogiri::XML::Document.parse(f)

        c = doc.create_element('clients') do |xml_node|

          nodes.each do |node|
            s = doc.create_element('client', :host => node.hostname, :cpu => node.cpus)
            xml_node.add_child(s)
          end
        end


#  <!-- to start os monitoring (cpu, network, memory). Use an erlang
#  agent on the remote machine or SNMP. erlang is the default --> 
#  <monitoring>
#    <monitor host="myserver" type="snmp"></monitor>
#  </monitoring>

        #monitor the tsung nodes to see if any bottleneck is on the node side
        m = doc.create_element('monitoring') do |xml_node|

          nodes.each do |node|
            s = doc.create_element('monitor', :host => node.hostname)
            xml_node.add_child(s)
          end
        end

        servers_node = doc.at_xpath '//servers'

        servers_node.after(m) # should be //servers.after and //servers.before since tsung is picky about the position
        servers_node.before(c)

        Tempfile.open('tsung-') do |tmp|
          tmp.write(doc.to_s)
          tmp.flush
          master.scp(tmp.path, 'tsung.xml')
        end
      end

    end

    def write_ssh_config
      config = ''

      nodes.each do |node|
        config << "
Host #{node.hostname}
  UserKnownHostsFile /dev/null
  StrictHostKeyChecking no"
      end

      Tempfile.open('ssh-conf-') do |tmp|
        tmp.write(config)
        tmp.flush
        master.scp(tmp.path, '.ssh/config')
      end
    end

    def write_ssh_key
      master.scp(File.expand_path(ssh_opts[:private_key_path]), '.ssh/id_rsa')
      master.ssh('chmod 0700 .ssh/id_rsa')
    end

    def connection
      @connection ||= connection = Fog::Compute.new(compute)
    end

    def bootstrap
      bootstrap_master
      bootstrap_clients
      write_ssh_config
      write_ssh_key
    end

    def bootstrap_master
      @master = bootstrap_node(@master[:name], @master[:flavor_id])
    end

    def bootstrap_clients
      @slaves.each do |s|
        @nodes.push bootstrap_node(s[:name], s[:flavor_id])
      end
    end

    def bootstrap_node(name, type)
      tags = {
        "Name" => name,
        "Tsung-Group" => group
      }
      node_opts = {
        :flavor_id => type,
        :tags => tags,
        :group => group
      }
      opts = node_opts.merge(ssh_opts)
      Amatsung::Node.create(connection, opts)
    end

    def shutdown
      nodes.each do |node|
        node.destroy
      end
      master.destroy
    end

  end

end