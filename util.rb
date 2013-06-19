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
