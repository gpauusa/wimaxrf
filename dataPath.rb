require 'omf-aggmgr/ogs_wimaxrf/client'

class DataPath

  def initialize
    @mobiles = {}
  end

  def get_mac_addresses
    @mobiles.keys
  end

  def get_clients
    @mobiles.values
  end

  def length
    @mobiles.length
  end

  def add(mac, mob)
    @mobiles[mac] = mob
  end

  def delete(mac)
    @mobiles.delete(mac)
  end

  def adddatapath(clients, mac, channel, gre)
    if channel == '1'
      @mobiles[mac].ul = gre
    else
      @mobiles[mac].dl = gre
    end
  end

  def deletedatapath(clients, mac, channel, gre)
    if channel == '1'
      @mobiles[mac].ul = nil
    else
      @mobiles[mac].dl = nil
    end
  end

  def stop
    #p "Datapath stopped"
  end

  def start
    #p "Datapath started"
  end

  def restart
    stop()
    start()
    #p "Datapath restarted"
  end

end
