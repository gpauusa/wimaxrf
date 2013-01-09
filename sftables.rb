require 'rubygems'
def sftableList()
  cmd = "sftables -L"
  result = system(cmd)
  result.each { |row|
  if row.match(/^ServiceClassName/)
  #new service class
  end
  if row.match(/chain to EntryName/)
  end  
        attr = Hash.new
      end
      if row.match(/[.]{2,}/)
      a = row.split(/[.]{2,}/)
      key = camelCase(a[0].strip)
      attr[key] = a[1].strip
      end
    }
    getResult[attrKey] = attr
    return getResult 
  end  
end
