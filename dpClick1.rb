require 'rubygems'
require 'open4'
require 'omf-aggmgr/ogs_wimaxrf/client'
require 'omf-aggmgr/ogs_wimaxrf/dataPath'
require 'omf-aggmgr/ogs_wimaxrf/mobileClients'
require 'omf-aggmgr/ogs_wimaxrf/execApp'

class Click1Datapath < DataPath
  attr_reader :def_gw, :net_mask, :def_ip
  attr_reader :slices, :auth, :port, :vlan

  $asn_gre_conf = "/etc/asnctrl_gre.conf"

  def initialize(config)
   super
   @port = config['interface'] || "eth0"
   @vlan = config['vlan'] || 0
   @def_gw = config['def_gw'] || "10.41.0.1"
   @net_mask = config['net_mask'] || "255.255.0.0"
   @def_ip = config['def_ip'] || "10.41.0.254"
   @click_command = config['click_command'] || '/usr/bin/click'
   @click_conf = config['click_conf'] || '/tmp/Wimax.click'
   @click_conf += "-#{@vlan}"
   @app = nil
  end

  def onAppEvent(name, id, msg = nil)
    puts "Click1Datapath: name => '#{name}' id => '#{id}' msg => '#{msg}'"
  end

  def createclickconfiguration(file)
    file << "
switch :: EtherSwitch;
#{@port}_queue :: Queue;
"
    # If we don't have VLAN or it is 0 then we don;t have vlans
    if @vlan.nil? || @vlan == '0'
      file << "
FromDevice(#{@port}, PROMISC 1) -> [0]switch;
switch[0] -> #{@port}_queue -> ToDevice(#{port});
"
    else
      file << "
FromDevice(#{@port}.#{@vlan}, PROMISC 1) -> [0]switch;
switch[0] -> #{@port}_queue -> ToDevice(#{@port}.#{@vlan});
"
    end
    i = 1
    @mobiles.each do |mac, client|
      next unless (client.ul != nil and client.dl != nil and client.ip != nil)
      file << "// ---  Client #{i} -------- //"
      file << "
AddressInfo(c_#{i} #{client.ip} #{client.mac});
arr_#{i} :: ARPResponder(c_#{i});
arq_#{i} :: ARPQuerier(c_#{i});
"
      file << "
Script(write arq_#{i}.gateway #{@def_gw}, write arq_#{i}.netmask #{@net_mask} )
"
      file << "
ulgre_#{i} :: FromDevice(#{client.ul});
dlgre_#{i} :: ToDevice(#{client.dl});
"
      file << "
switch[#{i}] -> cf_#{i} :: Classifier(12/0806 20/0001, 12/0806 20/0002, -);
cf_#{i}[0] -> arr_#{i} -> [#{i}]switch
cf_#{i}[1] -> [1]arq_#{i}
cf_#{i}[2] -> Strip(14) -> dlgreq_#{i} :: Queue -> dlgre_#{i};
// Switch output //
ulgre_#{i} -> GetIPAddress(16) -> arq_#{i} -> [#{i}]switch;
"
      i += 1
    end
  end

  def stop
    return unless @app
    begin
      @app.kill
    rescue Exception => ex
      print "Exception in stop: '#{ex}'"
    end
    @app = nil
  end

  def start
    return unless @mobiles.length > 0
    File.delete(@click_conf + ".bak") if File.exist?(@click_conf + ".bak")
    File.rename(@click_conf, @click_conf + ".bak") if File.exist?(@click_conf)
    open(@click_conf, 'w') do |f|
      createclickconfiguration(f)
      f.close
    end
    @app = ExecApp.new("C1DP-#{name}", self, "#{@click_command} #{@click_conf}")
  end

end
