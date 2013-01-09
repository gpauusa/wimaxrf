require 'rubygems'
require 'rparsec'
require 'open3'

require 'rexml/document'
require 'rexml/element'
include RParsec
class SFTableParser 
  include Functors
  include Parsers
  extend Parsers
  
    Struct.new("ServiceClass",:header,:chains)
    Struct.new("Entry",:name,:mainatt,:qos,:att,:classifyRule)
    Struct.new("Pair",:name,:value)
  def quotedName
    quote = char("\"")
    dash = string("-")
    dw = ((dash|word).many).map{|strings|strings.to_s} 
    name = sequence(word,dw){|a,b|a+b}
    quote >> name << quote
  end
  
  def space
    string(" ")
  end
  
  def newline
    char("\n")
  end
  def value
    ipvalue = sequence(integer,sequence(string("."),integer){|x,y| x+y}.repeat(3).map{|strings|strings.to_s}){|a,b| a+b}
    altipvalue = sequence(ipvalue,string("/"),ipvalue){|a,b,c| a+b+c}
    jm = sequence(string("["),word,string("]")){|a,b,c| a+b+c}
    njm = sequence(number,space,jm){|a,b,c|a.to_s+b+c}
    value = alt(altipvalue,njm,number,word){|string|string.to_s}
  end
  
  def attribute
    sequence(word,valuedelim,value,newline){|name,vd,value,nl| Struct::Pair.new(name,value)}
  end
  def valuedelim
    sequence(space,char(":"),whitespace.many)
  end
  def unspecified
     string("unspecified"){|a| a}
  end
  
  def qoSParameters
    words = sequence(word,sequence(space,word){|a,b|a+b}){|a,b|a+b}
    typeQoS = sequence(whitespaces,words,space.many,newline){|ws,w,s,nl| w}|sequence(whitespaces,unspecified,newline){|ws,w,nl| w}
    qoSattribute = sequence(whitespace.many(1),word,valuedelim,value,newline){|ws,name,vd,value,nl|Struct::Pair.new(name,value)}
    qoSattributes = qoSattribute.lexeme(newline){|a|a}
    sequence(string("QoSparameters "),newline,typeQoS,qoSattributes){|x,y,z,w| Struct::Pair.new(z,w)}
  end
  
  def parser
    classdelim=sequence(char("=").many,newline)
    entrydelim=sequence(char("-").many,newline)
    space = string(" ")
    unset = string("unset"){|a| a}
    
    chain = sequence(whitespace.many,string("chain to EntryName"),valuedelim,quotedName,newline){|ws,cte,vd,name,nl|name}
    chains = chain.lexeme(newline)
    serviceclass = sequence(string("ServiceClassName"),valuedelim,quotedName,newline){|scn,vd,name,nl| name}
    serviceclassSection = sequence(serviceclass, chains){|sc,ch|Struct::ServiceClass.new(sc,ch) }
    serviceclasses = serviceclassSection.lexeme(classdelim) {|a|a}
     
    attributes = attribute.many.map {|a| a}
    entryName = sequence(string("EntryName"),valuedelim,quotedName,newline){|name,vd,value,nl| Struct::Pair.new(name,value)}
    
    cri = sequence(string("ClassifyRule["),number,string("]"),newline)
    classifyRule = sequence(cri,attributes){|a,b| b}
    entry = sequence(entryName,attributes,newline,qoSParameters,attributes,newline,classifyRule) {|a,b,c,d,e,f,g|
      Struct::Entry.new(a,b,d,e,g) }
    entries = entry.lexeme(entrydelim){|a|a}
    sftables = sequence(serviceclasses,entries) do|a,b| x = Array.new()
      x<<a
      c = Hash.new
      b.each {|en| c[en.name.value] = en}
      x<<c
      x
    end
  end
 
  
  def self.toXML(sftables)
    root = REXML::Element.new("SFTABLES")
    serviceclasses = sftables[0]
    entries = sftables[1]
    #entries.each {|e| p e.qos}
    serviceclasses.each do|sc|
      scEl = root.add_element("ServiceClass")
      scEl.add_attribute("name",sc.header)
      p sc.header
      sc.chains.each do|c| 
        e = entries[c]
        #p e
        entryEl = scEl.add_element("Entry")
        entryEl.add_attribute("name",c)
        e.mainatt.each do |att|
          attEl = entryEl.add_element(att.name)
          attEl.add_text(att.value)
        end
        qos = e.qos
        qosEl = scEl.add_element("QoSparameters")
        qosEl.add_attribute("type",qos.name)
        qos.value.each {|att| 
          attEl = qosEl.add_element(att.name)
          attEl.add_text(att.value)}
        e.att.each do |att|
          attEl = entryEl.add_element(att.name)
          attEl.add_text(att.value)
        end
        i = 1
          #crEl = scEl.add_element("ClassifyRule[#{i}]")
          crEl = entryEl.add_element("ClassifyRule")
        e.classifyRule.each do |cratt|
          #i=i+1
          attEl = crEl.add_element(cratt.name)
          attEl.add_text(cratt.value)
        end
      end
    end
    root
  end
  
  def self.sftableList
    content=""
    #content = `sftables -L`
    #content = system(cmd) 
    #stdout,stderr,status = Open3.capture("/usr/bin/sftables -L")
    #IO.popen('command_to_run') { |io| while (line = io.gets) do puts line end }
    #Open3.popen3('/usr/bin/sftables -L') do | stdin, stdout, stderr |
    #content = stdout.read
    #end
    #IO.popen('/usr/bin/sftables -L') { |io| while (line = io.gets) do content = content+ line end }
    firstLine=true
    IO.popen('/usr/bin/sftables -L') { |io| while (line = io.gets) do 
      if firstLine
        firstLine = false
      else
        content = content+ line
      end
      end }
      #IO.popen("date") { |f| puts f.gets }
    #a = %x[/usr/bin/sftables -L]
    #content = a.chomp
    p "CONTENT #{content}"
    result = SFTableParser.new.parser.parse(content)
    p result
    return SFTableParser.toXML(result)
  end
  
  
end