require 'omf-aggmgr/ogs_wimaxrf/bspbase'

class ArqService < BSPBase
  @name = 'arq'
  @categoryName = 'arq'
  @info = 'Set ARQ parameters'
  param :enable, :bsname => 'arq', :name => '[enable]', :oid => '3.6.1.4.1.989.1.16.2.8.3.3.1.2.1.2', :help => 'Set to TRUE to enable the operation of ARQ: Boolean (false) '
  param :deliverinorder, :bsname => 'arq_deliver_in_order', :name => '[deliverinorder]', :oid => '1.3.6.1.4.1.989.1.16.2.8.3.3.1.8.1.1', :help => 'Set to TRUE if ARQ protected traffic is to be delivered in order: Boolean (true)'
end

class HarqService < BSPBase
  @name = 'harq'
  @categoryName = 'harq'
  @info = 'Set HARQ parameters'
  param :enable, :bsname => 'harq', :name => '[enable]', :oid => '1.3.6.1.4.1.989.1.16.2.8.3.3.1.3.1.1', :help => 'Set to TRUE to enable the operation of HARQ: Boolean (false) '
  param :maxtransmission, :bsname => 'harq_max_transmission', :name => '[maxtransmission]', :oid => '1.3.6.1.4.1.989.1.16.2.8.3.3.1.3.1.1', :help => 'The maximum number of HARQ transmissions: Integer (0)'
  param :ackdelay, :bsname => 'harq_ack_delay', :name => '[ackdelay]', :oid => '1.3.6.1.4.1.989.1.16.2.7.3.7.1.6.1.1', :help => 'The HARQ ACK delay advertised in the UCD (TLV 171): Integer (50)'
  param :ackchannels, :bsname => 'harq_ack_channels', :name => '[ackchannels]', :oid => '1.3.6.1.4.1.989.1.16.2.7.3.7.1.7.1.1', :help => 'The number of HARQ ACK channels that will be allocated in each frame: Integer (24)'
  param :errlow, :bsname => 'harq_err_low', :name => '[errlow]', :oid => '1.3.6.1.4.1.989.1.16.2.7.3.12.1.43.1', :help => 'Error rate threshold to trigger low HARQ error rate event (percentage): Integer[0..40] (2)'
  param :errhigh, :bsname => 'harq_err_high', :name => '[errhigh]', :oid => '1.3.6.1.4.1.989.1.16.2.7.3.12.1.44.1', :help => 'Error rate threshold to trigger high HARQ error rate event (percentage): Integer[0..40] (10)'
  param :errfasthigh, :bsname => 'harq_err_fast_high', :name => '[errfasthigh]', :oid => '1.3.6.1.4.1.989.1.16.2.7.3.12.1.45.1', :help => 'Error rate threshold to trigger HARQ error rate event (percentage): Integer[0..40] (30)'
  param :purgetimeout, :bsname => 'harq_purge_timeout', :name => '[purgetimeout]', :oid => '1.3.6.1.4.1.989.1.16.2.7.3.12.1.46.1', :help => 'In case HARQ error window for an MS was not advanced in this time interval (tens of milliseconds), HARQ MCS shall be driven from PCINR: Integer[1..100] (10)'
end

class MobileService < BSPBase
  @name = 'mobile'
  @categoryName = 'mobile'
  @info = 'Set MOBILE parameters'
  param :idlemodetimeout, :bsname => 'idle_mode_timeout', :name => '[idlemodetimeout]', :oid => '1.3.6.1.4.1.989.1.16.2.7.3.1.1.16.1', :help => 'Time the BS waits for a DREG-REQ after sending a DREG-CMD in case of un-solicited idle mode initiation. in ms: Integer (200)'
  param :dregcmdwaittime, :bsname => 'dreg_cmd_wait_time', :name => '[dregcmdwaittime]', :oid => '1.3.6.1.4.1.989.1.16.2.7.3.1.1.84.1', :help => 'The length of time the BS waits for a response to a DREG-CMD. in ms: Integer (500)'
  param :dregcmdnumretries, :bsname => 'dreg_cmd_num_retries', :name => '[dregcmdnumretries]', :oid => '1.3.6.1.4.1.989.1.16.2.7.3.1.1.85.1', :help => 'The number of times a DREG-CMD is sent to an MS before the BS gives up waiting for a response: Integer (5)'
end

class SecurityService < BSPBase
  @name = 'security'
  @categoryName = 'security'
  @info = 'Set SECURITY parameters'
  param :sachallengetimer, :bsname => 'tek_challenge_timer', :name => '[sachallengetimer]', :oid => '1.3.6.1.4.1.989.1.16.2.7.3.5.1.1.1', :help => 'The time the BS waits after sending an SA TEK challenge before retrying in ms: Integer'
  param :sachallengemaxresend, :bsname => 'tek_challenge_maxresend', :name => '[sachallengemaxresend]', :oid => '1.3.6.1.4.1.989.1.16.2.7.3.5.1.2.1', :help => 'The number of times the BS will retry the SA TEK challenge before the SS is signed off: Integer (3)'
  param :teklifetime, :bsname => 'tek_lifetime', :name => '[teklifetime]', :oid => '1.3.6.1.4.1.989.1.16.2.7.3.5.1.3.1', :help => 'The lifetime of the traffic encryption keys in seconds: Integer (43200)'
  param :tekchangeovertime, :bsname => 'tekchange_over_time', :name => '[tekchangeovertime]', :oid => '1.3.6.1.4.1.989.1.16.2.7.3.5.1.4.1', :help => 'The time after the completion of the SA TEK 3 way challenge that the old PMK and association AKs must be discarded in ms: Integer (50)'
  param :insecurestationallowed, :bsname => 'insecure_station_allowed', :name => '[insecurestationallowed]', :oid => '1.3.6.1.4.1.989.1.16.2.7.3.5.1.5.1', :help => 'A value of TRUE will allow SSs that have negotiated no security to enter the network: Boolean (true)'
  param :pkmv1allowed, :bsname => 'pkm_v1_allowed', :name => '[pkmv1allowed]', :oid => '1.3.6.1.4.1.989.1.16.2.7.3.5.1.6.1', :help => 'The BS is to allow PKM version 1 authentication: Boolean (true)'
  param :pkmv2allowed, :bsname => 'pkm_v2_allowed', :name => '[pkmv2allowed]', :oid => '1.3.6.1.4.1.989.1.16.2.7.3.5.1.7.1', :help => 'The BS is to allow PKM version 2 authentication: Boolean (true)'
  param :aeswrap, :bsname => 'aes_key_wrap_allowed', :name => '[aeswrap]', :oid => '1.3.6.1.4.1.989.1.16.2.7.3.5.1.8.1', :help => 'Enables the BS to use the CCM AES encryption mode with AES key wrapped key encryption: Boolean (false)'
  param :noencryption, :bsname => 'allow_no_encryption', :name => '[noencryption]', :oid => '1.3.6.1.4.1.989.1.16.2.7.3.5.1.9.1', :help => 'Allow no encryption: Boolean (true)'
end

class ZoneService < BSPBase
  @name = 'zone'
  @categoryName = 'zone'
  @info = 'Set ZONE parameters'
  param :type, :bsname => 'zone_type', :name => '[type]', :oid => '1.3.6.1.4.1.989.1.16.2.7.5.4.1.2.1.0', :help => "The zone type, which defines the zone's direction (UL or DL), PHY mode (OFDM or OFDMA) and structure (PUSC, STC, etc): Integer (3)"
  param :useallsubchannels, :bsname => 'use_all_subchanels', :name => '[useallsubchannels]', :oid => '1.3.6.1.4.1.989.1.16.2.7.5.4.1.3.1.0', :help => 'Set to TRUE if the zone must use all subchannels: Boolean (true)'
  param :maxproportion, :bsname => 'zone_max_proportion', :name => '[maxproportion]', :oid => '1.3.6.1.4.1.989.1.16.2.7.5.4.1.4.1.0', :help => 'The maximum percentage of the subframe that this zone will occupy: Integer[1..100] (96)'
  param :permutationbase, :bsname => 'zone_permutation_base', :name => '[permutationbase]', :oid => '1.3.6.1.4.1.989.1.16.2.7.5.4.1.5.1.0', :help => 'The base used for the sub-carrier permutation in PUSC zones: Integer[1..31] (0)'
  param :stccode, :bsname => 'stc_code', :name => '[stccode]', :oid => '1.3.6.1.4.1.989.1.16.2.7.5.4.1.7.1.0', :help => 'The STC mode and number of antennas used in this zone: Integer (0)'
  param :stcmatrix, :bsname => 'stc_matrix', :name => '[stcmatrix]', :oid => '1.3.6.1.4.1.989.1.16.2.7.5.4.1.8.1.0', :help => 'The STC matrix used in this zone, if STC is enabled: Integer (0)'
  param :acmtype, :bsname => 'zone_acm_type', :name => '[acmtype]', :oid => '1.3.6.1.4.1.989.1.16.2.7.5.4.1.9.1.0', :help => 'The AMC type used in this zone: Integer (0)'
  param :dedicatedpilots, :bsname => 'dedicated_pilots', :name => '[dedicatedpilots]', :oid => '1.3.6.1.4.1.989.1.16.2.7.5.4.1.12.1.0', :help => 'Set to TRUE if dedicated pilots are required in this zone, or FALSE if broadcast pilots are required: Boolean (false)'
end

class WirelessService < BSPBase
  @name = 'wireless'
  @categoryName = 'wireless'
  @info = 'Set WIRELESS parameters'
  param :resourceretaintimeout, :bsname => 'resource_retain_timeout', :name => '[resourceretaintimeout]', :oid => '1.3.6.1.4.1.989.1.16.2.7.3.1.1.15.1', :help => "Length of time the BS retains an MS's state information after reception of a MOB_HO-IND message. in ms: Integer (2000)"
  param :idlemodetimeout, :bsname => 'idle_mode_timeout', :name => '[idlemodetimeout]', :oid => '1.3.6.1.4.1.989.1.16.2.7.3.1.1.16.1', :help => 'Time the BS waits for a DREG-REQ after sending a DREG-CMD in case of un-solicited idle mode initiation. in ms: Integer (200)'
  param :resourceholdtimeout, :bsname => 'resource_hold_timeout', :name => '[resourceholdtimeout]', :oid => '1.3.6.1.4.1.989.1.16.2.7.3.1.1.17.1', :help => 'Time duration for which BS maintains MS connection information after sending the DREG-CMD. in ms: Integer (500)'
  param :maxulallocation, :bsname => 'max_upload_allocation', :name => '[maxulallocation]', :oid => '1.3.6.1.4.1.989.1.16.2.7.3.1.1.20.1', :help => 'Maximum size of a single uplink allocation: Integer (1100)'
  param :maxdlallocation, :bsname => 'max_download_allocation', :name => '[maxdlallocation]', :oid => '1.3.6.1.4.1.989.1.16.2.7.3.1.1.21.1', :help => 'Maximum size of a single downlink allocation: Integer (1600)'
  param :dlulgap, :bsname => 'downlink_uplink_gap', :name => '[dlulgap]', :oid => '1.3.6.1.4.1.989.1.16.2.7.3.1.1.22.1', :help => 'The minimum gap between the last symbol of the downlink subframe and the beginning of the first uplink grant. Only applicable for TDD: Integer (1057)'
  param :uldlgap, :bsname => 'uplink_downlink_gap', :name => '[uldlgap]', :oid => '1.3.6.1.4.1.989.1.16.2.7.3.1.1.23.1', :help => 'The minimum gap between the last symbol of the uplink subframe and the beginning of the first downlink grant. Only applicable for TDD: Integer (1057)'
  param :rangingretry, :bsname => 'ranging_retry_period', :name => '[rangingretry]', :oid => '1.3.6.1.4.1.989.1.16.2.7.3.1.1.35.1', :help => 'The number of ranging attempts before the BS gives up trying to align the SS: Integer (16)'
  param :numexpectedss, :bsname => 'num_expected_stations', :name => '[numexpectedss]', :oid => '1.3.6.1.4.1.989.1.16.2.7.3.1.1.40.1', :help => 'The number of expected SSs the sector is to support. It does not limit the number of SSs that may be supported: Integer (512)'
  param :regtimeout, :bsname => 'registration_timeout', :name => '[regtimeout]', :oid => '1.3.6.1.4.1.989.1.16.2.7.3.1.1.41.1', :help => 'Time that the BS waits for registration to occur after authorization before aborting the sign-on: Integer (10000)'
  param :phyenabled, :bsname => 'phy_operation_enabled', :name => '[phyenabled]', :oid => '1.3.6.1.4.1.989.1.16.2.7.3.1.1.52.1', :help => 'Set to TRUE to enable PHY operation of this sector: Boolean (true)'
  param :maxreprspfails, :bsname => 'max_rep_rsp_fails', :name => '[maxreprspfails]', :oid => '1.3.6.1.4.1.989.1.16.2.7.3.1.1.55.1', :help => 'The number of consecutive times that the MS can fail to send a REP-RSP message in reply to a REP-REQ from the base station before the MS is signed off: Integer (5)'
  param :txpower, :bsname => 'tx_power', :name => '[txpower]', :oid => '1.3.6.1.4.1.989.1.16.2.7.3.1.1.59.1', :help => 'The transmit power required by the base station, in units of 0.01 dBm: Integer[0..7500]'
  param :rngreqtimeout, :bsname => 'rng_req_response_timeout', :name => '[rngreqtimeout]', :oid => '1.3.6.1.4.1.989.1.16.2.7.3.1.1.69.1', :help => 'Length of time the target BS waits for a RNG-REQ message after the preparation phase before abandoning the handover: Integer (10000)'
  param :hotimetotrigger, :bsname => 'ho_time_to_trigger', :name => '[hotimetotrigger]', :oid => '1.3.6.1.4.1.989.1.16.2.7.3.1.1.71.1', :help => 'Time-to-Trigger duration is the time duration for MS decides to select a neighbor BS as a possible target BS: Integer[0..255] (0)'
  param :txpowerlimitenabled, :bsname => 'tx_power_limit_enabled', :name => '[txpowerlimitenabled]', :oid => '1.3.6.1.4.1.989.1.16.2.7.3.1.1.72.1', :help => 'Set to true to include the MS transmit power limitation TLV in the UCD. For user it means MS tx power limit enabled: Boolean (false)'
  param :txpowerlimit, :bsname => 'tx_power_limit', :name => '[txpowerlimit]', :oid => '1.3.6.1.4.1.989.1.16.2.7.3.1.1.73.1', :help => 'The MS transmit power limitation to be included in the UCD if the asxEbsSectorCfgIncludeMsTxPowerLimit field is true: Integer[0..255] (0)'
  param :ranginginterval, :bsname => 'periodic_ranging_interval', :name => '[ranginginterval]', :oid => '1.3.6.1.4.1.989.1.16.2.7.3.1.1.74.1', :help => 'The period during which the BS does not calculate any further adjustments for an SS after it has made an adjustment: Integer (50)'
  param :dregcmdwait, :bsname => 'dreg_cmd_wait_time', :name => '[dregcmdwait]', :oid => '1.3.6.1.4.1.989.1.16.2.7.3.1.1.84.1', :help => 'The length of time the BS waits for a response to a DREG-CMD: Integer (500)'
  param :dregcmdretries, :bsname => 'dreg_cmd_num_retries', :name => '[dregcmdretries]', :oid => '1.3.6.1.4.1.989.1.16.2.7.3.1.1.85.1', :help => 'The number of times a DREG-CMD is sent to an MS before the BS gives up waiting for a response: Integer (5)'
  param :dlpermutationbase, :bsname => 'downlink_permutation_base', :name => '[dlpermutationbase]', :oid => '1.3.6.1.4.1.989.1.16.2.7.3.1.1.87.1', :help => 'The base used for the sub-carrier permutation in downlink PUSC zones: Integer[0..31] (0)'
  param :reportingbase, :bsname => 'sn_reporting_base', :name => '[reportingbase]', :oid => '1.3.6.1.4.1.989.1.16.2.7.3.1.1.92.1', :help => 'The base for SN reports from an MS. This value is sent to the MS in the REG-RSP message, for values other than 3: Integer[0..255] (3)'
  param :powercontrolmode, :bsname => 'power_control_mode', :name => '[powercontrolmode]', :oid => '1.3.6.1.4.1.989.1.16.2.7.3.1.1.102.1', :help => 'Power control mode for the sector as per PMC-REQ/RSP. Modes currently supported: CloseLoop(0) and OpenLoopPassiveOffsetSsRetention(1). Integer[0..3] (0)'
  param :niieperiod, :bsname => 'ni_ie_period', :name => '[niieperiod]', :oid => '1.3.6.1.4.1.989.1.16.2.7.3.1.1.103.1', :help => 'NI-IE (Uplink noise and interference level) period in frame numbers. For power control: Integer (32)'
  param :maxtxpowerbackoff, :bsname => 'max_tx_power_backoff', :name => '[maxtxpowerbackoff]', :oid => '1.3.6.1.4.1.989.1.16.2.7.3.1.1.107.1', :help => 'A backoff applied to the reported max transmit power of an MS, used to limit MS transmit powers and alter ULM behaviour: Integer (0)'
  param :carriersensehysteresis, :bsname => 'carrier_sense_hysteresis', :name => '[carriersensehysteresis]', :oid => '1.3.6.1.4.1.989.1.16.2.7.3.1.1.112.1', :help => 'The carrier sense detection hysteresis, relatively to the high detection threshold, defines the lower RSSI detection threshold: Integer[-1000..-100] (-500)'
  param :carriersenseperiod, :bsname => 'carrier_sense_measure_period', :name => '[carriersenseperiod]', :oid => '1.3.6.1.4.1.989.1.16.2.7.3.1.1.114.1', :help => 'Duration of each measurement period: Integer (229)'
  param :privmapmode, :bsname => 'private_map_mode', :name => '[privmapmode]', :oid => '1.3.6.1.4.1.989.1.16.2.7.3.1.1.115.1', :help => 'The type of compression to use on the private maps: Integer[0..1] (1)'
  param :fbscanenabled, :bsname => 'fb_scan_enabled', :name => '[fbscanenabled]', :oid => '1.3.6.1.4.1.989.1.16.2.7.3.1.1.118.1', :help => 'Allow the FB to intiate a scheduled scan: Boolean (false)'
end
