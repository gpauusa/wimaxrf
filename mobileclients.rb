
require 'omf-aggmgr/ogs_wimaxrf/client'

class MobileClients

  def initialize(mob=nil, debug=nil)
    @mobiles = {}
    if !mob.nil?
      mob.each { |mac| add(mac) }
    end
  end

  def add( mac, oid = nil )
    @mobiles[mac] = Client.new(mac,oid) unless @mobiles.has_key? mac
  end

  def add_oid( mac, oid )
    @mobiles[mac].oid = oid
  end

  def add_tunnel( mac, ch, gre )
    add(mac)
    if (ch == '1') then
      @mobiles[mac].ul = gre
    else
      @mobiles[mac].dl = gre
    end
  end 

  def del_tunnel(mac,ch,gre)
    # Check if MAC address exists already
    if (@mobiles.has_key? mac) then
      if (ch == '1') then
        @mobiles[mac].ul = nil
      else
        @mobiles[mac].dl = nil
      end
    end
  end

  def each(&block)
    return @mobiles.each( &block ) 
  end

  def [](mobile)
    return @mobiles[mobile]
  end

  def get_mac_addresses
    return @mobiles.keys
  end

  def get_clients
    return @mobiles.values
  end
 
  def length
    return @mobiles.length
  end

  def delete( mobile )
    return @mobiles.delete(mobile)
  end

end
