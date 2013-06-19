module MacAddress
  def self.bin2dec(mac)
    raise "Invalid MAC address '#{mac}'" unless mac.length == 6
    mac.unpack("CCCCCC").join(".")
  end

  def self.bin2hex(mac)
    raise "Invalid MAC address '#{mac}'" unless mac.length == 6
    mac.unpack("H2H2H2H2H2H2").join(":")
  end

  def self.dec2hex(mac)
    mac.split(".").map { |a| "%02x" % a }.join(":")
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
