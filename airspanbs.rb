require 'rufus/scheduler'
require 'snmp'
require 'omf-aggmgr/ogs_wimaxrf/bs'
require 'omf-aggmgr/ogs_wimaxrf/measurements'
require 'omf-aggmgr/ogs_wimaxrf/util'

class AirspanBs < Bs
  attr_reader :serial, :tpsduul, :tppduul, :tpsdudl, :tppdud

  PARAMS_CLASSES = []

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
          error("Exception in trap handler: #{e.message}\n\t#{e.backtrace.join("\n\t")}")
        end
      end
      manager.on_trap_default do |trap|
        info("Received SNMP trap #{trap.inspect}")
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

    scheduler = Rufus::Scheduler.start_new
    # Local stats gathering
    scheduler.every "#{@meas.localinterval}s" do
      get_bs_stats
      # ASMAX-ESTATS-MIB::asxEstatsRegisteredMs.1
      registered_ms = begin snmp_get("1.3.6.1.4.1.989.1.16.2.9.5.1.1.1").to_i rescue 0 end
      debug("Found #{registered_ms} registered mobiles (#{@mobs.length} authorized + #{registered_ms - @mobs.length} unauthorized)")
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
  end

  def get_bs_stats
    get_bs_temperature_stats
    get_bs_voltage_stats
  end

  def get_bs_status
    # ASMAX-EBS-MIB::asxEbsBsStatusOperationalStatus.1
    status = snmp_get("1.3.6.1.4.1.989.1.16.2.7.4.2.1.1.1")
    return status
  end

  def get_bs_security_info
    # ASMAX-EBS-MIB::asxEbsBsStatusActiveEncryptionMode.1
    encryption_mode = snmp_get("1.3.6.1.4.1.989.1.16.2.7.4.2.1.4.1")
    # ASMAX-EBS-MIB::asxEbsSecuritySaChallengeTimer.1
    sa_tek_timeout = snmp_get("1.3.6.1.4.1.989.1.16.2.7.3.5.1.1.1")
    # ASMAX-EBS-MIB::asxEbsSecuritySaChallengeMaxResends.1
    sa_tek_max_resends = snmp_get("1.3.6.1.4.1.989.1.16.2.7.3.5.1.2.1")
    # ASMAX-EBS-MIB::asxEbsSecurityTekLifetime.1
    sa_tek_lifetime = snmp_get("1.3.6.1.4.1.989.1.16.2.7.3.5.1.3.1")
    # ASMAX-EBS-MIB::asxEbsSecurityPmkChangeOverTime.1
    sa_tek_change_over_time = snmp_get("1.3.6.1.4.1.989.1.16.2.7.3.5.1.4.1")
    # ASMAX-EBS-MIB::asxEbsSecurityAllowInsecureSs.1
    insecure_station_allowed = snmp_get("1.3.6.1.4.1.989.1.16.2.7.3.5.1.5.1")
    # ASMAX-EBS-MIB::asxEbsSecurityAllowPkmv1Authentication.1
    pkm_v1_allowed = snmp_get("1.3.6.1.4.1.989.1.16.2.7.3.5.1.6.1")
    # ASMAX-EBS-MIB::asxEbsSecurityAllowPkmv2Authentication.1
    pkm_v2_allowed = snmp_get ("1.3.6.1.4.1.989.1.16.2.7.3.5.1.7.1")
    # ASMAX-EBS-MIB::asxEbsSecurityAllowCcmAesKeyWrapEncryption.1
    aes_wrap_encryption_allowed = snmp_get("1.3.6.1.4.1.989.1.16.2.7.3.5.1.8.1")
    # ASMAX-EBS-MIB::asxEbsSecurityAllowNoEncryption.1
    no_encryption_allowed = snmp_get("1.3.6.1.4.1.989.1.16.2.7.3.5.1.9.1")
  end

  def get_zone_info
    # ASMAX-EBS-MIB::asxEbsStdZoneType.1.0
    type = snmp_get("1.3.6.1.4.1.989.1.16.2.7.5.4.1.2.1.0")
    # ASMAX-EBS-MIB::asxEbsStdZoneUseAllSubchannels.1.0
    use_all_subchanels = snmp_get("1.3.6.1.4.1.989.1.16.2.7.5.4.1.3.1.0")
    # ASMAX-EBS-MIB::asxEbsStdZoneMaxProportio.1.0
    max_extention_percentage = snmp_get("1.3.6.1.4.1.989.1.16.2.7.5.4.1.4.1.0")
    # ASMAX-EBS-MIB::asxEbsStdZonePermutationBase.1.0
    permutation_base = snmp_get("1.3.6.1.4.1.989.1.16.2.7.5.4.1.5.1.0")
    # ASMAX-EBS-MIB::asxEbsStdZoneStcMode.1.0
    stc_code = snmp_get("1.3.6.1.4.1.989.1.16.2.7.5.4.1.7.1.0")
    # ASMAX-EBS-MIB::asxEbsStdZoneStcMatrix1.0
    stc_matrix = snmp_get("1.3.6.1.4.1.989.1.16.2.7.5.4.1.8.1.0")
    # ASMAX-EBS-MIB::asxEbsStdZoneAmcType.1.0
    stc_type = snmp_get("1.3.6.1.4.1.989.1.16.2.7.5.4.1.9.1.0")
    # ASMAX-EBS-MIB::asxEbsStdZoneDedicatedPilots.1.0
    dedicated_pilots = snmp_get("1.3.6.1.4.1.989.1.16.2.7.5.4.1.12.1.0")
  end

  def get_dreg_cmd_info
    # ASMAX-EBS-MIB::asxEbsSectorCfgT46IdleModeInitiateTimeout.1
    unsolicited_timeout = snmp_get("1.3.6.1.4.1.989.1.16.2.7.3.1.1.16.1")
    # ASMAX-EBS-MIB::asxEbsSectorCfgDregCmdWaitTime.1
    wait_time = snmp_get("1.3.6.1.4.1.989.1.16.2.7.3.1.1.84.1")
    # ASMAX-EBS-MIB::asxEbsSectorCfgDregCmdNumRetries.1
    retries = snmp_get("1.3.6.1.4.1.989.1.16.2.7.3.1.1.85.1")
  end

  def get_arq_settings
    # ASMAX-ESVC-MIB::asxEsvcServiceClassExtArqEnabled.1.1
    # INTEGER: booleanFalse(0)/booleanTrue(1)
    enabled = snmp_get("1.3.6.1.4.1.989.1.16.2.8.3.3.1.7.1.1")
    # ASMAX-ESVC-MIB::asxEsvcServiceClassExtArqDeliverInOrder.1.1
    # INTEGER: booleanFalse(0)/booleanTrue(1)
    in_order = snmp_get("1.3.6.1.4.1.989.1.16.2.8.3.3.1.8.1.1")
  end

  def arq_settings
    # ASMAX-ESVC-MIB::asxEsvcServiceClassExtRowStatus.1.1
    # Valid values are: active(1), notInService(2), notReady(3),
    # createAndGo(4), createAndWait(5), destroy(6)
    snmp_set("1.3.6.1.4.1.989.1.16.2.8.3.3.1.2.1.1", 5)
    # ASMAX-ESVC-MIB::asxEsvcServiceClassExtArqEnabled.1.1
    # INTEGER: booleanFalse(0)/booleanTrue(1)
    snmp_set("1.3.6.1.4.1.989.1.16.2.8.3.3.1.7.1.1", 0)
    # ASMAX-ESVC-MIB::asxEsvcServiceClassExtArqDeliverInOrder.1.1
    # INTEGER: booleanFalse(0)/booleanTrue(1)
    #snmp_set("1.3.6.1.4.1.989.1.16.2.8.3.3.1.8.1.1", 1)
    # ASMAX-ESVC-MIB::asxEsvcServiceClassExtRowStatus.1.1
    # Valid values are: active(1), notInService(2), notReady(3),
    # createAndGo(4), createAndWait(5), destroy(6)
    snmp_set("1.3.6.1.4.1.989.1.16.2.8.3.3.1.2.1.1", 1)
  end

  def get_harq_settings
    # ASMAX-EBS-MIB::asxEsvcServiceClassExtHarqEnabled.1.1
    enabled = snmp_get("1.3.6.1.4.1.989.1.16.2.8.3.3.1.3.1.1", 0)
    # ASMAX-EBS-MIB::asxEsvcServiceClassExtHarqMaxTransmission.1.1
    # Integer: 0 == no limit
    max_transmission = snmp_get("1.3.6.1.4.1.989.1.16.2.8.3.3.1.5.1.1", 0)
    # ASMAX-EBS-MIB::asxEbsArqCfgHarqAckDelay.1
    ack_delay = snmp_get("1.3.6.1.4.1.989.1.16.2.7.3.7.1.6.1.", 50)
    # ASMAX-EBS-MIB::asxEbsArqCfgHarqNumAckChannels.1
    number_of_ack_channgels = snmp_get("1.3.6.1.4.1.989.1.16.2.7.3.7.1.7.1", 24)
    # ASMAX-EBS-MIB::asxEbsRrmCfgDlHarqErrLow.1
    # Integer 0..40
    error_rate_threashold_lower = snmp_get("1.3.6.1.4.1.989.1.16.2.7.3.12.1.43.1", 2)
    # ASMAX-EBS-MIB::asxEbsRrmCfgDlHarqErrHigh.1
    # Integer 0..40
    error_rate_threshold_higher = snmp_get("1.3.6.1.4.1.989.1.16.2.7.3.12.1.44.1", 10)
    # ASMAX-EBS-MIB::asxEbsRrmCfgDlHarqErrFastHigh.1
    # Integer 0..40
    fast_error_rate_threshold = snmp_get("1.3.6.1.4.1.989.1.16.2.7.3.12.1.45.1", 30)
    # ASMAX-EBS-MIB::asxEbsRrmCfgDlHarqPurgeTimeout
    # Integer 0..100
    purge_timeout = snmp_get("1.3.6.1.4.1.989.1.16.2.7.3.12.1.46.1", 10)
  end

  def harq_settings
    # default values for now
    # ASMAX-ESVC-MIB::asxEsvcServiceClassExtRowStatus.1.1
    # Valid values are: active(1), notInService(2), notReady(3),
    # createAndGo(4), createAndWait(5), destroy(6)
    snmp_set("1.3.6.1.4.1.989.1.16.2.8.3.3.1.2.1.1", 5)
    # ASMAX-EBS-MIB::asxEsvcServiceClassExtHarqEnabled.1.1
    snmp_set("1.3.6.1.4.1.989.1.16.2.8.3.3.1.3.1.1", 0)
    # ASMAX-EBS-MIB::asxEsvcServiceClassExtHarqMaxTransmission.1.1
    # Integer: 0 == no limit
    snmp_set("1.3.6.1.4.1.989.1.16.2.8.3.3.1.5.1.1", 0)
    # ASMAX-ESVC-MIB::asxEsvcServiceClassExtRowStatus.1.1
    # Valid values are: active(1), notInService(2), notReady(3),
    # createAndGo(4), createAndWait(5), destroy(6)
    snmp_set("1.3.6.1.4.1.989.1.16.2.8.3.3.1.3.1.1", 1)
    # ASMAX-EBS-MIB::asxEbsArqCfgHarqAckDelay.1 -> integer 1/0
    snmp_set("1.3.6.1.4.1.989.1.16.2.7.3.7.1.6.1.", 50)
    # ASMAX-EBS-MIB::asxEbsArqCfgHarqNumAckChannels.1 -> integer
    snmp_set("1.3.6.1.4.1.989.1.16.2.7.3.7.1.7.1", 24)
    # ASMAX-EBS-MIB::asxEbsRrmCfgDlHarqErrLow.1
    # Integer 0..40
    snmp_set("1.3.6.1.4.1.989.1.16.2.7.3.12.1.43.1", 2)
    # ASMAX-EBS-MIB::asxEbsRrmCfgDlHarqErrHigh.1
    # Integer 0..40
    snmp_set("1.3.6.1.4.1.989.1.16.2.7.3.12.1.44.1", 10)
    # ASMAX-EBS-MIB::asxEbsRrmCfgDlHarqErrFastHigh.1
    # Integer 0..40
    snmp_set("1.3.6.1.4.1.989.1.16.2.7.3.12.1.45.1", 30)
    # ASMAX-EBS-MIB::asxEbsRrmCfgDlHarqPurgeTimeout
    # Integer 0..100
    snmp_set("1.3.6.1.4.1.989.1.16.2.7.3.12.1.46.1", 10)
  end

  def get_bs_various_settings
    # ASMAX-EBS-MIB::asxEbsSectorCfgResourceRetainTimeout
    resource_retain_timeout = snmp_get("1.3.6.1.4.1.989.1.16.2.7.3.1.1.15.1")
		# ASMAX-EBS-MIB::asxEbsSectorCfgT46IdleModeInitiateTimeout
    idle_mode_timeout = snmp_get("1.3.6.1.4.1.989.1.16.2.7.3.1.1.16.1")
		# ASMAX-EBS-MIB::asxEbsSectorCfgBsMgmtResourceHoldTimeout
    resource_hold_timeout = snmp_get("1.3.6.1.4.1.989.1.16.2.7.3.1.1.17.1")
		# ASMAX-EBS-MIB::asxEbsSectorCfgMaxUlAllocation
    max_upload_allocation = snmp_get("1.3.6.1.4.1.989.1.16.2.7.3.1.1.20.1")
		# ASMAX-EBS-MIB::asxEbsSectorCfgMaxDlAllocation
    max_download_allocation = snmp_get("1.3.6.1.4.1.989.1.16.2.7.3.1.1.21.1")
		# ASMAX-EBS-MIB::asxEbsSectorCfgTtg
    downlink_uplink_gap = snmp_get("1.3.6.1.4.1.989.1.16.2.7.3.1.1.22.1")
		# ASMAX-EBS-MIB::asxEbsSectorCfgRtg
    uplink_downlink_gap = snmp_get("1.3.6.1.4.1.989.1.16.2.7.3.1.1.23.1")
		# ASMAX-EBS-MIB::asxEbsSectorCfgNumRangingRetries
    ranging_retry_period = snmp_get("1.3.6.1.4.1.989.1.16.2.7.3.1.1.35.1")
		# ASMAX-EBS-MIB::asxEbsSectorCfgNumExpectedSss
    expected_stations = snmp_get("1.3.6.1.4.1.989.1.16.2.7.3.1.1.40.1")
		# ASMAX-EBS-MIB::asxEbsSectorCfgRegistrationTimeout
    registration_timeout = snmp_get("1.3.6.1.4.1.989.1.16.2.7.3.1.1.41.1")
		# ASMAX-EBS-MIB::asxEbsSectorCfgInService
    phy_operation_enabled = snmp_get("1.3.6.1.4.1.989.1.16.2.7.3.1.1.52.1")
		# ASMAX-EBS-MIB::asxEbsSectorCfgNumNoReportsForSignoff
    max_rep_rsp_fails = snmp_get("1.3.6.1.4.1.989.1.16.2.7.3.1.1.55.1")
		# ASMAX-EBS-MIB::asxEbsSectorCfgTxPower
    transmit_power= snmp_get("1.3.6.1.4.1.989.1.16.2.7.3.1.1.59.1")
		# ASMAX-EBS-MIB::asxEbsSectorCfgT42HoRngRspTimeout
    rng_req_response_timeout= snmp_get("1.3.6.1.4.1.989.1.16.2.7.3.1.1.69.1")
		# ASMAX-EBS-MIB::asxEbsSectorCfgHoTimeToTriggerDuration
    time_to_trigger = snmp_get("1.3.6.1.4.1.989.1.16.2.7.3.1.1.71.1")
		# ASMAX-EBS-MIB::asxEbsSectorCfgIncludeMsTxPowerLimit
    tx_power_limit_enabled = snmp_get("1.3.6.1.4.1.989.1.16.2.7.3.1.1.72.1")
		# ASMAX-EBS-MIB::asxEbsSectorCfgMsTxPowerLimit
    tx_power_limit = snmp_get("1.3.6.1.4.1.989.1.16.2.7.3.1.1.73.1")
		# ASMAX-EBS-MIB::asxEbsSectorCfgDeadPeriodicRangingInterval
    periodic_ranging_interval = snmp_get("1.3.6.1.4.1.989.1.16.2.7.3.1.1.74.1")
		# ASMAX-EBS-MIB::asxEbsSectorCfgDregCmdWaitTime
    dreg_cmd_wait = snmp_get("1.3.6.1.4.1.989.1.16.2.7.3.1.1.84.1")
		# ASMAX-EBS-MIB::asxEbsSectorCfgDregCmdNumRetries
    dreg_cmd_retries = snmp_get("1.3.6.1.4.1.989.1.16.2.7.3.1.1.85.1")
		# ASMAX-EBS-MIB::asxEbsSectorCfgDlPermutationBase
    downlink_permutation_base = snmp_get("1.3.6.1.4.1.989.1.16.2.7.3.1.1.85.1")
		# ASMAX-EBS-MIB::asxEbsSectorCfgSnReportingBase
    sn_reports_base = snmp_get("1.3.6.1.4.1.989.1.16.2.7.3.1.1.92.1")
		# ASMAX-EBS-MIB::asxEbsSectorCfgPowerControlMode
    power_control_mode = snmp_get("1.3.6.1.4.1.989.1.16.2.7.3.1.1.102.1")
		# ASMAX-EBS-MIB::asxEbsSectorCfgNiIePeriod
    uplink_noise_interfaerance_level_period = snmp_get("1.3.6.1.4.1.989.1.16.2.7.3.1.1.103.1")
		# ASMAX-EBS-MIB::asxEbsSectorCfgMsMaxTxPowerBackoff
    max_tx_power_backoff = snmp_get("1.3.6.1.4.1.989.1.16.2.7.3.1.1.107.1")
		# ASMAX-EBS-MIB::asxEbsSectorCfgCarrierSenseHysteresis
    carrier_sense_hysteresis = snmp_get("1.3.6.1.4.1.989.1.16.2.7.3.1.1.112.1")
		# ASMAX-EBS-MIB::asxEbsSectorCfgCarrierSenseMeasurePeriod
    carrier_sense_measure_period = snmp_get("1.3.6.1.4.1.989.1.16.2.7.3.1.1.114.1")
		# ASMAX-EBS-MIB::asxEbsSectorCfgPrivateMapMode
    private_map_compression = snmp_get("1.3.6.1.4.1.989.1.16.2.7.3.1.1.115.1")
		# ASMAX-EBS-MIB::asxEbsSectorCfgScanScheduleEnable
    fb_scan_enabled = snmp_get("1.3.6.1.4.1.989.1.16.2.7.3.1.1.118.1")
		# ASMAX-EBS-MIB::asxEbsHoTriggerMsAction
    handoff_trigger_action = snmp_get("1.3.6.1.4.1.989.1.16.2.7.3.8.1.4.1")
  end

  def get_bs_temperature_stats
    # AIRSPAN-ASMAX-COMMON-MIB::asMaxCmTemperatureMonitorTable
    # AIRSPAN-ASMAX-COMMON-MIB::asMaxCmTempMonValue
    cpu_temp = snmp_get("1.3.6.1.4.1.989.1.16.1.5.1.4.2")
    # AIRSPAN-ASMAX-COMMON-MIB::asMaxCmTempMonStatus
    cpu_status = snmp_get("1.3.6.1.4.1.989.1.16.1.5.1.5.2")
    # AIRSPAN-ASMAX-COMMON-MIB::asMaxCmTempMonValue
    psu_temp = snmp_get("1.3.6.1.4.1.989.1.16.1.5.1.4.3")
    # AIRSPAN-ASMAX-COMMON-MIB::asMaxCmTempMonStatus
    psu_status = snmp_get("1.3.6.1.4.1.989.1.16.1.5.1.5.3")
    # AIRSPAN-ASMAX-COMMON-MIB::asMaxCmTempMonValue
    pico_temp = snmp_get("1.3.6.1.4.1.989.1.16.1.5.1.4.4")
    # AIRSPAN-ASMAX-COMMON-MIB::asMaxCmTempMonStatus
    pico_status = snmp_get("1.3.6.1.4.1.989.1.16.1.5.1.5.4")
    # AIRSPAN-ASMAX-COMMON-MIB::asMaxCmTempMonValue
    fpga_temp = snmp_get("1.3.6.1.4.1.989.1.16.1.5.1.4.5")
    # AIRSPAN-ASMAX-COMMON-MIB::asMaxCmTempMonStatus
    fpga_status = snmp_get("1.3.6.1.4.1.989.1.16.1.5.1.5.5")
    # AIRSPAN-ASMAX-COMMON-MIB::asMaxCmTempMonValue
    gps_sdr_temp = snmp_get("1.3.6.1.4.1.989.1.16.1.5.1.4.20")
    # AIRSPAN-ASMAX-COMMON-MIB::asMaxCmTempMonStatus
    gps_sdr_status = snmp_get("1.3.6.1.4.1.989.1.16.1.5.1.5.20")
    # AIRSPAN-ASMAX-COMMON-MIB::asMaxCmTempMonValue
    rf_tx_temp = snmp_get("1.3.6.1.4.1.989.1.16.1.5.1.4.21")
    # AIRSPAN-ASMAX-COMMON-MIB::asMaxCmTempMonStatus
    rf_tx_status = snmp_get("1.3.6.1.4.1.989.1.16.1.5.1.5.21")
    # AIRSPAN-ASMAX-COMMON-MIB::asMaxCmTempMonValue
    rf_fpga_temp = snmp_get("1.3.6.1.4.1.989.1.16.1.5.1.4.22")
    # AIRSPAN-ASMAX-COMMON-MIB::asMaxCmTempMonStatus
    rf_fpga_status = snmp_get("1.3.6.1.4.1.989.1.16.1.5.1.5.22")
    # AIRSPAN-ASMAX-COMMON-MIB::asMaxCmTempMonValue
    rf_board_temp = snmp_get("1.3.6.1.4.1.989.1.16.1.5.1.4.23")
    # AIRSPAN-ASMAX-COMMON-MIB::asMaxCmTempMonStatus
    rf_board_status = snmp_get("1.3.6.1.4.1.989.1.16.1.5.1.5.23")
    # AIRSPAN-ASMAX-COMMON-MIB::asMaxCmTempMonValue
    fem1_temp = snmp_get("1.3.6.1.4.1.989.1.16.1.5.1.4.24")
    # AIRSPAN-ASMAX-COMMON-MIB::asMaxCmTempMonStatus
    fem1_status = snmp_get("1.3.6.1.4.1.989.1.16.1.5.1.5.24")
    # AIRSPAN-ASMAX-COMMON-MIB::asMaxCmTempMonValue
    fem2_temp = snmp_get("1.3.6.1.4.1.989.1.16.1.5.1.4.25")
    # AIRSPAN-ASMAX-COMMON-MIB::asMaxCmTempMonStatus
    fem2_status = snmp_get("1.3.6.1.4.1.989.1.16.1.5.1.5.25")
  end

  def get_bs_voltage_stats
    # AIRSPAN-ASMAX-COMMON-MIB::asMaxCmDcVoltageMonitorTable
    # AIRSPAN-ASMAX-COMMON-MIB::asMaxCmDcVoltageMonValue
    qrtd_5vo_voltage = snmp_get("1.3.6.1.4.1.989.1.16.1.7.1.4.1")
    # AIRSPAN-ASMAX-COMMON-MIB::asMaxCmDcVoltageMonStatus
    qrtd_5vo_status = snmp_get("1.3.6.1.4.1.989.1.16.1.7.1.5.1")
    # AIRSPAN-ASMAX-COMMON-MIB::asMaxCmDcVoltageMonValue
    qrtd_3v3_voltage = snmp_get("1.3.6.1.4.1.989.1.16.1.7.1.4.1")
    # AIRSPAN-ASMAX-COMMON-MIB::asMaxCmDcVoltageMonStatus
    qrtd_3v3_status = snmp_get("1.3.6.1.4.1.989.1.16.1.7.1.5.1")
    # AIRSPAN-ASMAX-COMMON-MIB::asMaxCmDcVoltageMonValue
    qrtd_2v5_voltage = snmp_get("1.3.6.1.4.1.989.1.16.1.7.1.4.1")
    # AIRSPAN-ASMAX-COMMON-MIB::asMaxCmDcVoltageMonStatus
    qrtd_2v5_status = snmp_get("1.3.6.1.4.1.989.1.16.1.7.1.5.1")
    # AIRSPAN-ASMAX-COMMON-MIB::asMaxCmDcVoltageMonValue
    qrtd_1v8_voltage = snmp_get("1.3.6.1.4.1.989.1.16.1.7.1.4.1")
    # AIRSPAN-ASMAX-COMMON-MIB::asMaxCmDcVoltageMonStatus
    qrtd_1v8_status = snmp_get("1.3.6.1.4.1.989.1.16.1.7.1.5.1")
    # AIRSPAN-ASMAX-COMMON-MIB::asMaxCmDcVoltageMonValue
    qrtd_1v0_voltage = snmp_get("1.3.6.1.4.1.989.1.16.1.7.1.4.1")
    # AIRSPAN-ASMAX-COMMON-MIB::asMaxCmDcVoltageMonStatus
    qrtd_1v0_status = snmp_get("1.3.6.1.4.1.989.1.16.1.7.1.5.1")
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
#    @meas.clstats(ma, mac, ul_rssi, ul_cinr, dl_rssi, dl_cinr, m.mcsulmod, m.mcsdlmod)
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
