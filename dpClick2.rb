require 'monitor'
require 'socket'
require 'omf-aggmgr/ogs_wimaxrf/dataPath'
require 'omf-aggmgr/ogs_wimaxrf/execApp'

class Click2Datapath < DataPath
  include MonitorMixin

  attr_reader :port, :vlan

  def initialize(config)
    super
    @app = nil
    @bstype = config['bstype']
    @port = config['interface']
    @vlan = config['vlan'].to_i
    @bsif = config['bs_interface']
    @netif = @port.dup
    @netif << ".#{@vlan}" if @vlan != 0
    @defgw = config['default_gw'] || '10.41.0.1'
    @netmask = config['netmask'] || '255.255.0.0'
    @click_socket_path = config['click_socket_dir'] || '/var/run'
    @click_socket_path << "/click-#{@bstype}-#{name}.sock"
    @click_command = config['click_command'] || '/usr/bin/click'
    @click_command << " --allow-reconfigure --file /dev/null --unix-socket #{@click_socket_path}"
    @click_timeout = config['click_timeout'] || 5.0
  end

  # Starts a new click instance if it's not already running.
  def start
    synchronize {
      return if @app
      info("Starting datapath #{name}")

      if File::exist?(@click_socket_path)
        File::delete(@click_socket_path)
      end

      # start click process
      @app = ExecApp.new("C2DP-#{name}", self, @click_command)

      # wait for click to open the control socket
      timeout = @click_timeout.to_f
      until File::exist?(@click_socket_path)
        raise "Timed out waiting for control socket to appear" if timeout <= 0
        timeout -= 0.1
        sleep(0.1)
      end
      # open control socket
      @click_socket = UNIXSocket.new(@click_socket_path)

      # send initial configuration
      update_click_config
    }
  end

  # Stops the click instance, does nothing if it's not running.
  def stop
    synchronize {
      return unless @app
      info("Stopping datapath #{name}")

      # gracefully shutdown the connection
      begin @click_socket.send("QUIT", 0) rescue Errno::EPIPE end
      # close the control socket
      @click_socket.close

      # kill the process
      begin @app.kill('TERM') rescue Errno::ESRCH end
      @app = nil
    }
  end

  # Reconfigures the running click instance without stopping it.
  def restart
    synchronize {
      if @app
        update_click_config
      else
        start
      end
    }
  end

  def onAppEvent(event, id, msg)
    case event
    when 'DONE.ERROR'
      # click crashed, restart it
      synchronize {
        stop
        start
      }
    end
  end

  private

  # Returns a click configuration string suitable for Airspan-style base stations.
  def gen_airspan_config
    # first of all we declare the main switch element
    # and all the sources/sinks that we're going to use
    config = "switch :: EtherSwitch; \
from_bs :: FromDevice(#{@bsif}, PROMISC true); \
to_bs :: ToDevice(#{@bsif}); \
from_net :: FromDevice(#{@netif}, PROMISC true); \
to_net :: ToDevice(#{@netif}); "

    # then the two filter compounds for whitelisting
    # clients based on their mac address
    filter_first_output = []
    filter_second_output = []
    network_filter = 'filter_from_network :: { '
    bs_filter = 'filter_from_bs :: { '
    i = 1
    @mobiles.each_key do |mac|
      network_filter << "filter_#{i} :: HostEtherFilter(#{mac}, DROP_OWN false, DROP_OTHER true); "
      bs_filter << "filter_#{i} :: HostEtherFilter(#{mac}, DROP_OWN true, DROP_OTHER false); "
      filter_first_output << "filter_#{i}[0]"
      filter_second_output << "filter_#{i}[1]"
      i += 1
    end
    network_filter << 'input -> filter_1; '
    network_filter << filter_first_output.join(', ') << ' -> output; '
    network_filter << filter_second_output.join(' -> ') << ' -> Discard; } '
    bs_filter << 'input -> filter_1; '
    bs_filter << filter_second_output.join(', ') << ' -> output; '
    bs_filter << filter_first_output.join(' -> ') + ' -> Discard; } '
    config << network_filter << bs_filter

    # finally we plug everything into the switch
    config << "from_net -> filter_from_network -> [0]switch[0] -> Queue -> to_net; \
from_bs -> filter_from_bs -> [1]switch[1] -> Queue -> to_bs;"
  end

  # Returns a click configuration string suitable for NEC-style base stations.
  def gen_nec_config
    config = "switch :: EtherSwitch; \
FromDevice(#{@netif}, PROMISC true) -> [0]switch; \
switch[0] -> Queue -> ToDevice(#{@netif}); "

    i = 1
    @mobiles.each do |mac, client|
      next unless client.ul && client.dl && client.ip
      config << "AddressInfo(c_#{i} #{client.ip} #{client.mac}); \
arr_#{i} :: ARPResponder(c_#{i}); \
arq_#{i} :: ARPQuerier(c_#{i}); \
\
Script(write arq_#{i}.gateway #{@defgw}, write arq_#{i}.netmask #{@netmask}); \
\
ulgre_#{i} :: FromDevice(#{client.ul}); \
dlgre_#{i} :: ToDevice(#{client.dl}); \
\
switch[#{i}] -> cf_#{i} :: Classifier(12/0806 20/0001, 12/0806 20/0002, -); \
cf_#{i}[0] -> arr_#{i} -> [#{i}]switch; \
cf_#{i}[1] -> [1]arq_#{i}; \
cf_#{i}[2] -> Strip(14) -> dlgreq_#{i} :: Queue -> dlgre_#{i}; \
ulgre_#{i} -> GetIPAddress(16) -> arq_#{i} -> [#{i}]switch; "
      i += 1
    end
    config
  end

  # Replaces the current configuration with a new one generated on the fly.
  def update_click_config
    if @mobiles.length > 0
      if @bstype == 'nec'
        new_config = gen_nec_config
      else
        new_config = gen_airspan_config
      end
    else
      new_config = ''
    end

    debug("Loading new click configuration for datapath #{name}")
    begin
      @click_socket.send("WRITE hotconfig #{new_config}\n", 0)
    rescue Errno::EPIPE => e
      # click has probably crashed, so don't do anything because
      # it will be automatically restarted with the new config
      debug("Error writing on control socket: #{e.message}")
    else
      while line = @click_socket.gets
        case line
        when /^2\d\d/
          debug("New config loaded successfully")
          break
        when /^5\d\d/
          error("Could not load new config, old config still running: #{line}")
          break
        end
      end
    end
  end

end
