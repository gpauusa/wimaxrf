require 'socket'
require 'omf-aggmgr/ogs_wimaxrf/measurements.rb'
require 'omf-aggmgr/ogs_wimaxrf/client'
require 'omf-aggmgr/ogs_wimaxrf/mobileClients'
require 'omf-aggmgr/ogs_wimaxrf/netdev'
require 'omf-aggmgr/ogs_wimaxrf/circularBuffer'
require 'omf-aggmgr/ogs_wimaxrf/authenticator'
require 'omf-aggmgr/ogs_wimaxrf/necbsparams'
require 'omf-aggmgr/ogs_wimaxrf/util'
require 'rufus/scheduler'

EXTRA_NEC_MODULES = ["WMAN-DEV-MIB","WMAN-IF2-MIB","WMAN-IF2M-MIB","NEC-WIMAX-COMMON-REG",
  "NEC-WIMAX-COMMON-MIB-MODULE","NEC-WIMAX-BS-DEV-MIB","NEC-WIMAX-BS-IF-MIB"]

ASN_GRE_CONF = '/etc/asnctrl_gre.conf'

class NecBs < Netdev
  attr_reader :nomobiles, :serial, :tpsduul, :tppduul, :tpsdudl, :tppdud
  attr_accessor :dp,:auth
  attr_reader :asnHost,:sndPort,:rcvPort

  PARAMS_CLASSES = ["ArqService","HarqService","AsngwService","MonitorService",
    "MaintenanceService","DriverBaseService","DLProfileService","ULProfileService","WirelessService",
    "MPCService","MimoService","DebugService","MobileService","SecurityService"]

  def initialize(dp, auth, bsconfig, asnconfig)
    @dp = dp
    @asnHost = asnconfig['asnip'] || 'localhost'
    @rcvPort = asnconfig['asnrcvport'] || 54321
    @sndPort = asnconfig['asnsndport'] || 54322
    @auth = auth

    super(bsconfig)

    @meas = Measurements.new(bsconfig['bsid'], bsconfig['stats'])

    EXTRA_NEC_MODULES.each { |mod|
      add_snmp_module( mod )
    }

    debug(snmp_get("necWimaxBsStatMsNo.1").to_s)
    @serial = snmp_get("necWimaxBsSwCurrentVer.1").to_s
    get_bs_main_params()
    info("NEC BS (Serial# #{@serial}) at #{@frequency} MHz with #{@power} dBm")
    # Prepare constants
    @mSDUOID = get_oid("necWimaxBsSsPmDlThroughputSduCounter").to_s
    @mPDUOID = get_oid("necWimaxBsSsPmDlThroughputSduCounter").to_s
    @mMCSDLOID = get_oid("necWimaxBsAirStatDlFecCode").to_s
    @mMCSULOID = get_oid("necWimaxBsAirStatUlFecCode").to_s
    @mULCINR = get_oid("necWimaxBsAirStatUlCinr").to_s
    @mDLCINR = get_oid("necWimaxBsAirStatDlZoneCinr").to_s
    @mULRSSI = get_oid("necWimaxBsAirStatUlRssi").to_s
    @mDLRSSI = get_oid("necWimaxBsAirStatDlRssi").to_s
    @mobile_history = CircularBuffer.new(40)
    @mobs = MobileClients.new(@dp)
    check_existing()
    debug("Found #{@mobs.length} mobiles already registered")
    @dp.each{ |name,path|
      info "Starting #{name} datapath with #{path.length} clients"
      path.start()
    }

    @traphandler = Thread.new {
      debug("Creating trap handler")
      m = SNMP::TrapListener.new do |manager|
        manager.on_trap_default do |trap|
          debug trap.inspect
        end
      end
      m.join
    }
    scheduler = Rufus::Scheduler.start_new
    # Local stats gathering
    scheduler.every "#{@meas.localinterval}s" do
      get_mobile_stations()
      debug("Found #{@nomobiles} mobiles")
      get_bs_stats()
      debug("Checking mobile stats...")
      get_mobile_stats()
      debug("...done")
    end
    # Global stats gathering
    scheduler.every "#{@meas.globalinterval}s" do
      debug("BS Data collection")
      get_bs_main_params()
      get_bs_pdu_counters()
      @meas.bsstats(@frequency,@power,@nomobiles,@tpsduul, @tppduul, @tpsdudl, @tppdudl)
    end

    @sbController = Thread.new {
      # Connect to the NEC ASNGW daemon
      begin
        r = UDPSocket.open
        r.bind(0, @rcvPort)
      rescue Exception => ex
        debug("Failed to create WiMAXrf receiver control port: '#{ex}'")
      end
      loop {
        begin
          line = r.recvfrom(100)[0]    # Read line from the ASN
          #           puts "L=#{line}"
          args = line.split(' ')
          case args[0]
          when /^MS_REG/ then
            addMobile(args[1])
          when /^MS_DEL/ then
            @mobs.del_tunnel(args[1],args[2],args[3])
            debug "Deleting GRE: MAC=["+args[1]+"],DIR=["+args[2]+"],TUNNEL=["+args[3]+"]"
            if args[2] == "2" then deleteMobile(args[1]) end
          when /^MS_GRE/ then
            mac = args[1]
            debug "Adding GRE: MAC=["+mac+"],DIR=["+args[2]+"],TUNNEL=["+args[3]+"]"
            @mobs.add_tunnel(mac,args[2],args[3])
            if args[2] == "2" then startMobile(mac) end
          else error "Unknown command: "+line
          end
        rescue Exception => ex
          debug("Exception in control loop: '#{ex}'\n(at #{ex.backtrace})")
        end
      }
    }

  end

  def addMobile(mac)
    aclient = @auth.get(mac)
    if (aclient==nil)
      UDPSocket.open.send("DENY", 0, @asnHost, @sndPort)
      debug "Denied unknown client: #{mac}"
    else
      @mobs.add(mac,aclient.dpname,aclient.ipaddress)
      UDPSocket.open.send("ALLOW", 0, @asnHost, @sndPort)
      debug "Client ["+mac+"] added to datapath "+aclient.dpname
    end
  end

  def startMobile(mac)
    @mobs.start(mac)
    debug("Client ["+mac+"] started")
  end

  def modifyMobile(mac)
    aclient = @auth.get(mac)
    if (aclient==nil) then
      debug "Unknown client to modify: #{mac}"
    else
      if (@mobs.has_mac?(mac)) then
        @mobs.modify(mac,aclient.dpname,aclient.ipaddress)
        debug("Client ["+mac+"] modified to datapath/ip: "+aclient.dpname+"/"+aclient.ipaddress)
      end
    end
  end

  def deleteMobile(mac)
    @mobs.delete(mac)
    debug("Client ["+mac+"] deleted");
  end

  def check_existing
    hGREs = {}
    # Lets check if there are tunnels already up
    ifc = IO.popen("/sbin/ifconfig -a | grep greAnc")
    ifc.each {  |gre|
      hGREs[gre.scan(/greAnc_\d+/)[0]] = 1
    }
    # now let's find mobiles that are assigned to these
    if !(hGREs.empty?)
      File.open($asn_gre_conf).each { | line|
        begin
          mac,dir,tunnel,des = line.split(" ")
          next if !(hGREs.has_key?(tunnel))
          addMobile(mac)
          @mobs.add_tunnel(mac,dir,tunnel)
        rescue Exception => ex
          debug("Exception in check_existing: '#{ex}'")
        end
      }
    end
  end

  def set_time(time)
    @time = time
  end

  def mobile_history_dl
    @mobile_history.to_a
  end

  def shaper_history
    @shaper_history.to_a
  end

  def get_mobile_stations
    begin
      @nomobiles = snmp_get("necWimaxBsStatMsNo.1")
    rescue Exception => e
      @nomobiles = 0
    end
    return unless @nomobiles > 0
    begin
      snmp_get_multi(["necWimaxBsSsPmMacAddress"]) { |row|
        mac = row[0].value
        # Need to unpac this ...
        #       aip = @auth.getIP(mac)
        #         if (aip==nil) then
        #           #Kill the client
        #           debug "Denied unknown client: "+mac
        #         else
        #           @mobs.add(mac,aip[1],aip[0],MacAddress.bin2dec(mac))
        #           debug "Client ["+mac+"] added to vlan "+aip[1]
        #         end
      }
    rescue Exception => ex
      debug("Exception in get_mobile_stations(): '#{ex}'")
    end
  end

  def get_bs_stats
    #   snmp_walk()
    #    'necWimaxBsPmThroughputTable'
  end

  def get_bs_main_params
    #@frequency = snmp_get("wmanIf2BsOfdmaDownlinkFrequency.1")
    bsf = wiget("frequency")["frequency"]["frequency"]
    if bsf =~ /->/
      b = bsf.split('->')
      @frequency = b[0].strip.to_f
    else
      @frequency = bsf.to_f
    end
    @power = snmp_get("necWimaxBsPwrctrlTxPower.1").to_f
  end

  def get_bs_pdu_counters
    @tpsduul = 8.0 * snmp_get("necWimaxBsPmCurrentUlThroughputSdu.1").to_f
    @tppduul = 8.0 * snmp_get("necWimaxBsPmCurrentUlThroughputPdu.1").to_f
    @tpsdudl = 8.0 * snmp_get("necWimaxBsPmCurrentDlThroughputSdu.1").to_f
    @tppdudl = 8.0 * snmp_get("necWimaxBsPmCurrentDlThroughputPdu.1").to_f
  end

  def get_mobile_stats
    @mobs.each { |mac,m|
      begin
        sducount = snmp_get(@mSDUOID+".1.6."+m.snmp_mac).to_i
        debug("sducount #{sducount}")
        pducount = snmp_get(@mPDUOID+".1.6."+m.snmp_mac).to_i
        debug("pducount #{pducount}")
        m.du_reading(sducount,0, pducount, 0, Time.now.to_f)
        mcsdl = snmp_get(@mMCSDLOID+".1.6."+m.snmp_mac).to_i
        #debug("mcsdl #{mcsdl}")
        mcsul = snmp_get(@mMCSULOID+".1.6."+m.snmp_mac).to_i
        #debug("mcsul #{mcsul}")
        m.mcs_reading(mcsul,mcsdl)
        dlcinr = snmp_get(@mDLCINR+".1.6."+m.snmp_mac).to_f
        ulcinr = snmp_get(@mULCINR+".1.6."+m.snmp_mac).to_f / 4.0
        dlrssi = snmp_get(@mDLRSSI+".1.6."+m.snmp_mac).to_f
        ulrssi = snmp_get(@mULRSSI+".1.6."+m.snmp_mac).to_f / 4.0
        ma = Time.now.inspect
        @meas.clstats(ma, mac, ulrssi, ulcinr, dlrssi, dlcinr, m.mcsulmod, m.mcsdlmod)
      rescue Exception => ex
        debug("Exception in get_mobile_stats() for [#{mac}]: '#{ex}' at #{ex.backtrace[0]}")
        # Delete the MAC address
        #       @mobs.delete(mac)
      end
    }
    #     @mobile_history.push(ma)
    #     p @mobile_history.to_a
  end

  def set_shaping(slice, coef)
    @scoef[slice] = coef
  end

  def shape_traffic(shape)
    ms = @mobs.get_array()
    rate1 = (@scoef[0]*ms[0].mcsdlrate).to_i
    rate2 = (@scoef[1]*ms[1].mcsdlrate).to_i
    @shaper_history.push([@time, rate1 * 1.0e-3, rate2 * 1.0e-3])
    if $DEBUG
      puts "R1 = "+rate1.to_s+" R2 = "+rate2.to_s
    end
    if shape
      clientSession = TCPSocket.new("10.41.0.3", 777 )
      clientSession.puts "set shaper1.rate #{rate1}Kbps\n"
      clientSession.puts "set shaper2.rate #{rate2}Kbps\n"
      clientSession.close
    end
  end

  def restart
    begin
      status = snmp_set("wmanDevCmnResetDevice.0",1);
      if (status.include? "changed")
        result = "OK"
      else
        result = "Failed: '#{status}'"
      end
    rescue Exception => ex
      result = "Failed: '#{ex}'"
    end
  end

  def wiset(param, value)
    debug("wiset #{param} #{value}")
    result = ssh("/usr/sbin/wimax/cmd_app 3 #{param} #{value}")
  end

  def wigetAll
    wiget("all")
  end

  def wiget(param)
    #result = wiget("all")
    result = ssh("/usr/sbin/wimax/cmd_app 4 #{param}")
    wigetResult = {}
    attr = {}
    attrsKey = String.new(param)
    result.each_line("\n") do |row|
      if row.match('^\w{2,}')
        # add to main hash
        if not attr.empty?
          wigetResult[attrsKey] = attr
        end
      end
      if row.match(/^\w/)
        #new set of parameters
        attr = {}
        columns = row.split(":")
        if columns[1] != nil
          attrsKey = columns[1].strip
        end
      end
      if row.match(/^\s\S/)
        columns = row.split(":")
        if columns != nil
          attr[columns[0].strip]=columns[1].strip
        end
      end
    end
    wigetResult[attrsKey] = attr
    wigetResult
  end

  def get_info
    result = {}
    result["sysDescr0"] = snmp_get("sysDescr.0").to_s
    result["swVersion"] = @serial
    result["serialNo"] = snmp_get("necWimaxBsDevSerialNumber.1").to_s
    result["hwType"] = snmp_get("necWimaxBsDevHwType.1").to_s
    result = result.merge(wigetAll())
    result
  end

  def get_bs_pdu_stats
    get_bs_pdu_counters()
    result = {}
    result["tp-sdu-ul"] = @tpsduul.to_s
    result["tp-pdu-ul"] = @tppduul.to_s
    result["tp-sdu-dl"] = @tpsdudl.to_s
    result["tp-pdu-dl"] = @tppdudl.to_s
    result
  end

  def get_bs_mobiles
    result = {}
    result["Mobiles"] = @nomobiles
    result
  end

  def get_bs_interface_traffic
    result = {}
    snmp_get_multi(["ifIndex", "ifDescr", "ifInOctets", "ifOutOctets"]) do |row|
      ifc = {}
      ifc["ifDescription"] = "#{row[1].value}"
      ifc["ifInOctets"] = "#{row[2].value}"
      ifc["ifOutOctets"] = "#{row[3].value}"
      result["if#{row[0].value}"] = ifc
    end
    result
  end

  def to_s
    s = "NEC Basestation\n"
    s += "Serial number: #{@serial}\n"
  end

end
