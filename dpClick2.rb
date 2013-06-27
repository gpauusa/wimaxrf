require 'rubygems'
require 'open4'
require 'socket'
require 'omf-aggmgr/ogs_wimaxrf/client'
require 'omf-aggmgr/ogs_wimaxrf/dataPath'
require 'omf-aggmgr/ogs_wimaxrf/mobileClients'
require 'omf-aggmgr/ogs_wimaxrf/execApp'

class Click2Datapath < DataPath
  attr_reader :click_command, :click_socket
  attr_reader :app, :app_id
  attr_reader :port_bs, :port_net, :vlan_bs, :vlan_net

  # init of the Click configuration and start of the instance
  def initialize(config = {})
    super()
    @vlan_bs = config['vlan_bs'] || 0
    @vlan_net = config['vlan_net'] || 0
    @port_bs = config['bs_port'] || 'eth1'
    @port_net = config['network_port'] || 'eth2'
    @click_sock = UNIXSocket.new("/tmp/#{@vlan_net}.clicksocket")
    @click_command = config['click_command'] ||"/usr/local/bin/click --allow-reconfigure --unix-socket #{@click_sock} -f /dev/null"
    @app = nil
    @app_id = "CDP-#{@vlan_net}"
    puts "Adding #{@app_id}"
    self.start
  end

  # generate the click configuration for this datapath see wimaxrf/click/data-path-vlan.click for an example
  def generate_click_configuration()
    # first we build the parameters and the static elements depending on the presence of the vlans
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
    config = "switch :: EtherSwitch;\
from_bs :: FromDevice(#{interface_bs}, PROMISC true);\
to_bs :: ToDevice(#{interface_bs});\
from_net :: FromDevice(#{interface_net}, PROMISC true); \
to_net :: ToDevice(#{interface_net});"
    # then the two filter compounds (inbound and outbound)
    counter = 1
    filter_first_output = []
    filter_second_output = []
    network_filter = "filter_from_network :: {"
    bs_filter = "filter_from_bs :: {"
    mobiles.keys.each { |mac|
      network_filter << "filter_#{counter} :: HostEtherFilter(#{mac}, DROP_OWN false, DROP_OTHER true);"
      bs_filter << "filter_#{counter} :: HostEtherFilter(#{mac}, DROP_OWN true, DROP_OTHER false);"
      filter_first_output.push("filter_#{counter}[0]")
      filter_second_output.push("filter_#{counter}[1]")
      counter += 1
    }
    network_output_flow = "input -> filter_1;" + filter_first_output.join(', ') + " -> output;"
    network_sink_flow  = filter_second_output.join(" -> ") + " -> sink :: Discard;}"
    bs_output_flow = "input -> filter_1;" + filter_second_output.join(', ') + " -> output;"
    bs_sink_flow  = filter_first_output.join(" -> ") + " -> sink :: Discard;}"
    network_filter << network_output_flow << network_sink_flow
    bs_filter << bs_output_flow << bs_sink_flow
    # and at the end we generate package routing
    routing = "bs_queue :: Queue -> to_bs; \
net_queue :: Queue -> to_net; \
from_net -> filter_from_network #{net_vlan_decap} -> [0]switch;switch[0] #{net_vlan_encap} -> net_queue; \
from_bs -> filter_from_bs #{bs_vlan_decap} -> [1]switch;switch[1] #{bs_vlan_encap} -> bs_queue;"
    # join all the part of the config
    config << network_filter << bs_filter << routing << "\n"
    return config
  end

  #start a new click instance if none where found
  def start
    return unless @mobiles.length > 0
    return unless @app.nil?
    @app = Exec.new(@app_id, self, "#{@click_command}")
    self.update_click_config
    return (@app)
  end

  #stop the click instance, do nothing if click this click instance is not running
  def stop
    return if @app.nil?
    begin
      @app.kill(@app_id)
    rescue Exception => ex
      print "Exception in stop: '#{ex}'"
    end
    @app = nil
  end

  # Update the click configuration with a new one generated on the fly
  def update_click_config
    return unless @mobiles.lenght > 0
    new_config = generate_click_configuration()
    info("loading new_config to click for vlan #{@vlan_net}:\n #{new_config}")
    @click_sock.send "WRITE hotconfig #{new_config}", 0
    # TODO: better error checking
    while line = @click_sock.gets
      if line == "200 Write handler 'hotconfig' OK"
        info("New click config loaded successfully")
        break
      elsif line.match("^5[0-9]{2}*.")
        error("loaded a wrong click config old config still running")
        break
      end
    end
  end
end
