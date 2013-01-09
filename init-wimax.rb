#!/usr/bin/ruby

$: << File.expand_path(File.dirname(__FILE__) + "/../../")
$: << File.expand_path("/usr/share/omf-common-5.2/omf-common")

require 'snmp'
require 'yaml'

# Let's add some path here so that OMF libs are found

#require 'necbs.rb'
#require 'airspanbs.rb'

def importMib( mib, path )
  puts "Copying MIB from MIBS/#{mib} to #{path} ..."
  FileUtils.cp_r("MIBS/#{mib}", path)
  puts "Importing MIB: #{mib} ..."
  SNMP::MIB.import_module("MIBS/#{mib}")
end

if SNMP::MIB.import_supported? then
        puts "Import is supported.  Available MIBs include:"
        mib_list = SNMP::MIB.list_imported
        puts mib_list
else
        puts "Import is NOT support; please install libsmi2 (smidump)"
        exit
end

puts "-------------------------------------------"

mibpath = '/usr/share/mibs/site'
FileUtils.mkdir_p(mibpath)
puts "Importing MIBs ..."
importMib("AIRSPAN-MIB.mib", mibpath)
importMib("AIRSPAN-PRODUCTS-MIB.mib", mibpath)
importMib("AIRSPAN-ASMAX-COMMON-MIB.mib", mibpath)
importMib("ASMAX-EBS-MIB.mib", mibpath)
importMib("WMAN-DEV-MIB.mib",mibpath )
importMib("WMAN-IF2-BS-MIB.mib", mibpath )
importMib("WMAN-IF2F-BS-MIB.mib", mibpath )
importMib("AIRSPAN-ASMAX-BS-COMMON-MIB.mib", mibpath )
importMib("WMAN-IF2M-MIB.mib", mibpath )
importMib("NEC-WIMAX-COMMON-REG.mib", mibpath )
importMib("NEC-WIMAX-COMMON-MIB-MODULE.mib", mibpath )
importMib("NEC-WIMAX-BS-DEV-MIB.mib", mibpath )
importMib("NEC-WIMAX-BS-IF-MIB.mib", mibpath )
#importMib("POMI-MOBILITY.mib", mibpath)

#$config = open("/etc/omf-aggmgr-5.2/enabled/wimaxrf.yaml") { |f| YAML.load(f) }
#puts $config['wimaxrf']['asngw'].to_s
#puts "BS"
#puts $config['wimaxrf']['bs']


