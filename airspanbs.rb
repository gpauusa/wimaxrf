require 'socket'
require 'omf-aggmgr/ogs_wimaxrf/client'
require 'omf-aggmgr/ogs_wimaxrf/mobileClients'
require 'omf-aggmgr/ogs_wimaxrf/netdev'
require 'omf-aggmgr/ogs_wimaxrf/circularBuffer'
require 'omf-aggmgr/ogs_wimaxrf/dpClick1'
require 'omf-aggmgr/ogs_wimaxrf/dpOpenflow'
require 'omf-aggmgr/ogs_wimaxrf/authenticator'
require 'omf-aggmgr/ogs_wimaxrf/measurements'
require 'rufus/scheduler'

EXTRA_AIR_MODULES = []
#                   ["AIRSPAN-ASMAX-COMMON-MIB",
#                    "ASMAX-EBS-MIB", "ASMAX-ESTATS-MIB",
#                    "WMAN-DEV-MIB", "WMAN-IF2-BS-MIB"]

class AirBs < Netdev
  attr_reader :nomobiles, :serial, :tpsduul, :tppduul, :tpsdudl, :tppdud
  attr_accessor :dp, :auth
  attr_reader :asnHost, :sndPort, :rcvPort

  def initialize(dp, auth, bsconfig, asnconfig)
    @dp = dp
    @asnHost = asnconfig['asnip'] || 'localhost'
    @auth = auth

    super(bsconfig)

    @meas = Measurements.new(bsconfig['bsid'], bsconfig['stats'])

    EXTRA_AIR_MODULES.each { |mod|
      add_snmp_module(mod)
    }

    # set frequency
    #snmp_set("wmanIf2BsCmnPhyDownlinkCenterFreq.1", 2572000)
    get_bs_main_params
    info("Airspan BS (Serial# #{@serial}) at #{@frequency} MHz with #{@power} dBm")
    # Prepare constants
    #@mSDUOID = get_oid("necWimaxBsSsPmDlThroughputSduCounter").to_s

    @mobs = MobileClients.new(@dp)

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
      get_bs_stats()
      @meas.bsstats(@frequency, @power, @nomobiles, @tpsduul, @tppduul, @tpsdudl, @tppdudl)
    end
  end

  def get_bs_main_params
    # AIRSPAN-ASMAX-COMMON-MIB::asMaxCmInventorySerialNumber.1
    @serial = snmp_get("1.3.6.1.4.1.989.1.16.1.2.1.6.1").to_s
    # WMAN-IF2-BS-MIB::wmanIf2BsCmnPhyDownlinkCenterFreq.1
    #   FIXME: what about "WMAN-IF2-BS-MIB::wmanIf2BsCmnPhyUplinkCenterFreq.1" ???
    @frequency = snmp_get("1.0.8802.16.2.1.2.9.1.2.1.6.1").to_i / 1000.0
    # ASMAX-EBS-MIB::asxEbsBsCfgNumberOfAntennas.1
    #@noantennas = snmp_get("1.3.6.1.4.1.989.1.16.2.7.4.1.1.43.1").to_i
    # ASMAX-EBS-MIB::asxEbsRfStatusAchievedTxPower.<Antenna[0..3]>
    @power = snmp_get("1.3.6.1.4.1.989.1.16.2.7.7.2.1.3." + "0").to_i / 100.0
    # ASMAX-EBS-MIB::asxEbsRfStatusAchievedRxGain.<Antenna[0..3]>
    @rxgain = snmp_get("1.3.6.1.4.1.989.1.16.2.7.7.2.1.4." + "0").to_i / 100.0
  end

  def get_bs_stats
    get_bs_temperature_stats
    get_bs_voltage_stats
  end

  def get_bs_temperature_stats
    # AIRSPAN-ASMAX-COMMON-MIB::asMaxCmTemperatureMonitorTable
    # TODO
  end

  def get_bs_voltage_stats
    # AIRSPAN-ASMAX-COMMON-MIB::asMaxCmDcVoltageMonitorTable
    # TODO
  end

  def get_mobile_stations
    begin
      # ASMAX-ESTATS-MIB::asxEstatsRegisteredMs.1
      @nomobiles = snmp_get("1.3.6.1.4.1.989.1.16.2.9.5.1.1.1").to_i
    rescue Exception => e
      @nomobiles = 0
    end
    return unless @nomobiles > 0
    root = "1.3.6.1.4.1.989.1.16.2.9.6.1.1.1"
    snmp_get_multi(root) do |row|
      mac = row.name.index(root).map {|a| "%02x" % a}.join(":")
      aip = @auth.getIP(mac)
      if aip.nil? then
        debug "Denied unknown client: "+mac
      else
        @mobs.add(mac, aip[1], aip[0])
        debug "Client ["+mac+"] added to vlan "+aip[1]
      end
    end
  end

  def get_mobile_stats
    @mobs.each do |mac, ms|
      get_ms_stats(ms.snmp_mac)
    end
  end

  def get_ms_stats(mac)
    # ASMAX-ESTATS-MIB::asxEstatsActiveMsUlBytes.1.<MacAddr>
    uplink_bytes = snmp_get("1.3.6.1.4.1.989.1.16.2.9.6.1.1.1." + mac).to_i
    # ASMAX-ESTATS-MIB::asxEstatsActiveMsDlBytes.1.<MacAddr>
    downlink_bytes = snmp_get("1.3.6.1.4.1.989.1.16.2.9.6.1.2.1." + mac).to_i
    # ASMAX-ESTATS-MIB::asxEstatsMsDlRssi.1.<MacAddr>
    dl_rssi = snmp_get("1.3.6.1.4.1.989.1.16.2.9.2.1.1.1." + mac).to_i
    # ASMAX-ESTATS-MIB::asxEstatsMsDlCinr.1.<MacAddr>
    dl_cinr = snmp_get("1.3.6.1.4.1.989.1.16.2.9.2.1.12.1." + mac).to_i
    # ASMAX-ESTATS-MIB::asxEstatsMsUlRssi.1.<MacAddr>
    ul_rssi = snmp_get("1.3.6.1.4.1.989.1.16.2.9.2.1.2.1." + mac).to_i
    # ASMAX-ESTATS-MIB::asxEstatsMsUlCinr.1.<MacAddr>
    ul_cinr = snmp_get("1.3.6.1.4.1.989.1.16.2.9.2.1.5.1." + mac).to_i
    # ASMAX-ESTATS-MIB::asxEstatsMsUlTxPower.1.<MacAddr>
    ul_txpower = snmp_get("1.3.6.1.4.1.989.1.16.2.9.2.1.13.1." + mac).to_i
#    @meas.clstats(ma, mac, ul_rssi, ul_cinr, dl_rssi, dl_cinr, m.mcsulmod, m.mcs dlmod)
  end
end
