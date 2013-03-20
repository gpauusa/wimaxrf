require 'socket'
require 'omf-aggmgr/ogs_wimaxrf/client'
require 'omf-aggmgr/ogs_wimaxrf/mobileClients'
require 'omf-aggmgr/ogs_wimaxrf/netdev'
require 'omf-aggmgr/ogs_wimaxrf/circularBuffer'
require 'omf-aggmgr/ogs_wimaxrf/dpClick1'
require 'omf-aggmgr/ogs_wimaxrf/dpOpenflow'
require 'omf-aggmgr/ogs_wimaxrf/authenticator'
require 'omf-aggmgr/ogs_wimaxrf/oml4r.rb'
require 'rufus/scheduler'


class ClStat < OML4R::MPBase
  version "01"
  name  :client
  param :ma
  param :mac
  param :ulrssi, :type => :double
  param :ulcinr, :type => :double
  param :dlrssi, :type => :double
  param :dlcinr, :type => :double
  param :mcsulmod
  param :mcsdlmod
end

class BSStat < OML4R::MPBase
  version "02"
  name  :bs
  param :frequency, :type => :double
  param :power, :type => :double
  param :noclient
  param :ulsdu, :type => :double
  param :ulpdu, :type => :double
  param :dlsdu, :type => :double
  param :dlpdu, :type => :double
end

EXTRA_AIR_MODULES = []
#                   ["AIRSPAN-ASMAX-COMMON-MIB",
#                    "ASMAX-EBS-MIB", "ASMAX-ESTATS-MIB",
#                    "WMAN-DEV-MIB", "WMAN-IF2-BS-MIB"]

class AirBs < Netdev
  attr_reader :nomobiles, :serial, :tpsduul, :tppduul, :tpsdudl, :tppdud
  attr_accessor :dp, :auth
  attr_reader :asnHost, :sndPort, :rcvPort

  attr_reader :localoml, :globaloml

  OMLNAME1 = "wimax_clients#{ClStat.get_ver}"
  OMLFILE1 = "/var/log/#{OMLNAME1}.dat"
  OMLNAME2 = "wimax_bss#{BSStat.get_ver}"
  OMLFILE2 = "/var/log/#{OMLNAME2}.dat"

  def initialize(dp, auth, bsconfig, asnconfig)
    debug("initialize")
    @localoml = nil
    @globaloml = nil
    @dp = dp
    @asnHost = asnconfig['asnip'] || 'localhost'
    nID = bsconfig['bsid'] || Socket.gethostname
    oml_opts1 = { :expID => OMLNAME1, :appID => OMLNAME1, :nodeID => nID, :omlFile => OMLFILE1 }
    @localomlfile = OML4R::Oml4r.new(nil,oml_opts1)
    oml_opts2 = { :expID => OMLNAME2, :appID => OMLNAME2, :nodeID => nID, :omlFile => OMLFILE2 }
    @globalomlfile = OML4R::Oml4r.new(nil,oml_opts2)
    if !bsconfig['localoml'].nil?
      oml_opts1[:omlPort] = "3003"
      oml_opts1.merge!(bsconfig['localoml'])
      @localinterval = bsconfig['localoml']['interval'] || 10
      begin
        @localoml = OML4R::Oml4r.new(nil,oml_opts1)
        debug("Send client stats with APP_ID=#{@localoml.appID} node=#{@localoml.nodeID} server:#{@localoml.omlServer} every #{@localinterval} sec.")
        ClStat.attach(@localoml)
      rescue Exception => ex
        debug("Failed to connect with local OML: #{oml_opts1}\n#{ex}")
        @localoml = nil
      end
    end
    if !bsconfig['globaloml'].nil?
      oml_opts2[:omlPort] = "3003"
      oml_opts2.merge!(bsconfig['globaloml'])
      @globalinterval = bsconfig['globaloml']['interval'] || 300
      begin
        @globaloml = OML4R::Oml4r.new(nil,oml_opts2)
        debug("Send global BS stats with APP_ID=#{@globaloml.appID} node=#{@globaloml.nodeID} server:#{@globaloml.omlServer} every #{@globalinterval} sec." )
        BSStat.attach(@globaloml)
      rescue Exception => ex
        debug("Failed to connect with global OML: #{oml_opts2}\n#{ex}")
        @globaloml = nil
      end
    end

    @auth = auth
    super(bsconfig)

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
    scheduler.every "#{@localinterval}s" do
      debug("Local BS Data collection")
      get_mobile_stations
      debug("Found #{@nomobiles} mobiles")
      get_bs_stats
      debug("Checking mobile stats...")
      get_mobile_stats
      debug("...done")
    end
    scheduler.every "#{@globalinterval}s" do
      unless @globaloml.nil?
        debug("Global BS Data collection")
        get_bs_main_params
        # TODO: global data stats
        BSStat.inject(@frequency, @power, @nomobiles, @tpsduul, @tppduul, @tpsdudl, @tppdudl)
      end
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
      unless @localoml.nil?
        get_ms_data_stats(ms.snmp_mac)
        get_ms_rf_stats(ms.snmp_mac)
        # TODO ClStat.inject(...)
      end
    end
  end

  def get_ms_data_stats(mac)
    # ASMAX-ESTATS-MIB::asxEstatsActiveMsUlBytes.1.<MacAddr>
    uplink_bytes = snmp_get("1.3.6.1.4.1.989.1.16.2.9.6.1.1.1." + mac).to_i
    # ASMAX-ESTATS-MIB::asxEstatsActiveMsDlBytes.1.<MacAddr>
    downlink_bytes = snmp_get("1.3.6.1.4.1.989.1.16.2.9.6.1.2.1." + mac).to_i
  end

  def get_ms_rf_stats(mac)
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
  end
end
