require 'rubygems'
require 'socket'
require 'omf-aggmgr/ogs_wimaxrf/client'
require 'omf-aggmgr/ogs_wimaxrf/dataPath'
require 'omf-aggmgr/ogs_wimaxrf/mobileClients'
require 'omf-aggmgr/ogs_wimaxrf/execApp'

class Click2Datapath < DataPath
  attr_reader :port_bs, :port_net, :vlan_bs, :vlan_net

  def initialize(config = {})
    super()
    @app = nil
    @vlan_bs = config['vlan_bs'] || 0
    @vlan_net = config['vlan_net'] || 0
    @port_bs = config['bs_port'] || 'eth1'
    @port_net = config['network_port'] || 'eth2'
    @dpname = "#{port_net}-#{vlan_net}" # TODO: move to parent class
    @click_socket_path = "/var/run/click-#{@dpname}.sock"
    @click_socket = nil
    @click_command = config['click_command'] || '/usr/local/bin/click'
    @click_command += " --allow-reconfigure --file /dev/null --unix-socket #{@click_socket_path}"
  end

  # start a new click instance if not already running
  def start
    return unless @app.nil? && @mobiles.length > 0
    @app = ExecApp.new("C2DP-#{@dpname}", self, @click_command)
    @click_socket = UNIXSocket.new(@click_socket_path)
    update_click_config
  end

  # stop the click instance, do nothing if it's not running
  def stop
    return unless @app
    @click_socket.close
    @click_socket = nil
    begin
      @app.kill
    rescue Exception => ex
      error("Exception in stop:\n#{ex}")
    end
    @app = nil
  end

  def restart
    update_click_config
  end

  private

  # generate click configuration for this datapath
  def generate_click_config
    # first we build the parameters and the static
    # elements that depend on the presence of VLANs
    if @vlan_bs != 0
      interface_bs = "#{@port_bs}.#{@vlan_bs}"
      bs_vlan_encap = "-> vlan_to_bs_encap :: VLANEncap(#{@vlan_bs})"
      bs_vlan_decap = "-> bs_decap :: VLANDecap"
    else
      interface_bs = @port_bs
      bs_vlan_decap = ""
      bs_vlan_encap = ""
    end
    if @vlan_net != 0
      interface_net = "#{@port_net}.#{@vlan_net}"
      net_vlan_encap = "-> vlan_to_net_encap :: VLANEncap(#{@vlan_net})"
      net_vlan_decap = "-> net_decap :: VLANDecap"
    else
      interface_net = @port_net
      net_vlan_decap = ""
      net_vlan_encap = ""
    end
    config = "switch :: EtherSwitch; \
from_bs :: FromDevice(#{interface_bs}, PROMISC true); \
to_bs :: ToDevice(#{interface_bs}); \
from_net :: FromDevice(#{interface_net}, PROMISC true); \
to_net :: ToDevice(#{interface_net});"

    # then the two filter compounds that filter packets
    # coming from the bs and from the outside network
    filter_first_output = []
    filter_second_output = []
    network_filter = "filter_from_network :: {"
    bs_filter = "filter_from_bs :: {"
    counter = 1
    mobiles.each_key do |mac|
      network_filter << "filter_#{counter} :: HostEtherFilter(#{mac}, DROP_OWN false, DROP_OTHER true);"
      bs_filter << "filter_#{counter} :: HostEtherFilter(#{mac}, DROP_OWN true, DROP_OTHER false);"
      filter_first_output << "filter_#{counter}[0]"
      filter_second_output << "filter_#{counter}[1]"
      counter += 1
    end
    network_filter << "input -> filter_1;"
    network_filter << filter_first_output.join(", ") << " -> output;"
    network_filter << filter_second_output.join(" -> ") << " -> sink :: Discard; }"
    bs_filter << "input -> filter_1;"
    bs_filter << filter_second_output.join(", ") << " -> output;"
    bs_filter << filter_first_output.join(" -> ") + " -> sink :: Discard; }"

    # and at the end we generate package routing
    routing = "bs_queue :: Queue -> to_bs; \
net_queue :: Queue -> to_net; \
from_net -> filter_from_network #{net_vlan_decap} -> [0]switch; \
switch[0] #{net_vlan_encap} -> net_queue; \
from_bs -> filter_from_bs #{bs_vlan_decap} -> [1]switch; \
switch[1] #{bs_vlan_encap} -> bs_queue;"

    # put all the sections together and return the config
    config << network_filter << bs_filter << routing
  end

  # update the click configuration with a new one generated on the fly
  def update_click_config
    return unless @click_socket
    # TODO: the following return is wrong, we should instead
    #       generate an empty config when there are no clients
    return unless @mobiles.length > 0
    new_config = generate_click_config
    info("Loading new click configuration for datapath #{@dpname}")
    debug(new_config)
    @click_socket.send("write hotconfig #{new_config}\n", 0)
    # TODO: better error checking
    while line = @click_socket.gets
      if line == "200 Write handler 'hotconfig' OK"
        info("New config loaded successfully")
        break
      elsif line.match("^5[0-9]{2}*.")
        error("Loaded a wrong config, old config still running")
        break
      end
    end
  end

end
