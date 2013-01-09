require 'rubygems'
require 'open4'
require 'omf-aggmgr/ogs_wimaxrf/client'
require 'omf-aggmgr/ogs_wimaxrf/mobileclients'

class ClickDatapath1
  attr_reader :click_command, :click_conf
  attr_reader :def_gw, :net_mask, :def_ip
  attr_reader :slices,:auth
  $asn_gre_conf = "/etc/asnctrl_gre.conf"

  def initialize(config = {})
   @def_gw = config['def_gw'] || "10.41.0.1"
   @net_mask = config['net_mask']  || "255.255.0.0"
   @def_ip = config['def_ip'] || "10.41.0.254"
   @click_command = config['click_command'] || '/usr/local/bin/click'
   @click_conf = config['click_conf'] || '/tmp/Wimax.click'
   killprocess("click")
  end

  def killprocess(proc)
    pipe = IO.popen("pkill -9  #{proc}")
    pipe.readlines.each { |line|
    }
    if $clickThread and $clickThread.alive? then
      Process.kill(9, $clickThread.pid)
      $clickThread.kill
    end
    return "Killed"
  end

  def createclickconfiguration(file,clients)
    file << "
switch :: EtherSwitch;
eth0_queue :: Queue;
FromDevice(eth0, PROMISC 1) -> [0]switch;
switch[0] -> eth0_queue -> ToDevice(eth0);
"
    i = 1
    clients.each { |mac,client|
      next unless (client.ul != nil and client.dl != nil and client.ip != nil);
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
    }
  end

  def runclick(conf)
    if $clickThread and $clickThread.alive? then
      Process.kill(9, $clickThread.pid)
      $clickThread.kill
    end
    $clickMonitor.kill if $clickMonitor and $clickMonitor.alive?

    stdin,stdout,stderr = '','',''
    $clickThread = Open4::bg("#{@click_command} #{conf}",0=>stdin, 1=>stdout, 2=>stderr)
    $clickMoitor = Thread.new {
      loop {
        puts stderr unless stderr.gets.nil?
        puts stdout unless stdout.gets.nil?
        sleep(1)
      }
    }
    return($clickThread.pid)
  end

  def adddatapath( clients, mac, channel, gre )
    if (channel == '1') then
      clients[mac].ul = gre
    else 
      clients[mac].dl = gre
    end
  end
  
  def deletedatapath( clients, mac, channel, gre )
    if (channel == '1') then
      clients[mac].ul = nil
    else 
      clients[mac].dl = nil
    end
  end

  def stop( clients )
    if $clickThread and $clickThread.alive? then
      Process.kill(9, $clickThread.pid)
      $clickThread.kill
    end
    return killprocess("click")
  end

  def start( clients )
    File.delete(@click_conf+".bak") if File.exist?(@click_conf+".bak") 
    File.rename(@click_conf,@click_conf+".bak") if File.exist?(@click_conf)
    open(@click_conf, 'w') { |f| 
      createclickconfiguration(f,clients); 
      f.close 
    }
    return runclick(@click_conf)
  end

  def restart( clients )
    stop( clients )
    start( clients )
   end



end