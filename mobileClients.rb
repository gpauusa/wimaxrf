require 'omf-aggmgr/ogs_wimaxrf/client'

class MobileClients < MObject

  def initialize(auth, dp)
    @auth = auth
    @dp = dp
    @clients = {}
  end

  def [](mac)
    @clients[mac]
  end

  def each(&block)
    @clients.each(&block)
  end

  def has_mac?(mac)
    @clients.has_key?(mac)
  end

  def length
    @clients.length
  end

  def add(mac, dpname, ip=nil)
    return false if has_mac?(mac)
    c = Client.new(mac)
    c.dpname = dpname
    c.ip = ip
    @clients[mac] = c
    @dp[dpname].add(mac, c)
    true
  end

  def modify(mac, dpname, ip=nil)
    c = @clients[mac]
    return false unless c
    if dpname != c.dpname
      @dp[c.dpname].delete(mac)
      @dp[c.dpname].restart
      c.dpname = dpname
      c.ip = ip
      @dp[dpname].add(mac, c)
      @dp[dpname].restart
    elsif ip != c.ip
      c.ip = ip
      @dp[dpname].restart
    end
    true
  end

  def delete(mac)
    c = @clients[mac]
    return false unless c
    @clients.delete(mac)
    @dp[c.dpname].delete(mac)
    @dp[c.dpname].restart
    true
  end

  def add_tunnel(mac, ch, gre)
    return unless has_mac?(mac)
    if ch == '1'
      @clients[mac].ul = gre
    else
      @clients[mac].dl = gre
    end
  end

  def del_tunnel(mac, ch, gre)
    return unless has_mac?(mac)
    if ch == '1'
      @clients[mac].ul = nil
    else
      @clients[mac].dl = nil
    end
  end

  def start(mac)
    c = @clients[mac]
    return false unless c
    @dp[c.dpname].restart
    true
  end

  def start_all(empty=false)
    @dp.each_value do |datapath|
      if empty || datapath.length > 0
        datapath.restart
      end
    end
  end

  def on_client_registered(mac)
    if client = @auth.get_client(mac)
      add(mac, client.dpname, client.ipaddress)
      debug "Client [#{mac}] registered for datapath #{client.dpname}"
      true
    else
      debug "Denied unknown client [#{mac}]"
      false
    end
  end

  def on_client_deregistered(mac)
    if delete(mac)
      debug "Client [#{mac}] deregistered"
      true
    else
      debug "Client [#{mac}] was not registered"
      false
    end
  end

end
