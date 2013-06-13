#
# Copyright (c) 2006-20011 National ICT Australia (NICTA), Australia
#
# Copyright (c) 2004-20011 - WINLAB, Rutgers University, USA
#
# Permission is hereby granted, free of charge, to any person obtaining a copy
# of this software and associated documentation files (the "Software"), to deal
# in the Software without restriction, including without limitation the rights
# to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
# copies of the Software, and to permit persons to whom the Software is
# furnished to do so, subject to the following conditions:
#
# The above copyright notice and this permission notice shall be included in
# all copies or substantial portions of the Software.
#
# THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
# IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
# FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT.  IN NO EVENT SHALL THE
# AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
# LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
# OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN
# THE SOFTWARE.
#
# = wimaxrf.rb
#
# == Description
#
require 'omf-aggmgr/ogs/legacyGridService'
require 'omf-aggmgr/ogs_wimaxrf/dpClick1.rb'
require 'omf-aggmgr/ogs_wimaxrf/dpOpenflow.rb'
require 'omf-aggmgr/ogs_wimaxrf/dpMFirst.rb'
require 'omf-aggmgr/ogs_wimaxrf/dbClasses'
require 'omf-aggmgr/ogs_wimaxrf/sftablesParser'
require 'omf-aggmgr/ogs_wimaxrf/util'
require 'omf-aggmgr/ogs_wimaxrf/authenticator'

WIMAXRF_DIR = File.expand_path(File.dirname(__FILE__))

class WimaxrfService < LegacyGridService
  # used to register/mount the service, the service's url will be based on it
  name 'wimaxrf'
  info 'Service to configure and control WiMAX (Basestation) RF Section'
  @@config = nil
  @dpath = {}

  #
  # Configure the service through a hash of options
  #
  # - config = the Hash holding the config parameters for this service
  #
  def self.configure(config)
    @@config = config
    ['bs', 'database', 'datapath'].each do |sect|
      raise("Missing configuration section \"#{sect}\" in wimaxrf.yaml") unless @@config[sect]
    end
    raise("Missing default_interface in wimaxrf.yaml") unless @@config['datapath']['default_interface']

    @auth = Authenticator.new

    dbFile = "#{WIMAXRF_DIR}/#{@@config['database']['dbFile']}"
    debug("Loading database file #{dbFile}")
    DataMapper.setup(:default, "sqlite://#{dbFile}")
    DataMapper.auto_upgrade!

    dpconfig = findAllDataPaths()
    dpconfig.each do |dpc|
      createDatapath(dpc)
    end
    @datapathif = @@config['datapath']['default_interface']
    @manageInterface = @@config['datapath']['manage_interface'] || false

    if @@config['bs']['type'] == 'airspan'
      require 'omf-aggmgr/ogs_wimaxrf/airspanbs.rb'
      @@bs = AirBs.new( @dpath, @auth, config['bs'], config['asngw'] )
      debug("wimaxrf", "Airspan basestation loaded")
    else
      require 'omf-aggmgr/ogs_wimaxrf/necbs.rb'
      @@bs = NecBs.new( @dpath, @auth, config['bs'], config['asngw'] )
      debug("wimaxrf", "NEC basestation loaded")
    end

#    if not checkMandatoryParameters
#      #setMandatoryParameters
#    end
  end

#  eval(File.open("#{WIMAXRF_DIR}/necurls.rb").read)

  def self.findAllDataPaths()
    result = Datapath.all()
    dtps = Array.new
    result.each {|dtp|
      dtconf = Hash.new
      dtconf['vlan'] = dtp.vlan
      dtconf['type'] = dtp.type
      dtconf['name'] = dtp.name
      dtconf['interface'] = dtp.interface
      if dtp.dpattributes != nil
        dtp.dpattributes.each{|att| dtconf[att.name]=att.value }
      end
      dtps << dtconf
    }
    return dtps
  end

  # check database for datapath with vlan
  def self.checkDatapath(interface,vlan)
    result = Datapath.get(interface,vlan)
    if result
      return true
    else
      return false
    end
  end

  # check interfaces for vlan
  def self.checkIfDataPath(interface,vlan)
    result = `ifconfig | grep #{interface}.#{vlan}`
    if result.empty?
      # datapath does not exist
      return false
    else
      return true
    end
  end

  def self.checkInterface(interface)
    result = `ifconfig | grep #{interface}`
    if result.empty?
      # interface does not exist
      return false
    else
      return true
    end
  end


  #
  # Create new XML reply containing a given result value.
  # If the result is 'nil' or empty, set an error message in this reply.
  # Otherwise, call a block of commands to format the content of this reply
  # based on the result.
  #
  # - replyName = name of the new XML Reply object
  # - result = the result to store in this reply
  # - msg =  the error message to store in this reply, if result is nil or empty
  # - &block = the block of command to use to format the result
  #
  # [Return] a new XML tree
  #
  def self.buildXMLReply(replyName, result, msg, &block)
    root = REXML::Element.new("#{replyName}")
    if (result == :Error)
      addXMLElement(root, "ERROR", "Error when accessing the Inventory Database")
    elsif (result == nil || result.empty?)
    addXMLElement(root, "ERROR", "#{msg}")
    else
      yield(root, result)
    end
    return root
  end

  #
  # Create new XML element and add it to an existing XML tree
  #
  # - parent = the existing XML tree to add the new element to
  # - name = the name for the new XML element to add
  # - value =  the value for the new XML element to add
  #
  def self.addXMLElement(parent, name, value)
     el = parent.add_element(name)
     el.add_text(value)
  end

  def self.addXMLElementFromArray(parent,name,value)
    value.each { |val|
      if val.is_a?(Hash)
          el = parent.add_element(name)
          addXMLElementsFromHash(el,val, false)
        else
          if val.is_a?(Array)
            addXMLElementFromArray(parent,name,val)
          else
            el = parent.add_element(name)
            el.add_text(val)
          end
        end
    }
  end

  def self.addXMLElementsFromHash(parent, elems, isatt=true)
    m_isatt=isatt
    elems.each_pair { |key,val|
      if val.is_a?(Hash)
        m_isatt=false
      else
        m_isatt=isatt
      end
      if (m_isatt)
        parent.add_attribute(key,val)
      else
        if val.is_a?(Hash)
          el = parent.add_element(key)
          addXMLElementsFromHash(el,val, false)
        else
          if val.is_a?(Array)
            addXMLElementFromArray(parent,key,val)
          else
            el = parent.add_element(key)
            el.add_text(val)
          end
        end
       end
     }
  end

  def self.getAllParams(req)
    query = req.query()
    if query.has_key?('domain')
      query.delete('domain')
    end
    query
  end


  s_description "Get information about the Base Station"
  service 'bs/info' do |req, res|
    msgEmpty = "Failed to get basestation info"
    replyXML = buildXMLReply("STATUS", msgEmpty, msgEmpty) { |root, dummy|
      bsEl = root.add_element("BaseStation")
      addXMLElementsFromHash(bsEl,@@bs.get_info())
    }
    self.setResponse(res, replyXML)
  end

  s_description "Get status of WiMAX RF  service"
  service 'bs/status' do |req, res|
    msgEmpty = "Failed to get basestation status"
    replyXML = buildXMLReply("STATUS", msgEmpty, msgEmpty) { |root, dummy|
      bsEl = root.add_element("BaseStation")
      ifs = bsEl.add_element("Interfaces")
      addXMLElementsFromHash(ifs,@@bs.get_bs_interface_traffic())
      pdu = bsEl.add_element("Throughput")
      addXMLElementsFromHash(pdu,@@bs.get_bs_pdu_stats())
      mbEl = bsEl.add_element("Clients")

      #add_attribute_hash(mbEl)
    }
    self.setResponse(res, replyXML)
  end

#  s_description "setSingleDLMCS the Base Station"
#  s_param :mcs, 'mcs', 'Modulation-coding scheme'
#  service 'bs/setSingleDLMCS' do |req, res|
#    msgEmpty = "Failed to setSingleDLMCS basestation"
#    mcs = getParam(req, 'mcs')
#    value = mcs.to_i
#    ret = ""
#    ret = ret + @@bs.wiset(:dl_profile1, value)
#    value = 255
#    ret = ret + @@bs.wiset(:dl_profile2, value)
#    ret = ret + @@bs.wiset(:dl_profile3, value)
#    ret = ret + @@bs.wiset(:dl_profile4, value)
#    ret = ret + @@bs.wiset(:dl_profile5, value)
#    ret = ret + @@bs.wiset(:dl_profile6, value)
#    ret = ret + @@bs.wiset(:dl_profile7, value)
#    ret = ret + @@bs.wiset(:dl_profile8, value)
#    ret = ret + @@bs.wiset(:dl_profile9, value)
#    ret = ret + @@bs.wiset(:dl_profile10, value)
#    ret = ret + @@bs.wiset(:dl_profile11, value)
#    ret = ret + @@bs.wiset(:dl_profile12, value)
#    responseText = ret
#    res.body = responseText
#  end

#  s_description "setSingleULMCS the Base Station"
#  s_param :mcs, 'mcs', 'Modulation-coding scheme'
#  service 'bs/setSingleULMCS' do |req, res|
#    msgEmpty = "Failed to setSingleULMCS basestation"
#    mcs = getParam(req, 'mcs')
#    value = mcs.to_i
#    ret = ""
#    ret = ret + @@bs.wiset(:ul_profile1, value)
#    value = 255
#    ret = ret + @@bs.wiset(:ul_profile2, value)
#    ret = ret + @@bs.wiset(:ul_profile3, value)
#    ret = ret + @@bs.wiset(:ul_profile4, value)
#    ret = ret + @@bs.wiset(:ul_profile5, value)
#    ret = ret + @@bs.wiset(:ul_profile6, value)
#    ret = ret + @@bs.wiset(:ul_profile7, value)
#    ret = ret + @@bs.wiset(:ul_profile8, value)
#    ret = ret + @@bs.wiset(:ul_profile9, value)
#    ret = ret + @@bs.wiset(:ul_profile10, value)
#    responseText = ret
#    res.body = responseText
#  end

  s_description "Restart the Base Station"
  service 'bs/restart' do |req, res|
    msgEmpty = "Failed to restart basestation"
    responseText = @@bs.restart()
    res.body = responseText
  end

#  def self.checkAndSetParam( req, name, p )
#    if ((p[:name] =~ /\[/) != 0)
#     p "N=#{p[:name]} D=#{default} P=#{param}"
#     value = getParam(req,name)
#    else
#      value = getParamDef(req,name,p[:default])
#    end
#    if value
#      if (p[:type] == 'binary')
#        value = (value == "true") ? "1" : "0"
#      end
#      debug("Setting BS parameter #{p[:bsname]} to [#{value}]")
#      ret = @@bs.wiset(p[:bsname],value)
#      if ret =~ /Err/
#        error "Error setting #{name}"
#        raise "Error setting #{name}"
#      end
#      return true if ret =~ /reboot/
#    end
#    return false
#  end

#  def self.processServiceQuerry( servDef, req )
#    rst = false
#    servDef.each { |n,p|
#      rst ||= checkAndSetParam(req, n.to_s,p)
#    }
#    rst
#  end

#  def self.processServiceStatusOLD( servDef, req )
#    bsst = Hash.new
#    a = @@bs.wiget(servDef.getCategoryName)
#    a.each {|key, value|
#      bsst = bsst.merge(value)
#    }
#    #bsst = @@bs.wiget(servDef.getCategoryName)[servDef.getCategoryName]
#
#    p bsst
#    sst = {}
#    servDef.each { |n,p|
#      next unless p[:bsname]
#      if (p[:type] == 'binary')
#        sst[n.to_s] = bsst[p[:bsname]] == 1 ? "true" : "false"
#      else
#        if bsst[p[:bsname]]
#          sst[n.to_s] = bsst[p[:bsname]]
#        end
#      end
#    }
#    sst
#  end


#  def self.processServiceStatus( servDef, req )
#    bsst = Hash.new
#    query = getAllParams(req)
#    a = @@bs.wiget(servDef.getCategoryName)
#    a.each {|key, value|
#        bsst = bsst.merge(value)
#    }
#    #bsst = @@bs.wiget(servDef.getCategoryName)[servDef.getCategoryName]
#
#    p bsst
#    p query,query.empty?
#    sst = {}
#    servDef.each { |n,p|
#      p n,p[:bsname],query.has_key?(n.to_s)
#
#      #next unless p[:bsname]
#      next unless ( (p[:bsname] && (query.empty?)) || ((not query.empty?) && ( query.has_key?(n.to_s)) && (p[:bsname])))
#      param = Hash.new
#      if bsst[p[:bsname]] =~ /->/
#        b = bsst[p[:bsname]].split('->')
#        param['value'] = b[0].strip
#        c = b[1].split
#        param['afterreboot'] =  c[0].strip
#        if (p[:type] == 'binary')
#          param['afterreboot'] = param['afterreboot'] == "1" ? "true" : "false"
#        end
#      else
#        param['value'] = bsst[p[:bsname]]
#      end
#      if (p[:type] == 'binary')
#        param['value'] = param['value'] == "1" ? "true" : "false"
#        param['type'] = p[:type]
#      end
#       param['desc'] = p[:help]
#       sst[n.to_s] = param
#    }
#    sst
#  end

#  s_description "Get Basestation Static Parameter"
#  service 'bs/get' do |req, res|
#    query = getAllParams(req)
#    if not query.empty?
#      msgEmpty = "Failed to get basestation status"
#      #take first parameter
#      replyXML = buildXMLReply("STATUS", msgEmpty, msgEmpty) { |root, dummy|
#        bsEl = root.add_element("BaseStation")
#        query.each{|key,value|
#          addXMLElementsFromHash(bsEl,@@bs.wiget(key))
#        }
#      }
#      self.setResponse(res, replyXML)
#    else
#      raise HTTPStatus::BadRequest, "Missing parameter"
#    end
#  end


#  s_description "Set Basestation Static Parameter"
#  service 'bs/set' do |req, res|
#    query = getAllParams(req)
#    responseText=''
#    if not query.empty?
#      query.each{|key,value|
#        responseText = responseText+"\n"+@@bs.wiset(key,value)
#      }
#      res.body = responseText
#    else
#      raise HTTPStatus::BadRequest, "Missing parameter"
#    end
#  end

  def self.authorize(req, res)
   puts "Checking authorization"
   WEBrick::HTTPAuth.basic_auth(req, res, 'orbit') {|user, pass|
     # this block returns true if
     # authentication token is valid
     isAuth = user == 'gnome' && pass == 'super'
     puts "user: #{user} pw: #{pass} isAuth: #{isAuth}"
     isAuth
   }
   true
 end

# def self.findAttributeDef(name)
#   attDef=nil
#   NecBs::PARAMS_CLASSES.each {|pc|
#    claseName = eval pc
#    claseName.each { |n,p|
#      if name == p[:bsname]
#        attDef = p
#        break
#      end
#        }
#      }
#      attDef
#  end

#def self.setFromXml(docNew)
#  responseText=""
#  hash_conf = @@bs.wigetAll()
#  #to take BaseStation element
#  bsEl = docNew.root.elements["BaseStation"]
#  changed = false
#  if bsEl==nil
#    # report and error
#    responseText='BaseStation attribute is missing'
#  else
#    bsEl.elements.each {|c1|
#      #go trough all group of attributes
#      c1.elements.each {|c|
#        # go trough all attributes for the group
#        # find that attribute in current configuration
#
#        temp = hash_conf[c1.name][c.name]
#        if temp==nil
#          #report an error
#          responseText=responseText +"\n"+c.name+' is NOT valid attribute'
#        else
#          if !(c.text==temp)
#            changed = true
#            debug("Restore #{c.name} back to #{c.text}")
#            responseText = responseText +"\n"+"Change #{c.name} -> #{c.text} [OK]"
#            debug("#{c.name}")
#            attdef=findAttributeDef(c.name)
#            debug("#{attdef}")
#            if attdef == nil
#              @@bs.wiset(c.name,c.text)
#            else
#              if attdef[:type] == 'integer'
#                if c.text == c.text.to_i.to_s
#                  @@bs.wiset(c.name,c.text)
#                else
#                  if attdef[:conversion] !=nil
#                    cf = eval attdef[:conversion]
#                    newvalue = cf.call(c.text)
#                    @@bs.wiset(c.name,newvalue)
#                  end
#                end
#              else
#                @@bs.wiset(c.name,c.text)
#              end
#            end
#          end
#        end
#      }
#    }
#  end #if bsEl==nil
#    if changed
#      responseText = responseText +"\n"+"These parameters will be changed on reboot"
#    else
#      responseText = "No changes made - current configuration is the requested"
#    end
#    return responseText
#end


#def self.setMandatoryParameters
#  changed = false
#  responseText = ""
#  className = eval 'WirelessService'
#  p = className.getParam(:freq)
#  resultAll = @@bs.wiget(className.getCategoryName)
#  result = resultAll[className.getCategoryName]
#  if result[p[:bsname]].to_i != @@config['bs']['frequency'].to_i
#    @@bs.wiset(p[:bsname],@@config['bs']['frequency'])
#    responseText = responseText +"\n"+"Change #{p[:bsname]} -> #{@@config['bs']['frequency']} [OK]"
#    changed = true
#  end
#  className = eval 'UnexposedParams'
#  resultAll = @@bs.wiget(className.getCategoryName)
#  #resultAll is a hash of bs class categories
#  #we nedd to integrate all categories in one hash....
#  result = Hash.new
#  resultAll.each{|key,value|
#    result.merge!(value)
#  }
#  bsid = mac2Hex(@@config['bs']['bsid'])
#  asngwip = ip2Hex(@@config['asngw']['ip'])
#  asngwid = id2Hex(@@config['asngw']['id'])
#  asngwport = Integer((@@config['asngw']['port']).to_s)
#  p = className.getParam(:bsid)
#  if result[p[:bsname]].casecmp(bsid) != 0
#    @@bs.wiset(p[:bsname],bsid)
#    responseText = responseText +"\n"+"Change #{p[:bsname]} -> #{@@config['bs']['bsid']} [OK]"
#    changed = true
#  end
#  p = className.getParam(:gwepip)
#  if result[p[:bsname]].casecmp(asngwip) != 0
#    @@bs.wiset(p[:bsname],asngwip)
#    responseText = responseText +"\n"+"Change #{p[:bsname]} -> #{@@config['asngw']['ip']} [OK]"
#    changed = true
#  end
#  p = className.getParam(:gwepport)
#  if Integer(result[p[:bsname]]) != asngwport
#    @@bs.wiset(p[:bsname],asngwport)
#    responseText = responseText +"\n"+"Change #{p[:bsname]} -> #{@@config['asngw']['port']} [OK]"
#    changed = true
#  end
#  p = className.getParam(:gwdpip)
#  if result[p[:bsname]].casecmp(asngwip) != 0
#    @@bs.wiset(p[:bsname],asngwip)
#    responseText = responseText +"\n"+"Change #{p[:bsname]} -> #{@@config['asngw']['ip']} [OK]"
#    changed = true
#  end
#  p = className.getParam(:gwdpport)
#  if Integer(result[p[:bsname]]) != asngwport
#    @@bs.wiset(p[:bsname],asngwport)
#    responseText = responseText +"\n"+"Change #{p[:bsname]} -> #{@@config['asngw']['port']} [OK]"
#    changed = true
#  end
#  p = className.getParam(:authid)
#  if result[p[:bsname]].casecmp(asngwid) != 0
#    @@bs.wiset(p[:bsname],asngwid)
#    responseText = responseText +"\n"+"Change #{p[:bsname]} -> #{@@config['asngw']['id']} [OK]"
#    changed = true
#  end
#  p = className.getParam(:authip)
#  if result[p[:bsname]].casecmp(asngwip) != 0
#    @@bs.wiset(p[:bsname],asngwip)
#    responseText = responseText +"\n"+"Change #{p[:bsname]} -> #{@@config['asngw']['ip']} [OK]"
#    changed = true
#  end
#  p = className.getParam(:authport)
#  if Integer(result[p[:bsname]]) != asngwport
#    @@bs.wiset(p[:bsname],asngwport)
#    responseText = responseText +"\n"+"Change #{p[:bsname]} -> #{@@config['asngw']['port']} [OK]"
#    changed = true
#  end
#  p = className.getParam(:gwid)
#  if result[p[:bsname]].casecmp(asngwid) != 0
#    @@bs.wiset(p[:bsname],asngwid)
#    responseText = responseText +"\n"+"Change #{p[:bsname]} -> #{@@config['asngw']['id']} [OK]"
#    changed = true
#  end
#  p = className.getParam(:bsrxport)
#  if Integer(result[p[:bsname]]) != asngwport
#    @@bs.wiset(p[:bsname],asngwport)
#    responseText = responseText +"\n"+"Change #{p[:bsname]} -> #{@@config['asngw']['port']} [OK]"
#    changed = true
#  end
#  if changed
#    responseText = responseText +"\n"+"These mandatory parameters will be changed on reboot"
#  end
#  return responseText
#end

#def self.checkMandatoryParameters
#  debug("Mandatory parameters value check")
#  correct = true
#  className = eval 'WirelessService'
#  p = className.getParam(:freq)
#  resultAll = @@bs.wiget(className.getCategoryName)
#  result = resultAll[className.getCategoryName]
#  if result[p[:bsname]].to_i != @@config['bs']['frequency'].to_i
#    debug("#{result[p[:bsname]].to_i} FOR #{p[:bsname]} IS INCORRECT ")
#    correct = false
#  end
#  className = eval 'UnexposedParams'
#  resultAll = @@bs.wiget(className.getCategoryName)
#  #resultAll is a hash of bs class categories
#  #we nedd to integrate all categories in one hash....
#  result = Hash.new
#  resultAll.each{|key,value|
#    result.merge!(value)
#  }
#  bsid = mac2Hex(@@config['bs']['bsid'])
#  asngwip = ip2Hex(@@config['asngw']['ip'])
#  asngwid = id2Hex(@@config['asngw']['id'])
#  asngwport = Integer((@@config['asngw']['port']).to_s)
#  p = className.getParam(:bsid)
#  if result[p[:bsname]].casecmp(bsid) != 0
#    debug("#{result[p[:bsname]]} FOR #{p[:bsname]} IS INCORRECT, SHOULD BE #{@@config['bs']['bsid']}")
#    correct = false
#  end
#  p = className.getParam(:gwepip)
#  if result[p[:bsname]].casecmp(asngwip) != 0
#    debug("#{result[p[:bsname]]} FOR #{p[:bsname]} IS INCORRECT, SHOULD BE #{@@config['asngw']['ip']}")
#    correct = false
#  end
#  p = className.getParam(:gwepport)
#  if Integer(result[p[:bsname]]) != asngwport
#    debug("#{result[p[:bsname]]} FOR #{p[:bsname]} IS INCORRECT, SHOULD BE #{@@config['asngw']['port']}")
#    correct = false
#  end
#  p = className.getParam(:gwdpip)
#  if result[p[:bsname]].casecmp(asngwip) != 0
#    debug("#{result[p[:bsname]]} FOR #{p[:bsname]} IS INCORRECT, SHOULD BE #{@@config['asngw']['ip']}")
#    correct = false
#  end
#  p = className.getParam(:gwdpport)
#  if Integer(result[p[:bsname]]) != asngwport
#    debug("#{result[p[:bsname]]} FOR #{p[:bsname]} IS INCORRECT, SHOULD BE #{@@config['asngw']['port']}")
#    correct = false
#  end
#  p = className.getParam(:authid)
#  if result[p[:bsname]].casecmp(asngwid) != 0
#    debug("#{result[p[:bsname]]} FOR #{p[:bsname]} IS INCORRECT, SHOULD BE #{@@config['asngw']['id']}")
#    correct = false
#  end
#  p = className.getParam(:authip)
#  if result[p[:bsname]].casecmp(asngwip) != 0
#    debug("#{result[p[:bsname]]} FOR #{p[:bsname]} IS INCORRECT, SHOULD BE #{@@config['asngw']['ip']}")
#    correct = false
#  end
#  p = className.getParam(:authport)
#  if Integer(result[p[:bsname]]) != asngwport
#    debug("#{result[p[:bsname]]} FOR #{p[:bsname]} IS INCORRECT, SHOULD BE #{@@config['asngw']['port']}")
#    correct = false
#  end
#  p = className.getParam(:gwid)
#  if result[p[:bsname]].casecmp(asngwid) != 0
#    debug("#{result[p[:bsname]]} FOR #{p[:bsname]} IS INCORRECT, SHOULD BE #{@@config['asngw']['id']}")
#    correct = false
#  end
#  p = className.getParam(:bsrxport)
#  if Integer(result[p[:bsname]]) != asngwport
#    debug("#{result[p[:bsname]]} FOR #{p[:bsname]} IS INCORRECT, SHOULD BE #{@@config['asngw']['port']}")
#    correct = false
#  end
#  correct
#end


#  s_description "Restore Base Station parameters from default configuration"
#  service 'bs/default' do |req, res|
#    responseText=''
#    aFileName = "#{WIMAXRF_DIR}/#{@@config['reset']['file']}"
#    if File.file?(aFileName)
#      file = File.open(aFileName, "r")
#      input = file.read
#      file.close
#      docNew = REXML::Document.new(input.to_s)
#      responseText = setMandatoryParameters
#      responseText = responseText + setFromXml(docNew)
#    else
#      responseText = "Reset file #{aFileName} DOESN'T exist"
#    end
#   res.body = responseText
# end

  s_description "Add datapath....."
  s_param :vlan, 'vlan', 'Vlan number.'
  s_param :type, 'type', 'Type of datapath, can be: simple, click, mf and openflow '
  s_param :interface, '[interface]', 'Name of the ethernet card that hosts the VLAN'
  service 'datapath/add' do |req, res|
    vlan = getParam(req, 'vlan')
    type = getParam(req, 'type')
    params = getAllParams(req)
    if(req.query.has_key?('interface'))
      interface = getParam(req,'interface')
      params.delete('interface')
    else
      interface = @datapathif
    end
    params.delete('vlan')
    params.delete('type')
    res.body = addDataPath(vlan,type,interface,params)
  end

  def self.addDataPath(vlan,type,interface,params)
    success = true
    message = "Datapath #{interface} #{vlan} added"
    command = "vconfig add #{interface} #{vlan}"
    if not checkInterface(interface)
      return "Cannot create datapath; Interface #{interface} doesn't exist"
    end
    if @manageInterface
      if not checkIfDataPath(interface,vlan)
        if type == 'click'
          if vlan!='0' #not checkDatapath(interface,vlan) and
            if not system(command)
              success = false
              message = "Cannot create datapath; command #{command} failed with #{$?.exitstatus}"
            end
            if checkDatapath(interface,vlan)
              success = false
            end
          else
            message = "Datapath #{interface}.#{vlan} alerady exists"
          end
        end
      else
        message = "Datapath #{interface}.#{vlan} alerady exists"
      end
    else
      if not checkIfDataPath(interface,vlan)
        succes = false
        message = "Cannot create datapath; Interface #{interface}.#{vlan} doesn't exist"
      end
    end
    # add to database
    if success
      dpc = Hash.new
      begin
        newDP = Datapath.first_or_create({:vlan=>vlan,:interface=>interface},:type=>type)
        dpc['vlan'] = vlan
        dpc['type'] = type
        dpc['name'] = newDP.name
        params.each {|name,value|
          dpc[name] = value
          newDP.dpattributes.first_or_create(:name=>name,:value=>value,:vlan=>vlan)
        }
        newDP.save
        createDatapath(dpc)
      end
    end
    message
  end

  def self.createDatapath(dpc)
    debug("Creating datapath #{dpc['name']}")
    case dpc['type']
      when 'simple'
        @dpath[dpc['name'].to_s] = Click1Datapath.new(dpc)
      when 'click'
        @dpath[dpc['name'].to_s] = Click1Datapath.new(dpc)
      when 'mf'
        @dpath[dpc['name'].to_s] = MFirstDatapath.new(dpc)
      when 'openflow'
        @dpath[dpc['name'].to_s] = OpenFlowDatapath.new(dpc)
      else
        raise("Unknown datapath type \"#{dpc['type']}\" for vlan #{dpc['name']}")
    end
  end

  def self.deleteDataPath(vlan,interface)
    message = ''
    begin
      if vlan != '0'
        dp = Datapath.get(interface,vlan)
        if dp != nil
          # check is there any client with this vlan
          nodes = @auth.list_clients(interface,vlan)
          if nodes.empty?
            # if type click vconfig del
            if dp.type == 'click' and @manageInterface
              command = "vconfig rem #{interface}.#{vlan}"
              if not system(command)
                message = "Cannot delete datapath; command #{command} failed with #{$?.exitstatus}"
              end
            end
            dpname = dp.name
            if dp.destroy
              #remove from hash
              @dpath.delete(dpname)
              message = "Datapath #{interface}.#{vlan} deleted"
            else
                message = "Database ERROR for datapath #{vlan}"
             end
          else
            message = "Cannot delete datapath. There are still clients with vlan=#{vlan}."
          end
        else
          message = "Unknown datapath #{interface}.#{vlan}"
        end
      else
        raise("Cannot delete datapath 0")
      end
    rescue Exception => e
      message = e.message
    end
    message
  end

  s_description "Delete datapath....."
  s_param :vlan, 'vlan', 'Vlan number.'
  s_param :interface, 'interface', 'Name of the ethernet card that hosts the VLAN'
  service 'datapath/delete' do |req, res|
    vlan = getParam(req, 'vlan')
    interface = getParam(req, 'interface')
    # delete from database
    res.body = deleteDataPath(vlan,interface)
  end


  s_description "List all datapaths..."
  service 'datapath/list' do |req, res|
    dpaths = Datapath.all
    root = REXML::Element.new("DataPaths")
    if dpaths != nil
      dpaths.each do |dp|
        node = root.add_element("DataPath")
        node.add_attribute("vlan",dp.vlan )
        node.add_attribute("type", dp.type)
        node.add_attribute("interface", dp.interface)
        node.add_attribute("name", dp.name)
        dp.dpattributes.each do |att|
          addXMLElement(node,att.name,att.value)
        end
      end
    end
    setResponse(res, root)
  end

  def self.getDatapathStatus(interface,vlan)
    root = REXML::Element.new("DataPath")
    dpath = Datapath.first(:vlan => vlan,:interface=>interface)
    if dpath != nil
      root.add_attribute("vlan",dpath.vlan )
      root.add_attribute("type", dpath.type)
      root.add_attribute("interface", dpath.interface)
      root.add_attribute("name", dpath.name)
      dpath.dpattributes.each do |att|
        addXMLElement(root,att.name,att.value)
      end
      clients = @auth.list_clients(interface,vlan)
      cl = root.add_element("Clients")
      if clients != nil
        clients.each do |c|
          node = cl.add_element("client")
          node.add_attribute("macaddr",c.macaddr )
          node.add_attribute("ipaddress", c.ipaddress )
        end
      end
    end
    root
  end

  s_description "Datapath status..."
  s_param :vlan, 'vlan', 'Vlan number.'
  s_param :interface, 'interface', 'Name of the ethernet card that hosts the VLAN'
  service 'datapath/status' do |req, res|
    vlan = getParam(req, 'vlan')
    interface = getParam(req, 'interface')
    root = getDatapathStatus(interface,vlan)
    setResponse(res, root)
  end

   s_description "Clean all Datapaths "
  service 'datapath/clean' do |req, res|
    message =''
    @auth.del_all_clients
    dpaths = Datapath.all
    dpaths.each do |dp|
      message = message+"\n" + deleteDataPath(dp.vlan,dp.interface)
     end
    res.body = message
  end


  s_description "This service saves current datapath client configuration database."
  s_param :name, 'name', 'Name of status.'
  s_param :vlan, 'vlan', 'Vlan number.'
  s_param :interface, 'interface', 'Name of the ethernet card that hosts the VLAN'
  service 'datapath/config/save' do |req, res|
    name = getParam(req, :name.to_s)
    vlan = getParam(req, :vlan.to_s)
    interface = getParam(req, :interface.to_s)
    replyXML = getDatapathStatus(interface,vlan)
    begin
      conf = DataPathConfig.first_or_create({:name=>name}).update({:status=>replyXML.to_s,:vlan=>vlan})
    rescue Exception => ex
      replyXML = buildXMLReply("Clients", '', ex)
    end
    self.setResponse(res,replyXML)
 end

  def self.loadDataPath(docNew)
    #get datapath attributes from xml
    dp = docNew.elements["DataPath"]
    vlan = dp.attributes["vlan"]
    type = dp.attributes["type"]
    interface = dp.attributes["interface"]
    debug("#{vlan} #{type} #{interface} ")
    params = Hash.new
    dp.elements.each do |att|
      debug("#{att.name}")
      if (att.name <=> "Clients")!=0 #element Clients define clients not datapath attribute
        params[att.name]=att.text
      end
    end
    debug("#{params}")
    addDataPath(vlan,type,interface,params)
    clientsXml = dp.elements["Clients"]
    message = "Complete"
    message = loadClients(interface,vlan,clientsXml)
    debug("#{message}")
    message
  end

  s_description "This service load datapath client configuration from database."
  s_param :name, 'name', 'Name of client\'s status.'
  service 'datapath/config/load' do |req, res|
    name = getParam(req, :name.to_s)
    conf = DataPathConfig.first(:fields => [:status],:name => name)
    #if config end
    begin
      if conf != nil
    xmlConfig = conf.status
        docNew = REXML::Document.new(xmlConfig.to_s)
        #@auth.del_all_clients
        responseText = loadDataPath(docNew)
      else
        responseText = "There is no #{name} datapath configuration saved"
      end
    rescue Exception => ex
      responseText = ex
    end
    res.body = responseText
 end

 s_description "This service list all datapath client configurations from database."
  service 'datapath/config/list' do |req, res|
    msgEmpty = "There is no saved datapath configurations"
    result = DataPathConfig.all()
    listConfig = Array.new
    result.each {|conf|
      listConfig << conf.name
    }
    replyXML = buildXMLReply("Status", listConfig, msgEmpty){ |root, dummy|
      addXMLElementFromArray(root,"name",listConfig)
    }
    self.setResponse(res,replyXML)
 end

  s_description "This service deletes saved datapath client configuration from database."
  s_param :name, 'name', 'Name of configuration.'
  service 'datapath/config/delete' do |req, res|
    name = getParam(req, :name.to_s)
    conf = DataPathConfig.first(:name => name)
    if conf.destroy
      responseText = "Datapath configuration #{name} successfully deleted from database"
    else
      responseText = "There is no datapath configuration #{name} in database"
    end
    res.body = responseText
 end

 s_description "Show named datapath client configuration from database."
  s_param :name, 'name', 'Name of saved status.'
  service 'datapath/config/show' do |req, res|
    name = getParam(req, :name.to_s)
    conf = DataPathConfig.first(:fields => [:status],:name => name)
    if conf != nil
      xmlConfig = conf.status
      doc = REXML::Document.new(xmlConfig.to_s)
      self.setResponse(res,doc)
    else
      root = REXML::Element.new("DataPath")
      msg = "There is no #{name} datapath configuration saved"
      addXMLElement(root, "ERROR", "#{msg}")
      self.setResponse(res,root)
    end
 end

 s_description "Add client to datapath"
  s_param :vlan, 'vlan', 'Vlan number.'
  s_param :macaddr, 'macaddr', 'Mac address.'
  s_param :ipaddress, 'ipaddress', 'Mac address.'
  s_param :interface, 'interface', 'Interface.'
  service 'datapath/clients/add' do |req, res|
    macaddr = getParam(req, 'macaddr')
    vlan = getParam(req, 'vlan')
    ipaddress = getParam(req, 'ipaddress')
    interface = getParam(req, 'interface')
    begin
      if checkDatapath(interface,vlan)
        @auth.add_client(macaddr,interface,vlan, ipaddress)
        res.body = "Client added"
      else
        res.body = "Can not add client, datapath with vlan=#{vlan} does not exist"
      end
    rescue Exception => e
      res.body = e.message
    end
  end

  s_description "Delete client from datapath"
  s_param :macaddr, 'macaddr', 'Mac address.'
  service 'datapath/clients/delete' do |req, res|
    macaddr = getParam(req, 'macaddr')
    begin
      @auth.del_client(macaddr)
      res.body = "Client #{macaddr} deleted"
    rescue Exception => e
      res.body = e.message
    end
  end


  def self.loadClients(interface,vlan,docNew)
    message = " "
    begin
      clients = docNew.root.elements["Clients"].elements
      if clients==nil
        message << "NOT a valid datapath clients configuration"
      else
        message << "Load complete"
        clients.each {|c|
          if (c.attributes["macaddr"])
            macaddr = c.attributes["macaddr"]
            ipaddress = c.attributes["ipaddress"]
          client = @auth.get(macaddr)
          if not client
            @auth.add_client(macaddr,interface,vlan,ipaddress)
            message << "\nCLIENT "+ c.attributes["macaddr"] + ' ADDED'
          else
            modifyClient(macaddr,interface,vlan,ipaddress)
            message << "\nCLIENT "+ c.attributes["macaddr"] + ' MODIFIED'
          end
        end
      }
    end
    rescue Exception=>ex
      MObject.debug("#{ex}\n(at #{ex.backtrace})")
      message = ex
    end
    message
  end

  def self.modifyClient(macaddr,interface,vlan,ipaddress)
    aclient=@auth.get(macaddr)
    updateHash = Hash.new
    updateMobile=false
    message = " "
    if checkDatapath(interface,vlan)
      if aclient.vlan != vlan or aclient.interface != interface
        updateHash[:vlan]=vlan
        updateHash[:interface]=interface
        updateMobile=true
        message << "Vlan for #{macaddr} updated"
      end
    else
      message << "Can not modify client's vlan, datapath with interface=#{interface} and vlan=#{vlan} does not exist"
    end
    if ipaddress!=nil and ipaddress != aclient.ipaddress
      updateHash[:ipaddress]=ipaddress
      updateMobile=true
      message << "\nIP address for #{macaddr} updated"
    end
    if updateMobile
      @auth.update_client(macaddr,updateHash)
      # We should really check if anything changed before we do this!!!!!!
      @@bs.modifyMobile(macaddr)
    end
    message
  end


  s_description "Modify client's vlan and/or IP address..."
  s_param :vlan, '[vlan]', 'Vlan number.'
  s_param :interface, '[interface]', 'Interface.'
  s_param :ipaddress, '[ipaddress]', 'IP address.'
  s_param :macaddr, 'macaddr', 'Mac address.'
  service 'datapath/clients/modify' do |req, res|
    macaddr = getParam(req, 'macaddr')
    message = "modifyClient: "
    aclient=@auth.get(macaddr)
    begin
      if aclient
        if req.query.has_key?('vlan')
          vlan = getParam(req, 'vlan')
        else
          vlan = aclient.vlan
        end
        if req.query.has_key?('interface')
          interface = getParam(req, 'interface')
        else
          interface = aclient.interface
        end
        if(req.query.has_key?('ipaddress'))
          ipaddress = getParam(req, 'ipaddress')
        else
          ipaddress =nil
        end
        message <<  modifyClient(macaddr,interface,vlan,ipaddress)
      else
        message << "There is no client with mac = #{macaddr}!"
      end
      res.body = message
    rescue Exception => e
      res.body = e.message
    end
  end

  s_description "Current datapaths client configuration"
  s_param :vlan, '[vlan]', 'Vlan number.'
  s_param :interface, '[interface]', 'Interface.'
  service 'datapath/clients/list' do |req, res|
  if(req.query.has_key?('vlan'))
      vlan = getParam(req,'vlan')
      interface = getParam(req, 'interface')
    else
      vlan = nil
      interface=nil
    end
    nodes = @auth.list_clients(interface,vlan)
    root = REXML::Element.new("Status")
    if nodes != nil
      nodes.each do |c|
        node = root.add_element("Client")
        node.add_attribute("macaddr",c.macaddr )
        node.add_attribute("vlan", c.vlan)
        node.add_attribute("interface", c.interface)
        node.add_attribute("ipaddress", c.ipaddress )
        node.add_attribute("dpname", c.dpname )
      end
    end
    setResponse(res, root)
  end


#  #services defind base on base station param classes
#  NecBs::PARAMS_CLASSES.each {|pc|
#    claseName = eval pc
#
#  s_description claseName.getInfo
#  claseName.each { |n,p|
#    s_param n,p[:name],p[:help]
#    p p[:name]
#  }
#  service "bs/"+claseName.getName do |req, res|
#    query = getAllParams(req)
#    query_string = req.query_string()
#    if ((not query.empty?) && (query_string.include? "="))
#      begin
#        if processServiceQuerry( claseName, req )
#          res.body = "BS needs to be rebooted for changes to take effect"
#        else
#          res.body = "OK"
#        end
#      rescue Exception => e
#        res.body = e.message
#      end
#    else
#      msgEmpty = "Failed to get basestation status"
#      replyXML = buildXMLReply("STATUS", msgEmpty, msgEmpty) { |root, dummy|
#        bsEl = root.add_element(claseName.getName.capitalize())
#        harqst = processServiceStatus( claseName, req )
#        addXMLElementsFromHash(bsEl,harqst)
#      }
#      self.setResponse(res, replyXML)
#    end
#  end
#    }

#  s_description "Set/Get Modulation-coding scheme."
#  s_param :dl, '[dl]', 'Array of Dl link profile specification.'
#  s_param :ul, '[ul]', 'Array of Up link profile specification.'
#  service 'bs/mcsProfile' do |req, res|
#    isget=true
#    ret =""
#    if(req.query.has_key?('dl'))
#      dl = getParam(req,'dl')
#      isget = false
#      ret = ret + setULorDL("dl_profile",12,dl)
#    end
#    if(req.query.has_key?('ul'))
#      ul = getParam(req,'ul')
#      isget = false
#      ret = ret + setULorDL("ul_profile",10,ul)
#    end
#    if isget
#      #get DL/UL values
#      root = REXML::Element.new("MCSProfile")
#      dl_profile = getULorDL("dl_profile",12)
#      ul_profile = getULorDL("ul_profile",10)
#      root.elements <<  dl_profile
#      root.elements <<  ul_profile
#      self.setResponse(res, root)
#    else
#      responseText = ret
#      res.body = responseText
#    end
#  end

#  def self.setULorDL(name,no,listOfValues)
#    profileValues = listOfValues.split(",")
#    #profilesValues.sort!
#    d_value = 255
#    i=1
#    ret = ""
#    profileValues.each { |value|
#      key = (name+i.to_s).to_sym
#      ret = ret + @@bs.wiset(key, value)
#      i+=1
#    }
#    for k in i..no
#      key = (name+k.to_s).to_sym
#      @@bs.wiset(key, d_value)
#    end
#    return ret
#  end

#  def self.getULorDL(name,no)
#    d_value = 255
#    i=1
#    root = REXML::Element.new("#{name}")
#    for k in 1..no
#      key = (name+k.to_s)
#      result = @@bs.wiget(key)
#      category = result[key]
#      element = category[key]
#      index1 = element.rindex("(")+1
#      index2 = element.rindex(")")
#      value = element[index1..index2].to_i
#      if value != d_value
#        addXMLElement(root, key, value.to_s)
#      end
#    end
#    return root
#  end


    #------------ talk to db ---------------#

#  s_description "This service saves current BS configuration to database."
#  s_param :name, 'name', 'Name of configuration.'
#  service 'bs/config/save' do |req, res|
#    name = getParam(req, :name.to_s)
#    msgEmpty = "Failed to get basestation status"
#    replyXML = buildXMLReply("STATUS", msgEmpty, msgEmpty) { |root, dummy|
#        bsEl = root.add_element("BaseStation")
#        addXMLElementsFromHash(bsEl,@@bs.wigetAll())
#      }
#    begin
#      conf = Configuration.first_or_create({:name=>name}).update({:configuration=>replyXML.to_s})
#    rescue Exception => ex
#      replyXML = buildXMLReply("Configuration", '', ex)
#    end
#    self.setResponse(res,replyXML)
# end

#  s_description "This service load BS configuration from database."
#  s_param :name, 'name', 'Name of configuration.'
#  service 'bs/config/load' do |req, res|
#    name = getParam(req, :name.to_s)
#    conf = Configuration.first(:fields => [:configuration],:name => name)
#    xmlConfig = conf.configuration
#
#    begin
#      if xmlConfig != nil
#        docNew = REXML::Document.new(xmlConfig.to_s)
#        responseText = setFromXml(docNew)
#      else
#        responseText = "There is no #{name} configuration"
#      end
#    rescue Exception => ex
#      responseText = ex
#    end
#    res.body = responseText
# end

# s_description "This service lists names of all BS configurations from database."
#  service 'bs/config/list' do |req, res|
#    msgEmpty = "There is no saved configurations"
#    result = Configuration.all()
#    listConfig = Array.new
#    result.each {|conf|
#      listConfig << conf.name
#    }
#    replyXML = buildXMLReply("Configurations", listConfig, msgEmpty){ |root, dummy|
#      addXMLElementFromArray(root,"name",listConfig)
#    }
#    self.setResponse(res,replyXML)
# end

#  s_description "This service deletes BS configuration from database."
#  s_param :name, 'name', 'Name of configuration.'
#  service 'bs/config/delete' do |req, res|
#    name = getParam(req, :name.to_s)
#    conf = Configuration.first(:name => name)
#    if conf.destroy
#      responseText = "Configuration #{name} successfully deleted"
#    else
#      responseText = "There is no configuration #{name}"
#    end
#    res.body = responseText
# end

# s_description "Show named BS configuration from database."
#  s_param :name, 'name', 'Name of configuration.'
#  service 'bs/config/show' do |req, res|
#    name = getParam(req, :name.to_s)
#    conf = Configuration.first(:fields => [:configuration],:name => name)
#    xmlConfig = conf.configuration
#    doc = REXML::Document.new(xmlConfig.to_s)
#    self.setResponse(res,doc)
# end
# # ---------- Implement sftables ------------------#
#  #        sftables -L
#  s_description "Show sftables list."
#  service 'sftables/status' do |req, res|
#    replyXML = SFTableParser.sftableList
#    self.setResponse(res,replyXML)
#  end

end
