require 'rufus/scheduler'
require 'snmp'
require 'omf-aggmgr/ogs_wimaxrf/airspanbsparams'
require 'omf-aggmgr/ogs_wimaxrf/bs'
require 'omf-aggmgr/ogs_wimaxrf/measurements'
require 'omf-aggmgr/ogs_wimaxrf/util'

class AirspanBs < Bs
  attr_reader :serial, :tpsduul, :tppduul, :tpsdudl, :tppdud

  PARAMS_CLASSES = ['ArqService', 'HarqService', 'MobileService',
    'SecurityService', 'ZoneService', 'WirelessService']

  def initialize(mobs, bsconfig)
    super(bsconfig)

    @data_vlan = 0
    @mobs = mobs
    @meas = Measurements.new(bsconfig['bsid'], bsconfig['stats'])

    # Set initial frequency
    # WMAN-IF2-BS-MIB::wmanIf2BsCmnPhyDownlinkCenterFreq.1
    snmp_set("1.0.8802.16.2.1.2.9.1.2.1.6.1", bsconfig['frequency']) # in kHz

    get_bs_main_params
    info("Airspan BS (Serial# #{@serial}) at #{@frequency} MHz and #{@power} dBm")

    debug("Creating SNMP trap listener")
    SNMP::TrapListener.new(:Host => "0.0.0.0") do |manager|
      # SNMPv2-MIB::coldStart
      manager.on_trap("1.3.6.1.6.3.1.1.5.1") do |trap|
        next unless trap.source_ip == bsconfig['ip']
        info("Base station restarted")
      end
      # AIRSPAN-ASMAX-BS-COMMON-MIB::asMaxBsCmGpsLockChangeTrap
      manager.on_trap("1.3.6.1.4.1.989.1.16.2.1.2.0.2") do |trap|
        next unless trap.source_ip == bsconfig['ip']
        msg = "unknown GPS lock status"
        trap.each_varbind do |vb|
          # AIRSPAN-ASMAX-BS-COMMON-MIB::asMaxBsCmGpsTrapStatusGpsLock
          #   0 -> locked
          #   1 -> lock lost (degraded)
          #   2 -> lock lost (expired)
          if vb.name.to_s == "1.3.6.1.4.1.989.1.16.2.1.2.2.1.3"
            if vb.value.to_i == 0
              msg = "GPS locked"
            else
              msg = "GPS lock lost"
            end
          end
        end
        info("Received asMaxBsCmGpsLockChangeTrap: #{msg}")
      end
      # WMAN-IF2-BS-MIB::wmanif2BsSsRegisterTrap
      manager.on_trap("1.0.8802.16.2.1.1.2.0.5") do |trap|
        next unless trap.source_ip == bsconfig['ip']
        begin
          info("Received wmanif2BsSsRegisterTrap")
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
          error("Exception in trap handler: #{e.message}\n\t#{e.backtrace.join("\n\t")}")
        end
      end
      manager.on_trap_default do |trap|
        debug("Received SNMP trap #{trap.inspect}")
      end
    end

    # Right now this is needed because the ingress filter is not set
    # so we need to shutdown the filter
    # TODO: setup of ingress filter
    # ASMAX-AD-BRIDGE-MIB::asDot1adBsPortProvIngressFilterEnabled.4
    snmp_set("1.3.6.1.4.1.989.1.16.5.4.2.3.1.2.4", 0) # false

    # Handle already registered clients on startup
    # ASMAX-ESTATS-MIB::asxEstatsActiveMsUlBytes.1
    root = "1.3.6.1.4.1.989.1.16.2.9.6.1.1.1"
    snmp_get_multi(root) do |row|
      mac = MacAddress.arr2hex(row.name.index(root))
      @mobs.on_client_registered(mac)
    end
    @mobs.start_all

    # Local stats gathering
    Rufus::Scheduler.singleton.every "#{@meas.localinterval}s", :overlap => false do
      get_bs_stats
      # ASMAX-ESTATS-MIB::asxEstatsRegisteredMs.1
      registered_ms = begin snmp_get("1.3.6.1.4.1.989.1.16.2.9.5.1.1.1").to_i rescue 0 end
      debug("Found #{registered_ms} registered mobiles (#{@mobs.length} authorized + #{registered_ms - @mobs.length} unauthorized)")
      debug("Collecting stats...")
      @mobs.each do |mac, ms|
        get_ms_stats(ms.snmp_mac)
      end
      debug("...done")
    end
    # Global stats gathering
    Rufus::Scheduler.singleton.every "#{@meas.globalinterval}s", :overlap => false do
      debug("Global BS data collection")
      get_bs_main_params
      get_bs_stats
      @meas.bsstats(@frequency, @power, @mobs.length, @tpsduul, @tppduul, @tpsdudl, @tppdudl)
    end
  end

  def on_client_added(client)
    add_station(MacAddress.hex2dec(client.macaddr)) unless @data_vlan == 0
  end

  def on_client_deleted(client)
    delete_station(MacAddress.hex2dec(client.macaddr))
  end

  def create_vlan(vlan)
    debug("Creating VLAN #{vlan} on internal bridge")
    @data_vlan = vlan
    # The following settings are contained in the SNMP table
    # ASMAX-AD-BRIDGE-MIB::asDot1adVlanProvTable (1.3.6.1.4.1.989.1.16.5.4.1.2)

    # ASMAX-AD-BRIDGE-MIB::asDot1adVlanProvRowStatus.<Vlan>
    # Valid values are: active(1), notInService(2), notReady(3),
    # createAndGo(4), createAndWait(5), destroy(6)
    snmp_set("1.3.6.1.4.1.989.1.16.5.4.1.2.1.12.#{vlan}", 5) # createAndWait

    # ASMAX-AD-BRIDGE-MIB::asDot1adVlanProvFwdingDbid.<Vlan>
    # ID of the forwarding database for this vlan. Must not be 0. Is typically set to 1.
    snmp_set("1.3.6.1.4.1.989.1.16.5.4.1.2.1.2.#{vlan}", 1)

    # ASMAX-AD-BRIDGE-MIB::asDot1adVlanProvSsToSsEnabled.<Vlan>
    # Is traffic allowed to flow directly between SS ports? (boolean)
    snmp_set("1.3.6.1.4.1.989.1.16.5.4.1.2.1.3.#{vlan}", 1) # true

    # ASMAX-AD-BRIDGE-MIB::asDot1adVlanProvFloodUnknownEnabled.<Vlan>
    # Flood traffic with unknown destination? (boolean)
    snmp_set("1.3.6.1.4.1.989.1.16.5.4.1.2.1.4.#{vlan}", 1) # true

    # ASMAX-AD-BRIDGE-MIB::asDot1adVlanProvBroadcastMode.<Vlan>
    # How to handle broadcast and multicast traffic in this vlan.
    #   0 -> send over a pair of multicast groups (tagged and untagged traffic)
    #   1 -> duplicate over unicast flows to every SS in the vlan
    #   2 -> drop
    snmp_set("1.3.6.1.4.1.989.1.16.5.4.1.2.1.5.#{vlan}", 1)

    # ASMAX-AD-BRIDGE-MIB::asDot1adVlanProvUntaggedMcastSfid.<Vlan>
    # SFID of the multicast service flow provisioned for untagged broadcast/multicast traffic.
    # Unused since we set asDot1adVlanProvBroadcastMode to 1.
    #snmp_set("1.3.6.1.4.1.989.1.16.5.4.1.2.1.6.#{vlan}", sfid)

    # ASMAX-AD-BRIDGE-MIB::asDot1adVlanProvTaggedMcastSfid.<Vlan>
    # SFID of the multicast service flow provisioned for tagged broadcast/multicast traffic.
    # Unused since we set asDot1adVlanProvBroadcastMode to 1.
    #snmp_set("1.3.6.1.4.1.989.1.16.5.4.1.2.1.7.#{vlan}", sfid)

    # ASMAX-AD-BRIDGE-MIB::asDot1adVlanProvDhcpRelayAgentActive.<Vlan>
    #   0 -> off
    #   1 -> option 82 text
    #   2 -> option 82 binary
    snmp_set("1.3.6.1.4.1.989.1.16.5.4.1.2.1.8.#{vlan}", 0)

    # ASMAX-AD-BRIDGE-MIB::asDot1adVlanProvMacForceForwardingEnabled.<Vlan>
    # Is the Mac Force Forwarding option enabled? (boolean)
    snmp_set("1.3.6.1.4.1.989.1.16.5.4.1.2.1.9.#{vlan}", 0) # false

    # ASMAX-AD-BRIDGE-MIB::asDot1adVlanProvIpAddressType.<Vlan>
    # Specifies the type of IP address for all addresses configured for this vlan.
    #   0 -> unknown
    #   1 -> IPv4
    #   2 -> IPv6
    #snmp_set("1.3.6.1.4.1.989.1.16.5.4.1.2.1.10.#{vlan}", 1)

    # ASMAX-AD-BRIDGE-MIB::asDot1adVlanProvEdgeRouterIpAddress.<Vlan>
    # IP address of the edge router used by the BS. Only relevant when Mac Force
    # Forwarding is enabled or when operating in IP Convergence Sublayer mode.
    #snmp_set("1.3.6.1.4.1.989.1.16.5.4.1.2.1.11.#{vlan}", '')

    # ASMAX-AD-BRIDGE-MIB::asDot1adVlanProvArpSourceIpAddress.<Vlan>
    #snmp_set("1.3.6.1.4.1.989.1.16.5.4.1.2.1.13.#{vlan}", '')

    # ASMAX-AD-BRIDGE-MIB::asDot1adVlanProvLocalIpAddress.<Vlan>
    #snmp_set("1.3.6.1.4.1.989.1.16.5.4.1.2.1.14.#{vlan}", '')

    # ASMAX-AD-BRIDGE-MIB::asDot1adVlanProvLocalIpNetMask.<Vlan>
    #snmp_set("1.3.6.1.4.1.989.1.16.5.4.1.2.1.15.#{vlan}", '')

    # ASMAX-AD-BRIDGE-MIB::asDot1adVlanProvBcastServiceClassIndex.<Vlan>
    # Defines Service Class to use for Broadcast Service Flows.
    #snmp_set("1.3.6.1.4.1.989.1.16.5.4.1.2.1.16.#{vlan}", 3)

    # ASMAX-AD-BRIDGE-MIB::asDot1adVlanProvRowStatus.<Vlan>
    snmp_set("1.3.6.1.4.1.989.1.16.5.4.1.2.1.12.#{vlan}", 1) # active
  end

  def delete_vlan(vlan)
    debug("Deleting VLAN #{vlan} from internal bridge")

    # ASMAX-AD-BRIDGE-MIB::asDot1adVlanProvRowStatus.<Vlan>
    snmp_set("1.3.6.1.4.1.989.1.16.5.4.1.2.1.12.#{vlan}", 6) # destroy
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
    # ASMAX-EBS-MIB::asxEbsBsStatusOperationalStatus.1
    #   0 -> none/unknown
    #   1 -> in service
    #   2 -> out of service
    #   3 -> maintenance
    snmp_get("1.3.6.1.4.1.989.1.16.2.7.4.2.1.1.1").to_i
  end

  def get_bs_stats
    get_bs_temperature_stats
    get_bs_voltage_stats
  end

  def get_bs_temperature_stats
    # AIRSPAN-ASMAX-COMMON-MIB::asMaxCmTemperatureMonitorTable
    #  - temp is in Celsius degrees
    #  - status can be: normal(0), tooHigh(1), tooLow(2)

    cpu_temp = snmp_get("1.3.6.1.4.1.989.1.16.1.5.1.4.2")
    cpu_status = snmp_get("1.3.6.1.4.1.989.1.16.1.5.1.5.2")
    psu_temp = snmp_get("1.3.6.1.4.1.989.1.16.1.5.1.4.3")
    psu_status = snmp_get("1.3.6.1.4.1.989.1.16.1.5.1.5.3")
    pico_temp = snmp_get("1.3.6.1.4.1.989.1.16.1.5.1.4.4")
    pico_status = snmp_get("1.3.6.1.4.1.989.1.16.1.5.1.5.4")
    fpga_temp = snmp_get("1.3.6.1.4.1.989.1.16.1.5.1.4.5")
    fpga_status = snmp_get("1.3.6.1.4.1.989.1.16.1.5.1.5.5")
    gps_temp = snmp_get("1.3.6.1.4.1.989.1.16.1.5.1.4.20")
    gps_status = snmp_get("1.3.6.1.4.1.989.1.16.1.5.1.5.20")
    rf_tx_temp = snmp_get("1.3.6.1.4.1.989.1.16.1.5.1.4.21")
    rf_tx_status = snmp_get("1.3.6.1.4.1.989.1.16.1.5.1.5.21")
    rf_fpga_temp = snmp_get("1.3.6.1.4.1.989.1.16.1.5.1.4.22")
    rf_fpga_status = snmp_get("1.3.6.1.4.1.989.1.16.1.5.1.5.22")
    rf_board_temp = snmp_get("1.3.6.1.4.1.989.1.16.1.5.1.4.23")
    rf_board_status = snmp_get("1.3.6.1.4.1.989.1.16.1.5.1.5.23")
    fem1_temp = snmp_get("1.3.6.1.4.1.989.1.16.1.5.1.4.24")
    fem1_status = snmp_get("1.3.6.1.4.1.989.1.16.1.5.1.5.24")
    fem2_temp = snmp_get("1.3.6.1.4.1.989.1.16.1.5.1.4.25")
    fem2_status = snmp_get("1.3.6.1.4.1.989.1.16.1.5.1.5.25")
  end

  def get_bs_voltage_stats
    # AIRSPAN-ASMAX-COMMON-MIB::asMaxCmDcVoltageMonitorTable
    #  - voltage is in mV
    #  - status can be nominal(0), tooHigh(1), tooLow(2), outOfRange(3)

    qrtd_5v0_voltage = snmp_get("1.3.6.1.4.1.989.1.16.1.7.1.4.1")
    qrtd_5v0_status = snmp_get("1.3.6.1.4.1.989.1.16.1.7.1.5.1")
    qrtd_3v3_voltage = snmp_get("1.3.6.1.4.1.989.1.16.1.7.1.4.2")
    qrtd_3v3_status = snmp_get("1.3.6.1.4.1.989.1.16.1.7.1.5.2")
    qrtd_2v5_voltage = snmp_get("1.3.6.1.4.1.989.1.16.1.7.1.4.3")
    qrtd_2v5_status = snmp_get("1.3.6.1.4.1.989.1.16.1.7.1.5.3")
    qrtd_1v8_voltage = snmp_get("1.3.6.1.4.1.989.1.16.1.7.1.4.4")
    qrtd_1v8_status = snmp_get("1.3.6.1.4.1.989.1.16.1.7.1.5.4")
    qrtd_1v0_voltage = snmp_get("1.3.6.1.4.1.989.1.16.1.7.1.4.5")
    qrtd_1v0_status = snmp_get("1.3.6.1.4.1.989.1.16.1.7.1.5.5")
  end

  def get_ms_stats(mac)
    # ASMAX-ESTATS-MIB::asxEstatsActiveMsUlBytes.1.<MacAddr>
    uplink_bytes = snmp_get("1.3.6.1.4.1.989.1.16.2.9.6.1.1.1.#{mac}").to_i
    # ASMAX-ESTATS-MIB::asxEstatsActiveMsDlBytes.1.<MacAddr>
    downlink_bytes = snmp_get("1.3.6.1.4.1.989.1.16.2.9.6.1.2.1.#{mac}").to_i
    # ASMAX-ESTATS-MIB::asxEstatsMsDlRssi.1.<MacAddr>
    dl_rssi = snmp_get("1.3.6.1.4.1.989.1.16.2.9.2.1.1.1.#{mac}").to_i
    # ASMAX-ESTATS-MIB::asxEstatsMsDlCinr.1.<MacAddr>
    dl_cinr = snmp_get("1.3.6.1.4.1.989.1.16.2.9.2.1.12.1.#{mac}").to_i
    # ASMAX-ESTATS-MIB::asxEstatsMsUlRssi.1.<MacAddr>
    ul_rssi = snmp_get("1.3.6.1.4.1.989.1.16.2.9.2.1.2.1.#{mac}").to_i
    # ASMAX-ESTATS-MIB::asxEstatsMsUlCinr.1.<MacAddr>
    ul_cinr = snmp_get("1.3.6.1.4.1.989.1.16.2.9.2.1.5.1.#{mac}").to_i
    # ASMAX-ESTATS-MIB::asxEstatsMsUlTxPower.1.<MacAddr>
    ul_txpower = snmp_get("1.3.6.1.4.1.989.1.16.2.9.2.1.13.1.#{mac}").to_i

    # TODO
    #@meas.clstats(ma, mac, ul_rssi, ul_cinr, dl_rssi, dl_cinr, m.mcsulmod, m.mcsdlmod)
  end

  def add_station(mac)
    # The following settings are contained in the SNMP table
    # ASMAX-AD-BRIDGE-MIB::asDot1adSsPortProvTable (1.3.6.1.4.1.989.1.16.5.4.2.1)

    # ASMAX-AD-BRIDGE-MIB::asDot1adSsPortProvRowStatus.1.<MacAddr>
    # Valid values are: active(1), notInService(2), notReady(3),
    # createAndGo(4), createAndWait(5), destroy(6)
    snmp_set("1.3.6.1.4.1.989.1.16.5.4.2.1.1.7.1.#{mac}", 5) # createAndWait

    # ASMAX-AD-BRIDGE-MIB::asDot1adSsPortProvAdMode.1.<MacAddr>
    # Only relevant in "provider" (802.1ad) mode.
    #snmp_set("1.3.6.1.4.1.989.1.16.5.4.2.1.1.2.1.#{mac}", 0)

    # ASMAX-AD-BRIDGE-MIB::asDot1adSsPortProvIngressFilterEnabled.1.<MacAddr>
    # When enabled, discards all incoming frames for vlans
    # that are not included in this port's egress vlan list.
    # TODO: we should make this work and enable it
    snmp_set("1.3.6.1.4.1.989.1.16.5.4.2.1.1.3.1.#{mac}", 0) # false

    # ASMAX-AD-BRIDGE-MIB::asDot1adSsPortProvPvid.1.<MacAddr>
    # The PVID (Primary Vlan ID) of this port.
    snmp_set("1.3.6.1.4.1.989.1.16.5.4.2.1.1.4.1.#{mac}", @data_vlan)

    # ASMAX-AD-BRIDGE-MIB::asDot1adSsPortProvUserPriority.1.<MacAddr>
    # The user priority of vlan-tagged traffic. We leave the default value.
    #snmp_set("1.3.6.1.4.1.989.1.16.5.4.2.1.1.5.1.#{mac}", 0)

    # ASMAX-AD-BRIDGE-MIB::asDot1adSsPortProvAllowedFrameTypes.1.<MacAddr>
    # The frame types permitted on incoming traffic to this port.
    #   1 -> admit all
    #   2 -> admit only vlan-tagged
    #   3 -> admit only untagged
    snmp_set("1.3.6.1.4.1.989.1.16.5.4.2.1.1.6.1.#{mac}", 1)

    # ASMAX-AD-BRIDGE-MIB::asDot1adSsPortProvQinqSupported.1.<MacAddr>
    # Is Q-in-Q supported for this SS? (boolean)
    snmp_set("1.3.6.1.4.1.989.1.16.5.4.2.1.1.8.1.#{mac}", 0) # false

    # ASMAX-AD-BRIDGE-MIB::asDot1adSsPortProvSTagVlan.1.<MacAddr>
    #snmp_set("1.3.6.1.4.1.989.1.16.5.4.2.1.1.9.1.#{mac}", 0)

    # ASMAX-AD-BRIDGE-MIB::asDot1adSsPortProvUseCTagPriority.1.<MacAddr>
    #snmp_set("1.3.6.1.4.1.989.1.16.5.4.2.1.1.10.1.#{mac}", 1) # true

    # ASMAX-AD-BRIDGE-MIB::asDot1adSsPortProvsTagPriority.1.<MacAddr>
    #snmp_set("1.3.6.1.4.1.989.1.16.5.4.2.1.1.11.1.#{mac}", 0)

    # ASMAX-AD-BRIDGE-MIB::asDot1adSsPortProvRowStatus.1.<MacAddr>
    snmp_set("1.3.6.1.4.1.989.1.16.5.4.2.1.1.7.1.#{mac}", 1) # active

    # The following settings are contained in the SNMP table
    # ASMAX-AD-BRIDGE-MIB::asDot1adSsPortVlanListTable (1.3.6.1.4.1.989.1.16.5.4.2.2)

    # ASMAX-AD-BRIDGE-MIB::asDot1adSsPortVlanListRowStatus.1.<MacAddr>.<Vlan>
    # Valid values are: active(1), notInService(2), notReady(3),
    # createAndGo(4), createAndWait(5), destroy(6)
    snmp_set("1.3.6.1.4.1.989.1.16.5.4.2.2.1.4.1.#{mac}.#{@data_vlan}", 5) # createAndWait

    # ASMAX-AD-BRIDGE-MIB::asDot1adSsPortVlanListUntagged.1.<MacAddr>.<Vlan>
    # Determines whether frames are untagged on egress. (boolean)
    snmp_set("1.3.6.1.4.1.989.1.16.5.4.2.2.1.3.1.#{mac}.#{@data_vlan}", 0) # false

    # ASMAX-AD-BRIDGE-MIB::asDot1adSsPortVlanListRowStatus.1.<MacAddr>.<Vlan>
    snmp_set("1.3.6.1.4.1.989.1.16.5.4.2.2.1.4.1.#{mac}.#{@data_vlan}", 1) # active
  end

  def delete_station(mac)
    # ASMAX-AD-BRIDGE-MIB::asDot1adSsPortVlanListRowStatus.1.<MacAddr>.<Vlan>
    snmp_set("1.3.6.1.4.1.989.1.16.5.4.2.2.1.4.1.#{mac}.#{@data_vlan}", 6) # destroy

    # ASMAX-AD-BRIDGE-MIB::asDot1adSsPortProvRowStatus.1.<MacAddr>
    snmp_set("1.3.6.1.4.1.989.1.16.5.4.2.1.1.7.1.#{mac}", 6) # destroy
  end

end
