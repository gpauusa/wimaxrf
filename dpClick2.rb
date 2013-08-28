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
    @port = config['interface']
    @vlan = config['vlan'].to_i
    @bsif = config['bs_interface']
    @netif = @port.dup
    @netif << ".#{@vlan}" if @vlan != 0
    @click_socket_path = config['click_socket_dir'] || '/var/run'
    @click_socket_path << "/click-#{name}.sock"
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
    if @mobiles.length > 0
      new_config = generate_click_config
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
