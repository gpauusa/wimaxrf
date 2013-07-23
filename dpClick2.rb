require 'rubygems'
require 'socket'
require 'omf-aggmgr/ogs_wimaxrf/client'
require 'omf-aggmgr/ogs_wimaxrf/dataPath'
require 'omf-aggmgr/ogs_wimaxrf/mobileClients'
require 'omf-aggmgr/ogs_wimaxrf/execApp'

class Click2Datapath < DataPath
  attr_reader :port, :vlan

  def initialize(config)
    super
    @app = nil
    @port = config['interface']
    @vlan = config['vlan'].to_i
    @bsif = config['data_interface']
    @bsif << ".#{config['data_vlan']}" if config['data_vlan'].to_i != 0
    @netif = @port
    @netif << ".#{@vlan}" if @vlan != 0
    @click_socket_path = config['click_socket_dir'] || '/var/run'
    @click_socket_path << "/click-#{name}.sock"
    @click_socket = nil
    @click_command = config['click_command'] || '/usr/local/bin/click'
    @click_command << " --allow-reconfigure --file /dev/null --unix-socket #{@click_socket_path}"
  end

  # Starts a new click instance if it's not already running.
  def start
    return unless @app.nil?
    if File::exist?(@click_socket_path)
      File::delete(@click_socket_path)
    end
    @app = ExecApp.new("C2DP-#{name}", nil, @click_command)
    sleep(0.5)
    @click_socket = UNIXSocket.new(@click_socket_path)
    update_click_config
  end

  # Stops the click instance, does nothing if it's not running.
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

  # Reconfigures the running click instance without stopping it.
  def restart
    if @app
      update_click_config
    else
      start
    end
  end

  private

  # Generates and returns click configuration for this datapath.
  def generate_click_config
    # first of all we declare the main switch element
    # and all the sources/sinks that we're going to use
    config = "switch :: EtherSwitch; \
from_bs :: FromDevice(#{@bsif}, PROMISC true); \
to_bs :: ToDevice(#{@bsif}); \
from_net :: FromDevice(#{@netif}, PROMISC true); \
to_net :: ToDevice(#{@netif});"

    # then the two filter compounds for whitelisting
    # clients based on their mac address
    filter_first_output = []
    filter_second_output = []
    network_filter = 'filter_from_network :: {'
    bs_filter = 'filter_from_bs :: {'
    counter = 1
    @mobiles.each_key do |mac|
      network_filter << "filter_#{counter} :: HostEtherFilter(#{mac}, DROP_OWN false, DROP_OTHER true);"
      bs_filter << "filter_#{counter} :: HostEtherFilter(#{mac}, DROP_OWN true, DROP_OTHER false);"
      filter_first_output << "filter_#{counter}[0]"
      filter_second_output << "filter_#{counter}[1]"
      counter += 1
    end
    network_filter << 'input -> filter_1;'
    network_filter << filter_first_output.join(', ') << ' -> output;'
    network_filter << filter_second_output.join(' -> ') << ' -> sink :: Discard; }'
    bs_filter << 'input -> filter_1;'
    bs_filter << filter_second_output.join(', ') << ' -> output;'
    bs_filter << filter_first_output.join(' -> ') + ' -> sink :: Discard; }'

    # finally we plug everything into the switch
    routing = "bs_queue :: Queue -> to_bs; \
net_queue :: Queue -> to_net; \
from_net -> filter_from_network -> [0]switch; \
switch[0] -> net_queue; \
from_bs -> filter_from_bs -> [1]switch; \
switch[1] -> bs_queue;"

    # put all the sections together and return the config
    config << network_filter << bs_filter << routing
  end

  # Replaces the current configuration with a new one generated on the fly.
  def update_click_config
    return unless @click_socket
    if @mobiles.length > 0
      new_config = generate_click_config
    else
      new_config = ''
    end
    debug("Loading new click configuration for datapath #{name}")
    debug(new_config)
    @click_socket.send("write hotconfig #{new_config}\n", 0)
    # TODO: better error checking
    while line = @click_socket.gets
      # this will print just the first two lines for now FIXME
      debug("Click2 status: #{line}")
      if line.match('200|220')
        debug('New config loaded successfully')
        break
      elsif line.match('^5[0-9]{2}*.')
        error("Could not load new config, old config still running: #{line}")
        break
      end
    end
  end

end
