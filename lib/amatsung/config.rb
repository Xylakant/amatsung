require 'yaml'
require 'fog'
require 'tempfile'
require 'pp'

module Amatsung

  class Config

    attr_accessor :compute, :default_region, :user, :ssh_opts, :default_groups, :szenario_file
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
      @compute[:region] ||= 'eu-west-1'
      @compute[:provider] ||= 'AWS'
      
      @default_region = @compute[:region]
      @ssh_opts = struct[:ssh]
      @ssh_opts[:user] ||= 'root'
     
      @default_groups = struct[:nodes][:groups] || ["tsung-default"]

      @master_config = struct[:nodes][:master]
      @slaves = struct[:nodes][:slaves]

      @errors = {}
      @nodes = []
      @connections = {}
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
            host = (node.region == default_region) ? node.private_hostname : node.public_dns_name
            s = doc.create_element('client', :host => host, :cpu => node.cpus)
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
            # monitor only hosts in the same region
            if node.region == default_region
              s = doc.create_element('monitor', :host => node.private_hostname)
              xml_node.add_child(s)
            end
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
        host = (node.region == default_region) ? node.private_hostname : node.public_dns_name

        config << "
Host #{host}
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

    def connection(region = nil)
      region ||= default_region
      @connections[region] ||= Fog::Compute.new(compute.merge({:region => region}))
      @connections[region]
    end

    def bootstrap
      create_security_groups
      bootstrap_master
      bootstrap_clients
      write_ssh_config
      write_ssh_key
      adjust_security_groups
    end

    def primary_group
      default_groups.first
    end

    def create_security_groups

      groups = default_groups
      groups += @master_config[:groups] unless @master_config[:groups].nil?

      @slaves.each {|s| groups += s[:groups] unless s[:groups].nil? }
      groups.uniq!

      all_regions.each do |region|
        c = connection(region)

        # trash the default group if it exists, we don't want any permissions to spill over from any
        # other tsung run. leave other groups as before
        def_group = c.security_groups.get(primary_group)
        def_group.destroy if def_group
        
        # recreate the default group and allow ssh access from everywhere
        def_group = c.security_groups.new(:name => primary_group, :description => "primary group autogenerated by amatsung")
        def_group.save
        def_group.authorize_port_range(22..22, :cidr_ip => "0.0.0.0/32")

        # create each group if it does not exist
        groups.each do |group|
          g = c.security_groups.get(group)
          if g.nil?
            g = c.security_groups.new(:name => group, :description => "autogenerated group by amatsung")
            g.save
          end
        end
      end
    end

    def all_regions
      regions = [@compute[:region]]
      regions.push @master_config[:region] unless @master_config[:region].nil?
      @slaves.each {|s| regions.push s[:region] unless s[:region].nil?}
      regions.uniq
    end

    # allows free communication between all hosts of the tsung cluster
    # i.e: drop the firewall for all hosts in the cluster 
    def adjust_security_groups

      all_regions.each do |region|
        c = connection(region)
        g = c.security_groups.get(primary_group)
        
        g.authorize_port_range(1024..65535, :cidr_ip => "#{master.public_ip_address}/32")
        nodes.each do |node|
          g.authorize_port_range(1024..65535, :cidr_ip => "#{node.public_ip_address}/32")
        end
      end
    end

    def bootstrap_master
      @master = bootstrap_node(@master_config)
    end

    def bootstrap_clients
      @slaves.each do |s|
        @nodes.push bootstrap_node(s)
      end
    end

    def bootstrap_node(opts)
      tags = {
        "Name" => opts[:name]
      }

      groups = default_groups + (opts[:groups] || [])

      node_opts = {
        :ami => opts[:ami],
        :region => opts[:region],
        :flavor_id => opts[:flavor_id],
        :tags => tags,
        :groups => groups
      }
      
      region = opts[:region]
      node_opts.merge!(ssh_opts)
      Amatsung::Node.create(connection(region), node_opts)
    end

    def shutdown
      nodes.each do |node|
        node.destroy
      end
      master.destroy
    end

  end

end