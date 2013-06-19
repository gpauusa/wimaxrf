require 'omf-aggmgr/ogs_wimaxrf/client'

class MobileClients

  def initialize(dp, debug=nil)
    @dp = dp
    @mobiles = {}
  end

  def add(mac, dpname, ip = nil, oid = nil)
    raise("Unknown datapath: #{dpname} for mac #{mac}") unless @dp.has_key? dpname
    return if @mobiles.has_key?(mac)
    m = Client.new(mac, oid)
    m.dpname = dpname
    m.ip = ip
    @mobiles[mac] = m
    @dp[dpname].add(mac, m)
  end

  def start(mac)
    dpname = @mobiles[mac].dpname
    @dp[dpname].restart()
  end

  def modify(mac, dpname, ip = nil, oid = nil)
    m = @mobiles[mac]
    if dpname != m.dpname
      @dp[m.dpname].delete(mac)
      @dp[m.dpname].restart()
      @dp[dpname].add(mac, m)
    end
    m.dpname = dpname
    m.ip = ip
    @dp[dpname].restart()
  end

  def delete(mac)
#    return unless @mobiles.has_key?(mac)
    m = @mobiles[mac]
    @dp[m.dpname].delete(mac)
    @dp[m.dpname].restart()
    @mobiles.delete(mac)
  end

  def add_oid(mac, oid)
    @mobiles[mac].oid = oid
  end

  def add_tunnel(mac, ch, gre)
    return unless @mobiles.has_key?(mac)
    if ch == '1'
      @mobiles[mac].ul = gre
    else
      @mobiles[mac].dl = gre
    end
  end

  def del_tunnel(mac, ch, gre)
    # Check if MAC address exists already
    return unless @mobiles.has_key?(mac)
    if ch == '1'
      @mobiles[mac].ul = nil
    else
      @mobiles[mac].dl = nil
    end
  end

  def each(&block)
    @mobiles.each(&block)
  end

  def vlan_mobiles(v)
    @dp[v].getClients()
  end

  def has_mac?(mac)
    print "Checking for #{mac} = " + @mobiles.has_key?(mac).to_s
    @mobiles.has_key?(mac)
  end

  def [](mac)
    @mobiles[mac]
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

  def start_dp(v)
    @dp[v].start()
  end

  def stop_dp(v)
    @dp[v].stop()
  end

  def restart_dp(v)
    @dp[v].restart()
  end

end
