require 'omf-aggmgr/ogs_wimaxrf/dataPath'

class MFirstDatapath < DataPath

  def stop
    p "Datapath stopped"
  end

  def start
    p "Datapath started"
  end

end
