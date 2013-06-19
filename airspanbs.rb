require 'omf-aggmgr/ogs_wimaxrf/client'
require 'omf-aggmgr/ogs_wimaxrf/mobileClients'
require 'omf-aggmgr/ogs_wimaxrf/netdev'
require 'omf-aggmgr/ogs_wimaxrf/circularBuffer'
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

  def initialize(dp, auth, bsconfig, asnconfig)
    super(bsconfig)

    @dp = dp
    @auth = auth
    @meas = Measurements.new(bsconfig['bsid'], bsconfig['stats'])
    @mobs = MobileClients.new(@dp)

    EXTRA_AIR_MODULES.each { |mod|
      add_snmp_module(mod)
    }

    # Set frequency
    #snmp_set("wmanIf2BsCmnPhyDownlinkCenterFreq.1", 2572000)
    get_bs_main_params()
    info("Airspan BS (Serial# #{@serial}) at #{@frequency} MHz and #{@power} dBm")

    debug("Creating trap handler")
    SNMP::TrapListener.new(:Host => "0.0.0.0") do |manager|
      # Handle traps for client (de)registration
      # WMAN-IF2-BS-MIB::wmanif2BsSsRegisterTrap
      manager.on_trap("1.0.8802.16.2.1.1.2.0.5") do |trap|
        debug("Received wmanif2BsSsRegisterTrap: #{trap.inspect}")
        macaddr = nil
        status = nil
        trap.each_varbind do |vb|
          # WMAN-IF2-BS-MIB::wmanif2BsSsNotificationMacAddr
          if vb.name.to_s == "1.0.8802.16.2.1.1.2.1.1.1"
            macaddr = arr_to_hex_mac(vb.value)
          # WMAN-IF2-BS-MIB::wmanIf2BsSsRegisterStatus
          elsif vb.name.to_s == "1.0.8802.16.2.1.1.2.1.1.8"
            status = vb.value.to_i
          end
        end
        if macaddr.nil?
          debug("Missing SsNotificationMacAddr in trap")
        elsif status == 1 # registration
          create_ms_datapath(macaddr)
        elsif status == 2 # deregistration
          delete_ms_datapath(macaddr)
        else
          debug("Missing or invalid SsRegisterStatus in trap")
        end
      end
    end

    # TODO: handle already registered clients on startup
    #root = "1.3.6.1.4.1.989.1.16.2.9.6.1.1.1"
    #snmp_get_multi(root) do |row|
    #  mac = row.name.index(root).map { |a| "%02x" % a }.join(":")
    #  create_ms_datapath(mac)
    #end

    scheduler = Rufus::Scheduler.start_new
    # Local stats gathering
    scheduler.every "#{@meas.localinterval}s" do
      get_bs_stats()
      get_mobile_stations()
      debug("Found #{@nomobiles} mobiles")
      debug("Checking mobile stats...")
      @mobs.each do |mac, ms|
        get_ms_stats(ms.snmp_mac)
      end
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
    get_bs_temperature_stats()
    get_bs_voltage_stats()
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
#    @meas.clstats(ma, mac, ul_rssi, ul_cinr, dl_rssi, dl_cinr, m.mcsulmod, m.mcsdlmod)
  end

  def create_ms_datapath(mac)
    client = @auth.get(mac)
    if client.nil? then
      debug "Denied unknown client [#{mac}]"
    else
      @mobs.add(mac, client.dpname, client.ipaddress)
      debug "Client [#{mac}] added to datapath #{client.dpname}"
    end
  end

  def delete_ms_datapath(mac)
    if @mobs.has_mac?(mac) then
      @mobs.delete(mac)
      debug "Client [#{mac}] deleted"
    else
      debug "Client [#{mac}] is not registered"
    end
  end
end
