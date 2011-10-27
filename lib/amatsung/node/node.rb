# :private_key_path => '/Users/fgilcher/.ssh/aws-test', :public_key_path => '/Users/fgilcher/.ssh/aws-test.pub', :user => 'ubuntu'
module Amatsung
  class Node

    attr_accessor  :provider, :node_config, :vm, :provisioned, :cpus
    attr_reader :region

    def initialize(provider, node_config)
      @provider = provider
      @node_config = node_config
      @cpus = (node_config.delete(:cpus) || 1)
      @region = node_config.delete(:region)
      @provisioned = false
    end

    def bootstrap()
      @vm = provider.servers.bootstrap(node_config)
      self
    end

    def provision
      if provisioned?
        return self
      end

      @vm.ssh 'sudo apt-get -qy update'
      @vm.ssh 'sudo apt-get -qy install erlang erlang-src  gnuplot-nox libtemplate-perl libhtml-template-perl libhtml-template-expr-perl erlang-nox'
      @vm.ssh 'wget http://tsung.erlang-projects.org/dist/ubuntu/tsung_1.3.3-1_all.deb'
      @vm.ssh 'sudo dpkg -i tsung_1.3.3-1_all.deb'
      @vm.ssh 'rm tsung_1.3.3-1_all.deb'
      @provisioned = true
      self
    end

    def scp(local_path, remote_path, upload_options = {})
      @vm.scp(local_path, remote_path, upload_options)
    end

    def ssh(commands)
      @vm.ssh(commands)
    end

    def provisioned?
      @provisioned
    end

    def push_keys

    end

    def self.create(provider, node_config)
      s = self.new(provider, node_config)
      s.provisioned = node_config.delete(:provisioned) || false
      s.bootstrap
      s.provision
      s.push_keys
      s
    end

    def destroy
      @vm.destroy
    end

    def private_hostname
      /^([-\w]+)/.match(@vm.private_dns_name)[1]
    end

    def private_dns_name
      @vm.private_dns_name
    end
    
    def public_dns_name
      @vm.dns_name
    end

    def public_ip_address
      @vm.public_ip_address
    end

    def self.list

    end

  end
end