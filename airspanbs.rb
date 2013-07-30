require 'omf-aggmgr/ogs_wimaxrf/measurements'
require 'omf-aggmgr/ogs_wimaxrf/netdev'
require 'omf-aggmgr/ogs_wimaxrf/util'
require 'rufus/scheduler'

class AirBs < Netdev
  attr_reader :nomobiles, :serial, :tpsduul, :tppduul, :tpsdudl, :tppdud

  def initialize(mobs, bsconfig)
    super(bsconfig)

    @mobs = mobs
    @meas = Measurements.new(bsconfig['bsid'], bsconfig['stats'])
    @data_vlan = bsconfig['data_vlan']

    # Set frequency
    #snmp_set("wmanIf2BsCmnPhyDownlinkCenterFreq.1", bsconfig['frequency'])
    get_bs_main_params
    info("Airspan BS (Serial# #{@serial}) at #{@frequency} MHz and #{@power} dBm")

    debug("Creating trap handler")
    SNMP::TrapListener.new(:Host => "0.0.0.0") do |manager|
      # WMAN-IF2-BS-MIB::wmanif2BsSsRegisterTrap
      manager.on_trap("1.0.8802.16.2.1.1.2.0.5") do |trap|
        begin
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
            @mobs.on_client_registered(macaddr)
            @mobs.start(macaddr)
          elsif status == 2 # deregistration
            @mobs.on_client_deregistered(macaddr)
          else
            debug("Missing or invalid SsRegisterStatus in trap")
          end
        rescue => e
          error("Exception in trap handler: #{e.message}\n#{e.backtrace.join("\n\t")}")
        end
      end
      manager.on_trap_default do |trap|
        info("Received SNMP trap #{trap.inspect}")
      end
    end

    # ASMAX-AD-BRIDGE-MIB::asDot1adBsPortProvIngressFilterEnabled.4
    # Right now this is needed because the ingress filter is not set
    # so we need to shutdown the filter
    # TODO: setup of ingress filter
    snmp_set('1.3.6.1.4.1.989.1.16.5.4.2.3.1.2.4', 0)

    # FIXME: this should not be done here
    if @data_vlan && @data_vlan != 0
      create_vlan(@data_vlan)
    end

    # TODO: use of MacAddress for converting the address
    # handle already registered clients on startup
    root = "1.3.6.1.4.1.989.1.16.2.9.6.1.1.1"
    snmp_get_multi(root) do |row|
      mac = row.name.index(root).map { |a| "%02x" % a }.join(":")
      @mobs.on_client_registered(mac)
    end
    @mobs.start_all

    scheduler = Rufus::Scheduler.start_new
    # Local stats gathering
    scheduler.every "#{@meas.localinterval}s" do
      get_bs_stats
      get_mobile_stations
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
      get_bs_main_params
      get_bs_stats
      @meas.bsstats(@frequency, @power, @nomobiles, @tpsduul, @tppduul, @tpsdudl, @tppdudl)
    end
  end

  def on_client_added(client)
    add_station(MacAddress.hex2dec(client.macaddr)) unless @data_vlan == 0
  end

  def on_client_deleted(client)
    delete_station(MacAddress.hex2dec(client.macaddr)) unless @data_vlan == 0
  end

  private

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
    rescue
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

  def create_vlan(vlan)
    debug("Creating VLAN #{vlan} on internal bridge")
    # The following settings are contained in the SNMP table
    # ASMAX-AD-BRIDGE-MIB::asDot1adVlanProvTable (1.3.6.1.4.1.989.1.16.5.4.1.2)

    # ASMAX-AD-BRIDGE-MIB::asDot1adVlanProvRowStatus.<Vlan>
    # Valid values are: active(1), notInService(2), notReady(3),
    # createAndGo(4), createAndWait(5), destroy(6)
    snmp_set('1.3.6.1.4.1.989.1.16.5.4.1.2.1.12.' + vlan.to_s, 5) # createAndWait

    # ASMAX-AD-BRIDGE-MIB::asDot1adVlanProvFwdingDbid.<Vlan>
    # ID of the forwarding database for this vlan. Must not be 0. Is typically set to 1.
    snmp_set('1.3.6.1.4.1.989.1.16.5.4.1.2.1.2.' + vlan.to_s, 1)

    # ASMAX-AD-BRIDGE-MIB::asDot1adVlanProvSsToSsEnabled.<Vlan>
    # Is traffic allowed to flow directly between SS ports? (boolean)
    snmp_set('1.3.6.1.4.1.989.1.16.5.4.1.2.1.3.' + vlan.to_s, 1) # true

    # ASMAX-AD-BRIDGE-MIB::asDot1adVlanProvFloodUnknownEnabled.<Vlan>
    # Flood traffic with unknown destination? (boolean)
    snmp_set('1.3.6.1.4.1.989.1.16.5.4.1.2.1.4.' + vlan.to_s, 1) # true

    # ASMAX-AD-BRIDGE-MIB::asDot1adVlanProvBroadcastMode.<Vlan>
    # How to handle broadcast and multicast traffic in this vlan.
    #   0 -> send over a pair of multicast groups (tagged and untagged traffic)
    #   1 -> duplicate over unicast flows to every SS in the vlan
    #   2 -> drop
    snmp_set('1.3.6.1.4.1.989.1.16.5.4.1.2.1.5.' + vlan.to_s, 1)

    # ASMAX-AD-BRIDGE-MIB::asDot1adVlanProvUntaggedMcastSfid.<Vlan>
    # SFID of the multicast service flow provisioned for untagged broadcast/multicast traffic.
    # Unused since we set asDot1adVlanProvBroadcastMode to 1.
    #snmp_set('1.3.6.1.4.1.989.1.16.5.4.1.2.1.6.' + vlan.to_s, sfid)

    # ASMAX-AD-BRIDGE-MIB::asDot1adVlanProvTaggedMcastSfid.<Vlan>
    # SFID of the multicast service flow provisioned for tagged broadcast/multicast traffic.
    # Unused since we set asDot1adVlanProvBroadcastMode to 1.
    #snmp_set('1.3.6.1.4.1.989.1.16.5.4.1.2.1.7.' + vlan.to_s, sfid)

    # ASMAX-AD-BRIDGE-MIB::asDot1adVlanProvDhcpRelayAgentActive.<Vlan>
    #   0 -> off
    #   1 -> option 82 text
    #   2 -> option 82 binary
    snmp_set('1.3.6.1.4.1.989.1.16.5.4.1.2.1.8.' + vlan.to_s, 0)

    # ASMAX-AD-BRIDGE-MIB::asDot1adVlanProvMacForceForwardingEnabled.<Vlan>
    # Is the Mac Force Forwarding option enabled? (boolean)
    snmp_set('1.3.6.1.4.1.989.1.16.5.4.1.2.1.9.' + vlan.to_s, 0) # false

    # ASMAX-AD-BRIDGE-MIB::asDot1adVlanProvIpAddressType.<Vlan>
    # Specifies the type of IP address for all addresses configured for this vlan.
    #   0 -> unknown
    #   1 -> IPv4
    #   2 -> IPv6
    #snmp_set('1.3.6.1.4.1.989.1.16.5.4.1.2.1.10.' + vlan.to_s, 1)

    # ASMAX-AD-BRIDGE-MIB::asDot1adVlanProvEdgeRouterIpAddress.<Vlan>
    # IP address of the edge router used by the BS. Only relevant when Mac Force
    # Forwarding is enabled or when operating in IP Convergence Sublayer mode.
    #snmp_set('1.3.6.1.4.1.989.1.16.5.4.1.2.1.11.' + vlan.to_s, '')

    # ASMAX-AD-BRIDGE-MIB::asDot1adVlanProvArpSourceIpAddress.<Vlan>
    #snmp_set('1.3.6.1.4.1.989.1.16.5.4.1.2.1.13.' + vlan.to_s, '')

    # ASMAX-AD-BRIDGE-MIB::asDot1adVlanProvLocalIpAddress.<Vlan>
    #snmp_set('1.3.6.1.4.1.989.1.16.5.4.1.2.1.14.' + vlan.to_s, '')

    # ASMAX-AD-BRIDGE-MIB::asDot1adVlanProvLocalIpNetMask.<Vlan>
    #snmp_set('1.3.6.1.4.1.989.1.16.5.4.1.2.1.15.' + vlan.to_s, '')

    # ASMAX-AD-BRIDGE-MIB::asDot1adVlanProvBcastServiceClassIndex.<Vlan>
    # Defines Service Class to use for Broadcast Service Flows.
    #snmp_set('1.3.6.1.4.1.989.1.16.5.4.1.2.1.16.' + vlan.to_s, 3)

    # ASMAX-AD-BRIDGE-MIB::asDot1adVlanProvRowStatus.<Vlan>
    snmp_set('1.3.6.1.4.1.989.1.16.5.4.1.2.1.12.' + vlan.to_s, 1) # active
  end

  def delete_vlan(vlan)
    debug("Deleting VLAN #{vlan} from internal bridge")

    # ASMAX-AD-BRIDGE-MIB::asDot1adVlanProvRowStatus.<Vlan>
    snmp_set('1.3.6.1.4.1.989.1.16.5.4.1.2.1.12.' + vlan.to_s, 6) # destroy
  end

  def add_station(mac)
    # The following settings are contained in the SNMP table
    # ASMAX-AD-BRIDGE-MIB::asDot1adSsPortProvTable (1.3.6.1.4.1.989.1.16.5.4.2.1)

    # ASMAX-AD-BRIDGE-MIB::asDot1adSsPortProvRowStatus.1.<MacAddr>
    # Valid values are: active(1), notInService(2), notReady(3),
    # createAndGo(4), createAndWait(5), destroy(6)
    snmp_set('1.3.6.1.4.1.989.1.16.5.4.2.1.1.7.1.' + mac, 5) # createAndWait

    # ASMAX-AD-BRIDGE-MIB::asDot1adSsPortProvAdMode.1.<MacAddr>
    # Only relevant in "provider" (802.1ad) mode.
    #snmp_set('1.3.6.1.4.1.989.1.16.5.4.2.1.1.2.1.' + mac, 0)

    # ASMAX-AD-BRIDGE-MIB::asDot1adSsPortProvIngressFilterEnabled.1.<MacAddr>
    # When enabled, discards all incoming frames for vlans
    # that are not included in this port's egress vlan list.
    # TODO: we should make this work and enable it
    snmp_set('1.3.6.1.4.1.989.1.16.5.4.2.1.1.3.1.' + mac, 0) # false

    # ASMAX-AD-BRIDGE-MIB::asDot1adSsPortProvPvid.1.<MacAddr>
    # The PVID (Primary Vlan ID) of this port.
    snmp_set('1.3.6.1.4.1.989.1.16.5.4.2.1.1.4.1.' + mac, @data_vlan)

    # ASMAX-AD-BRIDGE-MIB::asDot1adSsPortProvUserPriority.1.<MacAddr>
    # The user priority of vlan-tagged traffic. We leave the default value.
    #snmp_set('1.3.6.1.4.1.989.1.16.5.4.2.1.1.5.1.' + mac, 0)

    # ASMAX-AD-BRIDGE-MIB::asDot1adSsPortProvAllowedFrameTypes.1.<MacAddr>
    # The frame types permitted on incoming traffic to this port.
    #   1 -> admit all
    #   2 -> admit only vlan-tagged
    #   3 -> admit only untagged
    snmp_set('1.3.6.1.4.1.989.1.16.5.4.2.1.1.6.1.' + mac, 1)

    # ASMAX-AD-BRIDGE-MIB::asDot1adSsPortProvQinqSupported.1.<MacAddr>
    # Is Q-in-Q supported for this SS? (boolean)
    snmp_set('1.3.6.1.4.1.989.1.16.5.4.2.1.1.8.1.' + mac, 0) # false

    # ASMAX-AD-BRIDGE-MIB::asDot1adSsPortProvSTagVlan.1.<MacAddr>
    #snmp_set('1.3.6.1.4.1.989.1.16.5.4.2.1.1.9.1.' + mac, 0)

    # ASMAX-AD-BRIDGE-MIB::asDot1adSsPortProvUseCTagPriority.1.<MacAddr>
    #snmp_set('1.3.6.1.4.1.989.1.16.5.4.2.1.1.10.1.' + mac, 1) # true

    # ASMAX-AD-BRIDGE-MIB::asDot1adSsPortProvsTagPriority.1.<MacAddr>
    #snmp_set('1.3.6.1.4.1.989.1.16.5.4.2.1.1.11.1.' + mac, 0)

    # ASMAX-AD-BRIDGE-MIB::asDot1adSsPortProvRowStatus.1.<MacAddr>
    snmp_set('1.3.6.1.4.1.989.1.16.5.4.2.1.1.7.1.' + mac, 1) # active

    # The following settings are contained in the SNMP table
    # ASMAX-AD-BRIDGE-MIB::asDot1adSsPortVlanListTable (1.3.6.1.4.1.989.1.16.5.4.2.2)

    # ASMAX-AD-BRIDGE-MIB::asDot1adSsPortVlanListRowStatus.1.<MacAddr>.<Vlan>
    # Valid values are: active(1), notInService(2), notReady(3),
    # createAndGo(4), createAndWait(5), destroy(6)
    snmp_set('1.3.6.1.4.1.989.1.16.5.4.2.2.1.4.1.' + mac + '.' + @data_vlan.to_s, 5) # createAndWait

    # ASMAX-AD-BRIDGE-MIB::asDot1adSsPortVlanListUntagged.1.<MacAddr>.<Vlan>
    # Determines whether frames are untagged on egress. (boolean)
    snmp_set('1.3.6.1.4.1.989.1.16.5.4.2.2.1.3.1.' + mac + '.' + @data_vlan.to_s, 0) # false

    # ASMAX-AD-BRIDGE-MIB::asDot1adSsPortVlanListRowStatus.1.<MacAddr>.<Vlan>
    snmp_set('1.3.6.1.4.1.989.1.16.5.4.2.2.1.4.1.' + mac + '.' + @data_vlan.to_s, 1) # active
  end

  def delete_station(mac)
    # ASMAX-AD-BRIDGE-MIB::asDot1adSsPortVlanListRowStatus.1.<MacAddr>.<Vlan>
    snmp_set('1.3.6.1.4.1.989.1.16.5.4.2.2.1.4.1.' + mac + '.' + @data_vlan.to_s, 6) # destroy

    # ASMAX-AD-BRIDGE-MIB::asDot1adSsPortProvRowStatus.1.<MacAddr>
    snmp_set('1.3.6.1.4.1.989.1.16.5.4.2.1.1.7.1.' + mac, 6) # destroy
  end

end
