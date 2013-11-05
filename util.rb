module MacAddress
  def self.arr2hex(array)
    raise "Invalid MAC address #{array.inspect}" unless array.length == 6
    array.map { |a| "%02x" % a }.join(":")
  end

  def self.bin2dec(mac)
    raise "Invalid MAC address '#{mac}'" unless mac.length == 6
    mac.unpack("CCCCCC").join(".")
  end

  def self.bin2hex(mac)
    raise "Invalid MAC address '#{mac}'" unless mac.length == 6
    mac.unpack("H2H2H2H2H2H2").join(":")
  end

  def self.dec2hex(mac)
    arr2hex(mac.split("."))
  end

  def self.hex2dec(mac)
    mac.split(":").map { |a| a.to_i(16) }.join(".")
  end
end

def ip2Hex(a)
  if a =~ /^0x/
    hexString = a
  else
    hexString="0x"
    b = a.split(".")
    b.each do |e|
      c = "0" + e.to_i.to_s(16)
      l = c.size
      hexString = hexString+c[l-2..l-1]
    end
  end
  hexString
end

def mac2Hex(a)
  if a =~ /^0x/
    hexString = a
  else
    hexString="0x"
    b = a.split(":")
    b.each do |e|
      hexString = hexString+e
    end
  end
  hexString
end

def id2Hex(a)
  if a =~ /^0x/
    hexString = a
  else
    hexString="0x"
    a.each_byte do |e|
      c = e.to_s(16)
      l = c.size
      hexString = hexString+c
    end
  end
  hexString
end

module Util
  # Returns the IPv4 address of the network interface 'ifname'
  def self.get_interface_address(ifname)
    `ip addr show dev #{ifname} | sed -nre 's,.*inet ([0-9\.]+)/.*,\1,p'`
  end

  # Returns the vlan id of the network interface 'ifname'
  def self.get_interface_vlan(ifname)
    vlan = `ip -d link show dev #{ifname} | sed -nre 's,.*vlan id ([0-9]+) .*,\1,p'`
    vlan.to_i
  end

  # Returns true if the given interface exists, false otherwise
  def self.interface_exists?(interface, vlan=nil)
    interface += ".#{vlan}" if vlan
    result = `ip link show | grep "#{interface}"`
    !result.empty?
  end
end
