require 'omf-aggmgr/ogs_wimaxrf/netdev'

class Bs < Netdev
  def initialize(bsconfig)
    super
  end

  def get_params_classes
    PARAMS_CLASSES
  end

  # it is necessary to implement these methods
  def get(param)
    raise NotImplementedError.new("You must implement Bs#get in your subclass.")
  end

  def set(param, value)
    raise NotImplementedError.new("You must implement Bs#set in your subclass.")
  end

  def restart
    raise NotImplementedError.new("You must implement Bs#restart in your subclass.")
  end

  def get_info
    raise NotImplementedError.new("You must implement Bs#get_info in your subclass.")
  end

  def get_bs_interface_traffic
    result = {}
  end

  def get_bs_pdu_stats
  end

  def checkAndSetParam(value, p)
  end

  def processServiceStatus(servDef, query)
  end

end
