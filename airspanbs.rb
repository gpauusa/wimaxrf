require 'omf-aggmgr/ogs_wimaxrf/client'
require 'omf-aggmgr/ogs_wimaxrf/mobileClients'
require 'omf-aggmgr/ogs_wimaxrf/netdev'
require 'omf-aggmgr/ogs_wimaxrf/authenticator'
require 'omf-aggmgr/ogs_wimaxrf/measurements'
require 'omf-aggmgr/ogs_wimaxrf/util'
require 'rufus/scheduler'

EXTRA_AIR_MODULES = []
#                   ["AIRSPAN-ASMAX-COMMON-MIB", "ASMAX-AD-BRIDGE-MIB",
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
    @data_vlan = bsconfig['data_vlan']

    EXTRA_AIR_MODULES.each { |mod|
      add_snmp_module(mod)
    }

    # Set frequency
    #snmp_set("wmanIf2BsCmnPhyDownlinkCenterFreq.1", 2572000)
    get_bs_main_params()
    info("Airspan BS (Serial# #{@serial}) at #{@frequency} MHz and #{@power} dBm")

    debug("Creating trap handler")
    SNMP::TrapListener.new(:Host => "0.0.0.0") do |manager|
      # WMAN-IF2-BS-MIB::wmanif2BsSsRegisterTrap
      manager.on_trap("1.0.8802.16.2.1.1.2.0.5") do |trap|
        debug("Received wmanif2BsSsRegisterTrap: #{trap.inspect}")
        macaddr = nil
        status = nil
        trap.each_varbind do |vb|
          # WMAN-IF2-BS-MIB::wmanif2BsSsNotificationMacAddr
          if vb.name.to_s == "1.0.8802.16.2.1.1.2.1.1.1"
            macaddr = MacAddress.bin2hex(vb.value)
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
      manager.on_trap_default do |trap|
        info("Received SNMP trap #{trap.inspect}")
      end
    end

    # TODO: check if wimaxrf should put up this interface
    # setting data vlan on the BS
    if @data_vlan && @data_vlan != 0
      add_vlan_bs(@data_vlan)
      debug("Creating VLAN #{bsconfig['data_interface']}.#{@data_vlan}")
      cmd = "ip link add link #{bsconfig['data_interface']} name #{bsconfig['data_interface']}.#{@data_vlan} type vlan id #{@data_vlan}"
      if not system(cmd)
        debug("Could not create VLAN: command '#{cmd}' failed with status #{$?.exitstatus}")
      end
      cmd = "ip link set #{bsconfig['data_interface']}.#{@data_vlan} up"
      if not system(cmd)
        return "Could not bring interface up: command '#{cmd}' failed with status #{$?.exitstatus}"
      end
    end

    # TODO: use of MacAddress for converting the address
    # handle already registered clients on startup
    root = "1.3.6.1.4.1.989.1.16.2.9.6.1.1.1"
    snmp_get_multi(root) do |row|
      mac = row.name.index(root).map { |a| "%02x" % a }.join(":")
      create_ms_datapath(mac)
    end

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
      @mobs.start(mac)
    end
  end

  def delete_ms_datapath(mac)
    if @mobs.has_mac?(mac) then
      @mobs.delete(mac)
      @mobs.start(mac)
      debug "Client [#{mac}] deleted"
    else
      debug "Client [#{mac}] is not registered"
    end
  end

  # Send a group of set requests to the airspan BS to create a new vlan
  def add_vlan_bs(vlan)
    debug("Start setup of #{vlan} on the Airspan BS")
    # Vlan settings, hardcoded, usefull setting have comments for eventual modification
    # ASMAX-AD-BRIDGE-MIB::asDot1adSsVlanProvRowStatus.<Vlan> 5==CreateAndWait 6==Destroy 1==active vlan 2==notinservice
    snmp_set('1.3.6.1.4.1.989.1.16.5.4.1.2.1.12.' + vlan.to_s, 5)
    # ASMAX-AD-BRIDGE-MIB::asDot1adVlanProvFwdingDbid.<Vlan>
    snmp_set('1.3.6.1.4.1.989.1.16.5.4.1.2.1.2.' + vlan.to_s, 1)
    # ASMAX-AD-BRIDGE-MIB::asDot1adVlanProvSsToSsEnabled.<Vlan>
    snmp_set('1.3.6.1.4.1.989.1.16.5.4.1.2.1.3.' + vlan.to_s, 1)  # mac forced forwarding 0 = unchecked 1= checked
    # ASMAX-AD-BRIDGE-MIB::asDot1adVlanProvFloodUnknownEnabled.<Vlan>
    snmp_set('1.3.6.1.4.1.989.1.16.5.4.1.2.1.4.' + vlan.to_s, 1)   # 1==enabled 0 disabled
    # ASMAX-AD-BRIDGE-MIB::asDot1adVlanProvBroadcastMode.<Vlan>
    snmp_set('1.3.6.1.4.1.989.1.16.5.4.1.2.1.5.' + vlan.to_s, 1)  # 0==Multicast Group 1==Duplicate 2==drop
    # ASMAX-AD-BRIDGE-MIB::asDot1adVlanProvUntaggedMcastSfid.<Vlan>
    snmp_set('1.3.6.1.4.1.989.1.16.5.4.1.2.1.6.' + vlan.to_s, 4294959122) # FIXME: this and the next values are autogenerated and incremental nonetheless seems useless for now and not having big impact
    # ASMAX-AD-BRIDGE-MIB::asDot1adVlanProvTaggedMcastSfid.<Vlan>
    snmp_set('1.3.6.1.4.1.989.1.16.5.4.1.2.1.7.' + vlan.to_s, 4294959123)
    # ASMAX-AD-BRIDGE-MIB::asDot1adVlanProvDhcpRelayAgentActive.<Vlan>
    snmp_set('1.3.6.1.4.1.989.1.16.5.4.1.2.1.8.' + vlan.to_s, 0)  # 0==off, 1==option 82 text, 2 option 82 binary
    # ASMAX-AD-BRIDGE-MIB::asDot1adVlanProvMacForceForwardingEnabled.<Vlan>
    snmp_set('1.3.6.1.4.1.989.1.16.5.4.1.2.1.9.' + vlan.to_s, 0) # values 1/0 on/off
    # ASMAX-AD-BRIDGE-MIB::asDot1adVlanProvIpAddressType.<Vlan>
    snmp_set('1.3.6.1.4.1.989.1.16.5.4.1.2.1.10.' + vlan.to_s, 1) # dunno probably something to do with edgerouteripaddress
    # ASMAX-AD-BRIDGE-MIB::asDot1adVlanProvEdgeRouterIpAddress.<Vlan>
    snmp_set('1.3.6.1.4.1.989.1.16.5.4.1.2.1.11.' + vlan.to_s, 00000000) # undotted hex format
    # ASMAX-AD-BRIDGE-MIB::asDot1adVlanProvBcastServiceClassIndex.<Vlan>
    snmp_set('1.3.6.1.4.1.989.1.16.5.4.1.2.1.16.' + vlan.to_s, 3)
    # ASMAX-AD-BRIDGE-MIB::asDot1adSsVlanProvRowStatus.<Vlan> 5==CreateAndWait 6==Destroy 1==active vlan 2==notinservice
    snmp_set('1.3.6.1.4.1.989.1.16.5.4.1.2.1.12.' + vlan.to_s, 1)
  end

  # delete a vlan from the airspan BS
  def delete_vlan_bs(vlan)
    debug("Removing vlan #{vlan} from Airspan BS")
    # ASMAX-AD-BRIDGE-MIB::asDot1adSsVlanProvRowStatus.<Vlan> 5==CreateAndWait 6==Destroy 1==active vlan 2==notinservice
    snmp_set('1.3.6.1.4.1.989.1.16.5.4.1.2.1.12.' + vlan.to_s, 6)
  end

  # Send a group of set requests to add a new station to the airspan BS
  def add_new_station_bs(mac)
    debug("Adding a new Station to the Airspan BS")
    # Settings for the SSs most of them are harcoded
    # ASMAX-AD-BRIDGE-MIB::asDot1adSSPortProvRowStatus.1.<MacAddr> 5==CreateAndWait 6==Destroy 1==active vlan 2==notinservice 4==CreateAndGo
    snmp_set('1.3.6.1.4.1.989.1.16.5.4.2.1.1.7.1.' + mac, 4)
    # ASMAX-AD-BRIDGE-MIB::asDot1adSsPortProvIngressFilterEnabled.1.<MacAddr>
    snmp_set('1.3.6.1.4.1.989.1.16.5.4.2.1.1.3.1.' + mac, 0) # ingress filtering enabled 0/1 TODO: find a way to configure the bs to have this enabled and working
    # ASMAX-AD-BRIDGE-MIB::asDot1adSsPortProvPvid.1.<MacAddr>
    snmp_set('1.3.6.1.4.1.989.1.16.5.4.2.1.1.4.1.' + mac, @data_vlan)
    # ASMAX-AD-BRIDGE-MIB::asDot1adSsPortProvUserPriority.1.<MacAddr>
    snmp_set('1.3.6.1.4.1.989.1.16.5.4.2.1.1.5.1.' + mac, 0) # default priority (int)
    # ASMAX-AD-BRIDGE-MIB::asDot1adSsPortProvAllowedFrameTypes.1.<MacAddr>
    snmp_set('1.3.6.1.4.1.989.1.16.5.4.2.1.1.6.1.' + mac, 1) # allowed Frame types 0==not set 1==tagged&untagged 2==tagged 3==untagged
    # ASMAX-AD-BRIDGE-MIB::asDot1adSsPortProvQinqSupported.1.<MacAddr>
    snmp_set('1.3.6.1.4.1.989.1.16.5.4.2.1.1.8.1.' + mac, 0) # Q-in-Q supported 0 == no 1== yes
    # ASMAX-AD-BRIDGE-MIB::asDot1adSsPortProvSTagVlan.1.<MacAddr>
    snmp_set('1.3.6.1.4.1.989.1.16.5.4.2.1.1.9.1.' + mac, 1) # Tag frames
    # ASMAX-AD-BRIDGE-MIB::asDot1adSsPortProvUseCTagPriority.1.<MacAddr>
    snmp_set('1.3.6.1.4.1.989.1.16.5.4.2.1.1.10.1.' + mac, 1)
    # ASMAX-AD-BRIDGE-MIB::asDot1adSsPortProvsTagPriority.1.<MacAddr>
    snmp_set('1.3.6.1.4.1.989.1.16.5.4.2.1.1.11.1.' + mac, 0) # int
    # ASMAX-AD-BRIDGE-MIB::asDot1adSSPortProvRowStatus.1.<MacAddr> 5==CreateAndWait 6==Destroy 1==active vlan 2==notinservice
    snmp_set('1.3.6.1.4.1.989.1.16.5.4.2.1.1.7.1.' + mac, 1)
    # Setting of the vlan for a station (tagged/untagged)
    # ASMAX-AD-BRIDGE-MIB::asDot1adSSPortVlanListRowStatus.1.<MacAddr>.<Vlan>
    snmp_set('1.3.6.1.4.1.989.1.16.5.4.2.2.1.4.1.' + mac + "." + @data_vlan.to_s, 5)
    # ASMAX-AD-BRIDGE-MIB::asDot1adSSPortVlanListUntagged.1.<MacAddr>.<Vlan>
    snmp_set('1.3.6.1.4.1.989.1.16.5.4.2.2.1.3.1.' + mac + "." + @data_vlan.to_s, 0) # tagged/untagged 0/1
    # ASMAX-AD-BRIDGE-MIB::asDot1adSSPortVlanListRowStatus.1.<MacAddr>.<Vlan>
    snmp_set('1.3.6.1.4.1.989.1.16.5.4.2.2.1.4.1.' + mac + "." + @data_vlan.to_s, 1)
  end

  # delete a Station from the airspan bs
  def delete_station_bs(mac)
    debug("Removing a Station from the Airspan BS")
    # ASMAX-AD-BRIDGE-MIB::asDot1adSSPortProvRowStatus.1.<MacAddr> 5==CreateAndWait 6==Destroy 1==active vlan 2==notinservice
    snmp_set('1.3.6.1.4.1.989.1.16.5.4.2.1.1.7.1.' + mac, 6)
    # ASMAX-AD-BRIDGE-MIB::asDot1adSSPortVlanListRowStatus.1.<MacAddr>.<Vlan>
    snmp_set('1.3.6.1.4.1.989.1.16.5.4.2.2.1.4.1.' + mac + "." + @data_vlan.to_s, 6)
  end

end
