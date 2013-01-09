require 'omf-aggmgr/ogs_wimaxrf/client'
require 'omf-aggmgr/ogs_wimaxrf/dataPath'

class OpenFlowDatapath < DataPath

  def stop()
    p "Datapath stopped"
  end

  def start() 
    p "Datapath started"
  end

end
