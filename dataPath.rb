require 'omf-aggmgr/ogs_wimaxrf/client'

class DataPath
  attr_reader :name

  def self.create(type, name, *args)
    info("Creating datapath #{name}")
    case type
      when 'click1', 'click' # backward compatibility
        Click1Datapath.new(*args)
      when 'click2'
        Click2Datapath.new(*args)
      when 'mf'
        MFirstDatapath.new(*args)
      when 'openflow'
        OpenFlowDatapath.new(*args)
      else
        error("Unknown type '#{type}' for datapath #{name}")
        nil
    end
  end

  def initialize(config)
    @mobiles = {}
    @name = config['name']
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

  def start
  end

  def stop
  end

  def restart
    stop
    start
  end

end
