require 'omf-aggmgr/ogs_wimaxrf/client'
require 'omf-aggmgr/ogs_wimaxrf/mobileclients'

class DataPath
  def checkexisting( clients )
  end

  def stop( clients )
    p "Datapath stopped"
  end

  def start( clients ) 
    p "Datapath started"
  end

  def restart( clients )
    stop( clients )
    start( mac, clients )
    p "Datapath restarted"   
  end

  def add( clients, mac )
    clients.add(mac)
    p "Client #{mac} added"   
  end

  def adddatapath( clients, mac, channel, gre )
    p "Added #{channel}->#{gre} for #{mac}"   
  end
  
  def deldatapath( clients, mac, channel, gre )
    p "Delete #{channel}->#{gre} for #{mac}"   
  end
end
