require 'omf-common/mobject'
require 'rubygems'
require 'oml4r'

class OML4R::MPBase
  @@cver = {}

  def self.version(ver)
    @@cver[self] = ver
  end

  def self.get_ver
    @@cver[self]
  end
end

class CLStat < OML4R::MPBase
  version '01'
  name  :client
  channel :clstat

  param :ma
  param :mac
  param :ulrssi, :type => :double
  param :ulcinr, :type => :double
  param :dlrssi, :type => :double
  param :dlcinr, :type => :double
  param :mcsulmod
  param :mcsdlmod
end

#String, String, Float, Float, Float, Float, String, String

class BSStat < OML4R::MPBase
  version "02"
  name  :basestation
  channel :bsstat

  param :frequency, :type => :double
  param :power, :type => :double
  param :noclient, :type => :uint32
  param :ulsdu, :type => :double
  param :ulpdu, :type => :double
  param :dlsdu, :type => :double
  param :dlpdu, :type => :double
end
#Float, Float, Float, Float

OMLNAME = "wimaxrf"
OMLNAME1 = "#{OMLNAME}_client#{CLStat.get_ver()}"
OMLNAME2 = "#{OMLNAME}_bs#{BSStat.get_ver()}"

class Measurements < MObject
  attr_reader :lurl, :localinterval, :gurl, :globalinterval

  def initialize(bsid, logconfig)
    @enabled = true
    @lurl = "file:/var/log/#{OMLNAME1}.dat"
    @localinterval = 10
    @gurl = "file:/var/log/#{OMLNAME2}.dat"
    @globalinterval  = 300
    nID = bsid || Socket.gethostname
    opts = {
      :appName => OMLNAME,
      :domain => "GENI-#{OMLNAME}",
      :create_default_channel => false,
      :nodeID => nID
    }

    if logconfig then
      @enabled = logconfig['enabled'] if logconfig['enabled']

      if logconfig['localoml']
        @lurl = logconfig['localoml']['url'] if !logconfig['localoml']['url'].nil?
        @localinterval = logconfig['localoml']['interval'] if !logconfig['localoml']['interval'].nil?
      end

      if logconfig['globaloml']
        @gurl = logconfig['globaloml']['url'] if !logconfig['globaloml']['url'].nil?
        @globalinterval = logconfig['globaloml']['interval'] if !logconfig['globaloml']['interval'].nil?
      end
    end

    begin
      bss = OML4R::create_channel(:bsstat, @gurl)
      mbs = OML4R::create_channel(:clstat, @lurl)
      OML4R::init(nil, opts)
    rescue => ex
      raise "OML Initialization error for [#{@lurl},#{@gurl}]: #{ex.message}"
    end

    Kernel.at_exit {
      OML4R::close() if @enabled
    }
  end

  def bsstats(*args)
    return unless @enabled
    BSStat.inject(*args)
  end

  def clstats(*args)
    return unless @enabled
    CLStat.inject(*args)
  end

end
