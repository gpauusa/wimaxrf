require 'yaml'
require 'snmp'
include SNMP

manager = Manager.new(:Host => '10.3.9.3', :Community => 'private')
yaml = YAML::load(File.open("config.yaml"))

yaml.each_pair { |key, value|
    #puts "#{key} = #{value}"
    if value[0].eql?('Gauge32') 
        #print "INT #{key}=#{value.to_s}\n"
        vb = SNMP::VarBind.new(key, SNMP::Gauge32.new(value[1]))
        print "#{key} value changed to Gauge32 #{value[1]}\n"
    elsif value[0].eql?('Integer32') 
        #print "INT #{key}=#{value.to_s}\n"
        vb = SNMP::VarBind.new(key, SNMP::Integer32.new(value[1]))
        print "#{key} value changed to INT32 #{value[1]}\n"
    elsif value[0].eql?('OctetString') 
        #print "STR #{key}=#{val}\n"
        vb = SNMP::VarBind.new(key, SNMP::OctetString.new(value[1].to_s))
        print "#{key} value changed to STR #{value[1]}\n"
    end
    
    resp = manager.set(vb)
    print "GET got error #{resp.error_status()}\n"
    
    #val = @manager.get_value(newoid)
    #print "#{newoid} value now set to #{value}\n"
    #Frequency:2572000kHz (Gauge32)
    #downlink = VarBind.new("1.0.8802.16.2.1.2.9.1.2.1.6.1", Gauge32.new(2572000))
    #resp = manager.set(downlink)
    #print "GET got error #{resp.error_status()}\n"
}


manager.close
