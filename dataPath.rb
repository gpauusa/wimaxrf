require 'omf-aggmgr/ogs_wimaxrf/client'

class DataPath
  def initialize
    @mobiles = Hash.new() 
  end
#  def [](mac)
#    return @mobiles[mac]
#  end

  def get_mac_addresses
    return @mobiles.keys
  end

  def get_clients
    return @mobiles.values
  end

  def length
    return @mobiles.length
  end

  def add( mac, mob )
    @mobiles[mac]=mob 
  end

  def delete( mac )
    @mobiles.delete(mac)
  end

  def adddatapath( clients, mac, channel, gre )
    if (channel == '1') then
      @mobiles[mac].ul = gre
    else
      @mobiles[mac].dl = gre
    end
  end

  def deletedatapath( clients, mac, channel, gre )
    if (channel == '1') then
      @mobiles[mac].ul = nil
    else
      @mobiles[mac].dl = nil
    end
  end


#  def checkexisting( clients )
#  end

  def stop()
    #p "Datapath stopped"
  end

  def start() 
    #p "Datapath started"
  end

  def restart()
    stop()
    start()
    #p "Datapath restarted"   
  end

end
