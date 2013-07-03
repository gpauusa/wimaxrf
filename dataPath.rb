require 'omf-common/mobject'

class DataPath < MObject
  attr_reader :name

  def initialize(config)
    super()
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
