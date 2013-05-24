
class Client
  # we should really keep some history rather then just the latest values
  attr_reader :mac,:snmp_mac           # Basic MAC addresses
  attr_accessor :ul, :dl, :vlan, :ip, :dpname   # Tunnels, VLAN and IP address
  # Measurements
  attr_accessor :basic_measurement,:extended_measurement
  attr_reader :tppduul,:tppdudl, :pduul, :pdudl, :tpsduul, :tpsdudl, :sduul, :sdudl, :mcsulrate, :mcsulmod, :mcsdlrate, :mcsdlmod, :rssi

  def initialize(m, basic, debug=nil)
    @mac = m
    @snmp_mac = to_snmp(m)
    @ip = nil
    @ul = nil
    @dl = nil
    @vlan = nil
    @dpname=nil
    @basic_measurement = Hash.new()
    @extended_measurement = Hash.new()
    @tppdudl = @tppduul = @tpsdudl = @tpsduul = 0
    @lastts = nil
    @debug = debug
  end

  def du_reading( pduul, pdudl, sduul, sdudl, ts=nil )
    ts = Time.now.to_f if ts.nil?   
    if !(@lastts.nil?)
      tdiff = ts - @lastts
      @tppdudl = 8.0 * (pdudl - @pdudl)/tdiff
      @tppduul = 8.0 * (pduul - @pduul)/tdiff
      @tpsdudl = 8.0 * (sdudl - @sdudl)/tdiff
      @tpsduul = 8.0 * (sduul - @sduul)/tdiff
    end
    @pdudl = pdudl
    @pduul = pduul 
    @sdudl = sdudl
    @sduul = sduul 
    @lastts = ts
  end

  def get_rate( mcs )
    rate, mod = case
    when mcs == 21
      [12100.0, "64QAM 5/6"]
    when mcs == 20
      [10500.0, "64QAM 3/4"]
    when mcs == 19
      [10000.0, "64QAM 2/3"]
    when mcs == 18
      [8700.0, "64QAM 1/2"]
    when mcs == 17
      [8700.0, "16QAM 3/4"]
    when mcs == 16
      [6180.0, "16QAM 1/2"]
    when mcs == 15
      [3390.0, "QPSK 3/4"]
    when mcs == 14
      [3000.0, "QPSK 1/2"]
    when mcs == 13
      [2000.0, "QPKS 1/2"]
    else
      [1000.0, "QPSK 1/2"]
    end
    return rate, mod
  end

  def mcs_reading( mcsul, mcsdl )
    @mcsulrate, @mcsulmod = get_rate(mcsul)
    @mcsdlrate, @mcsdlmod = get_rate(mcsdl)
  end

  def rssi_reading( rssi )
    @rssi = rssi
  end

  def to_string_mac(mac)
    raise "Invalid MAC" unless mac.length == 6
    mac.unpack("H2H2H2H2H2H2").join(":")
  end

  def to_snmp_mac(mac)
    raise "Invalid MAC #{mac}" unless mac.length == 6
    mac.unpack("CCCCCC").join(".")
  end

  def to_snmp( mac )
    mac.split(":").map{|s| s.to_i(16).to_s}.join(".")
  end


end
