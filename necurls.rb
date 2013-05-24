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
# = necursl.rb
#

  s_description "setSingleDLMCS the Base Station"
  s_param :mcs, 'mcs', 'Modulation-coding scheme'
  service 'bs/setSingleDLMCS' do |req, res|
    msgEmpty = "Failed to setSingleDLMCS basestation"
    mcs = getParam(req, 'mcs')
    value = mcs.to_i
    ret = ""
    ret = ret + @@bs.wiset(:dl_profile1, value)
    value = 255
    ret = ret + @@bs.wiset(:dl_profile2, value)
    ret = ret + @@bs.wiset(:dl_profile3, value)
    ret = ret + @@bs.wiset(:dl_profile4, value)
    ret = ret + @@bs.wiset(:dl_profile5, value)
    ret = ret + @@bs.wiset(:dl_profile6, value)
    ret = ret + @@bs.wiset(:dl_profile7, value)
    ret = ret + @@bs.wiset(:dl_profile8, value)
    ret = ret + @@bs.wiset(:dl_profile9, value)
    ret = ret + @@bs.wiset(:dl_profile10, value)
    ret = ret + @@bs.wiset(:dl_profile11, value)
    ret = ret + @@bs.wiset(:dl_profile12, value)
    responseText = ret
    res.body = responseText
  end

  s_description "setSingleULMCS the Base Station"
  s_param :mcs, 'mcs', 'Modulation-coding scheme'
  service 'bs/setSingleULMCS' do |req, res|
    msgEmpty = "Failed to setSingleULMCS basestation"
    mcs = getParam(req, 'mcs')
    value = mcs.to_i
    ret = ""
    ret = ret + @@bs.wiset(:ul_profile1, value)
    value = 255
    ret = ret + @@bs.wiset(:ul_profile2, value)
    ret = ret + @@bs.wiset(:ul_profile3, value)
    ret = ret + @@bs.wiset(:ul_profile4, value)
    ret = ret + @@bs.wiset(:ul_profile5, value)
    ret = ret + @@bs.wiset(:ul_profile6, value)
    ret = ret + @@bs.wiset(:ul_profile7, value)
    ret = ret + @@bs.wiset(:ul_profile8, value)
    ret = ret + @@bs.wiset(:ul_profile9, value)
    ret = ret + @@bs.wiset(:ul_profile10, value)
    responseText = ret
    res.body = responseText
  end

  s_description "Restart the Base Station"
  service 'bs/restart' do |req, res|
    msgEmpty = "Failed to restart basestation"
    responseText = @@bs.restart()
    res.body = responseText
  end

  def self.checkAndSetParam( req, name, p )
    if ((p[:name] =~ /\[/) != 0)
     p "N=#{p[:name]} D=#{default} P=#{param}" 
     value = getParam(req,name)
    else
      value = getParamDef(req,name,p[:default])
    end
    if value
      if (p[:type] == 'binary') 
        value = (value == "true") ? "1" : "0"
      end
      debug("Setting BS parameter #{p[:bsname]} to [#{value}]")
      ret = @@bs.wiset(p[:bsname],value)
      if ret =~ /Err/
        error "Error setting #{name}"
        raise "Error setting #{name}" 
      end 
      return true if ret =~ /reboot/
    end
    return false
  end

  def self.processServiceQuerry( servDef, req )
    rst = false
    servDef.each { |n,p|
      rst ||= checkAndSetParam(req, n.to_s,p)
    }
    rst
  end

  def self.processServiceStatusOLD( servDef, req )
    bsst = Hash.new
    a = @@bs.wiget(servDef.getCategoryName)
    a.each {|key, value|
      bsst = bsst.merge(value)
    }
    #bsst = @@bs.wiget(servDef.getCategoryName)[servDef.getCategoryName]
  
    p bsst
    sst = {}
    servDef.each { |n,p|
      next unless p[:bsname]
      if (p[:type] == 'binary') 
        sst[n.to_s] = bsst[p[:bsname]] == 1 ? "true" : "false"
      else
        if bsst[p[:bsname]] 
          sst[n.to_s] = bsst[p[:bsname]]
        end
      end
    }
    sst
  end


  def self.processServiceStatus( servDef, req )
    bsst = Hash.new
    query = getAllParams(req)
    a = @@bs.wiget(servDef.getCategoryName)
    a.each {|key, value|
        bsst = bsst.merge(value)
    }
    #bsst = @@bs.wiget(servDef.getCategoryName)[servDef.getCategoryName]
  
    p bsst
    p query,query.empty?
    sst = {}
    servDef.each { |n,p|
      p n,p[:bsname],query.has_key?(n.to_s)
      
      #next unless p[:bsname]
      next unless ( (p[:bsname] && (query.empty?)) || ((not query.empty?) && ( query.has_key?(n.to_s)) && (p[:bsname])))
      param = Hash.new
      if bsst[p[:bsname]] =~ /->/
        b = bsst[p[:bsname]].split('->')
        param['value'] = b[0].strip
        c = b[1].split
        param['afterreboot'] =  c[0].strip
        if (p[:type] == 'binary') 
          param['afterreboot'] = param['afterreboot'] == "1" ? "true" : "false"
        end
      else
        param['value'] = bsst[p[:bsname]]
      end
      if (p[:type] == 'binary') 
        param['value'] = param['value'] == "1" ? "true" : "false"
        param['type'] = p[:type]
      end
       param['desc'] = p[:help] 
       sst[n.to_s] = param
    }
    sst
  end

  s_description "Get Basestation Static Parameter"
  service 'bs/get' do |req, res|
    query = getAllParams(req)
    if not query.empty?        
      msgEmpty = "Failed to get basestation status"
      #take first parameter 
      replyXML = buildXMLReply("STATUS", msgEmpty, msgEmpty) { |root, dummy|
        bsEl = root.add_element("BaseStation")
        query.each{|key,value|
          addXMLElementsFromHash(bsEl,@@bs.wiget(key))
        }
      }
      self.setResponse(res, replyXML)
    else
      raise HTTPStatus::BadRequest, "Missing parameter"
    end    
  end
    

  s_description "Set Basestation Static Parameter"
  service 'bs/set' do |req, res|
    query = getAllParams(req)
    responseText=''
    if not query.empty?
      query.each{|key,value|
        responseText = responseText+"\n"+@@bs.wiset(key,value)
      }
      res.body = responseText
    else
      raise HTTPStatus::BadRequest, "Missing parameter"
    end
  end

 def self.findAttributeDef(name)
   attDef=nil
   NecBs::PARAMS_CLASSES.each {|pc|
    claseName = eval pc
    claseName.each { |n,p|
      if name == p[:bsname]
        attDef = p
        break
      end
        }
      }
      attDef
  end
 
def self.setFromXml(docNew)
  responseText=""
  hash_conf = @@bs.wigetAll()
  #to take BaseStation element
  bsEl = docNew.root.elements["BaseStation"]
  changed = false
  if bsEl==nil
    # report and error
    responseText='BaseStation attribute is missing'
  else
    bsEl.elements.each {|c1| 
      #go trough all group of attributes
      c1.elements.each {|c|
        # go trough all attributes for the group
        # find that attribute in current configuration
        
        temp = hash_conf[c1.name][c.name]
        if temp==nil
          #report an error
          responseText=responseText +"\n"+c.name+' is NOT valid attribute'
        else
          if !(c.text==temp)
            changed = true
            debug("Restore #{c.name} back to #{c.text}")
            responseText = responseText +"\n"+"Change #{c.name} -> #{c.text} [OK]"
            debug("#{c.name}")
            attdef=findAttributeDef(c.name)
            debug("#{attdef}")
            if attdef == nil
              @@bs.wiset(c.name,c.text)
            else
              if attdef[:type] == 'integer'
                if c.text == c.text.to_i.to_s
                  @@bs.wiset(c.name,c.text)
                else
                  if attdef[:conversion] !=nil
                    cf = eval attdef[:conversion]
                    newvalue = cf.call(c.text)
                    @@bs.wiset(c.name,newvalue)
                  end
                end
              else
                @@bs.wiset(c.name,c.text)
              end
            end
          end
        end
      }
    }
  end #if bsEl==nil
    if changed
      responseText = responseText +"\n"+"These parameters will be changed on reboot"
    else
      responseText = "No changes made - current configuration is the requested"
    end
    return responseText
end


def self.setMandatoryParameters
  changed = false
  responseText = ""
  className = eval 'WirelessService'
  p = className.getParam(:freq)
  resultAll = @@bs.wiget(className.getCategoryName)
  result = resultAll[className.getCategoryName]
  if result[p[:bsname]].to_i != @@config['bs']['frequency'].to_i
    @@bs.wiset(p[:bsname],@@config['bs']['frequency'])
    responseText = responseText +"\n"+"Change #{p[:bsname]} -> #{@@config['bs']['frequency']} [OK]"
    changed = true
  end
  className = eval 'UnexposedParams'
  resultAll = @@bs.wiget(className.getCategoryName)
  #resultAll is a hash of bs class categories
  #we nedd to integrate all categories in one hash....
  result = Hash.new
  resultAll.each{|key,value| 
    result.merge!(value)
  }
  bsid = mac2Hex(@@config['bs']['bsid'])
  asngwip = ip2Hex(@@config['asngw']['ip'])
  asngwid = id2Hex(@@config['asngw']['id'])
  asngwport = Integer((@@config['asngw']['port']).to_s)
  p = className.getParam(:bsid)
  if result[p[:bsname]].casecmp(bsid) != 0
    @@bs.wiset(p[:bsname],bsid)
    responseText = responseText +"\n"+"Change #{p[:bsname]} -> #{@@config['bs']['bsid']} [OK]"
    changed = true
  end
  p = className.getParam(:gwepip)
  if result[p[:bsname]].casecmp(asngwip) != 0
    @@bs.wiset(p[:bsname],asngwip)
    responseText = responseText +"\n"+"Change #{p[:bsname]} -> #{@@config['asngw']['ip']} [OK]"
    changed = true
  end
  p = className.getParam(:gwepport)
  if Integer(result[p[:bsname]]) != asngwport
    @@bs.wiset(p[:bsname],asngwport)
    responseText = responseText +"\n"+"Change #{p[:bsname]} -> #{@@config['asngw']['port']} [OK]"
    changed = true
  end
  p = className.getParam(:gwdpip)
  if result[p[:bsname]].casecmp(asngwip) != 0
    @@bs.wiset(p[:bsname],asngwip)
    responseText = responseText +"\n"+"Change #{p[:bsname]} -> #{@@config['asngw']['ip']} [OK]"
    changed = true
  end
  p = className.getParam(:gwdpport)
  if Integer(result[p[:bsname]]) != asngwport
    @@bs.wiset(p[:bsname],asngwport)
    responseText = responseText +"\n"+"Change #{p[:bsname]} -> #{@@config['asngw']['port']} [OK]"
    changed = true
  end
  p = className.getParam(:authid)
  if result[p[:bsname]].casecmp(asngwid) != 0
    @@bs.wiset(p[:bsname],asngwid)
    responseText = responseText +"\n"+"Change #{p[:bsname]} -> #{@@config['asngw']['id']} [OK]"
    changed = true
  end
  p = className.getParam(:authip)
  if result[p[:bsname]].casecmp(asngwip) != 0
    @@bs.wiset(p[:bsname],asngwip)
    responseText = responseText +"\n"+"Change #{p[:bsname]} -> #{@@config['asngw']['ip']} [OK]"
    changed = true
  end
  p = className.getParam(:authport)
  if Integer(result[p[:bsname]]) != asngwport
    @@bs.wiset(p[:bsname],asngwport)
    responseText = responseText +"\n"+"Change #{p[:bsname]} -> #{@@config['asngw']['port']} [OK]"
    changed = true
  end
  p = className.getParam(:gwid)
  if result[p[:bsname]].casecmp(asngwid) != 0
    @@bs.wiset(p[:bsname],asngwid)
    responseText = responseText +"\n"+"Change #{p[:bsname]} -> #{@@config['asngw']['id']} [OK]"
    changed = true
  end
  p = className.getParam(:bsrxport)
  if Integer(result[p[:bsname]]) != asngwport
    @@bs.wiset(p[:bsname],asngwport)
    responseText = responseText +"\n"+"Change #{p[:bsname]} -> #{@@config['asngw']['port']} [OK]"
    changed = true
  end
  if changed
    responseText = responseText +"\n"+"These mandatory parameters will be changed on reboot"
  end
  return responseText
end

def self.checkMandatoryParameters
  debug("Mandatory parameters value check")
  correct = true
  className = eval 'WirelessService'
  p = className.getParam(:freq)
  resultAll = @@bs.wiget(className.getCategoryName)
  result = resultAll[className.getCategoryName]
  if result[p[:bsname]].to_i != @@config['bs']['frequency'].to_i
    debug("#{result[p[:bsname]].to_i} FOR #{p[:bsname]} IS INCORRECT ")
    correct = false
  end
  className = eval 'UnexposedParams'
  resultAll = @@bs.wiget(className.getCategoryName)
  #resultAll is a hash of bs class categories
  #we nedd to integrate all categories in one hash....
  result = Hash.new
  resultAll.each{|key,value| 
    result.merge!(value)
  }
  bsid = mac2Hex(@@config['bs']['bsid'])
  asngwip = ip2Hex(@@config['asngw']['ip'])
  asngwid = id2Hex(@@config['asngw']['id'])
  asngwport = Integer((@@config['asngw']['port']).to_s)
  p = className.getParam(:bsid)
  if result[p[:bsname]].casecmp(bsid) != 0
    debug("#{result[p[:bsname]]} FOR #{p[:bsname]} IS INCORRECT, SHOULD BE #{@@config['bs']['bsid']}")
    correct = false
  end
  p = className.getParam(:gwepip)
  if result[p[:bsname]].casecmp(asngwip) != 0
    debug("#{result[p[:bsname]]} FOR #{p[:bsname]} IS INCORRECT, SHOULD BE #{@@config['asngw']['ip']}")
    correct = false
  end
  p = className.getParam(:gwepport)
  if Integer(result[p[:bsname]]) != asngwport
    debug("#{result[p[:bsname]]} FOR #{p[:bsname]} IS INCORRECT, SHOULD BE #{@@config['asngw']['port']}")
    correct = false
  end
  p = className.getParam(:gwdpip)
  if result[p[:bsname]].casecmp(asngwip) != 0
    debug("#{result[p[:bsname]]} FOR #{p[:bsname]} IS INCORRECT, SHOULD BE #{@@config['asngw']['ip']}")
    correct = false
  end
  p = className.getParam(:gwdpport)
  if Integer(result[p[:bsname]]) != asngwport
    debug("#{result[p[:bsname]]} FOR #{p[:bsname]} IS INCORRECT, SHOULD BE #{@@config['asngw']['port']}")
    correct = false
  end
  p = className.getParam(:authid)
  if result[p[:bsname]].casecmp(asngwid) != 0
    debug("#{result[p[:bsname]]} FOR #{p[:bsname]} IS INCORRECT, SHOULD BE #{@@config['asngw']['id']}")
    correct = false
  end
  p = className.getParam(:authip)
  if result[p[:bsname]].casecmp(asngwip) != 0
    debug("#{result[p[:bsname]]} FOR #{p[:bsname]} IS INCORRECT, SHOULD BE #{@@config['asngw']['ip']}")
    correct = false
  end
  p = className.getParam(:authport)
  if Integer(result[p[:bsname]]) != asngwport
    debug("#{result[p[:bsname]]} FOR #{p[:bsname]} IS INCORRECT, SHOULD BE #{@@config['asngw']['port']}")
    correct = false
  end
  p = className.getParam(:gwid)
  if result[p[:bsname]].casecmp(asngwid) != 0
    debug("#{result[p[:bsname]]} FOR #{p[:bsname]} IS INCORRECT, SHOULD BE #{@@config['asngw']['id']}")
    correct = false
  end
  p = className.getParam(:bsrxport)
  if Integer(result[p[:bsname]]) != asngwport
    debug("#{result[p[:bsname]]} FOR #{p[:bsname]} IS INCORRECT, SHOULD BE #{@@config['asngw']['port']}")
    correct = false
  end
  correct
end


  s_description "Restore Base Station parameters from default configuration"
  service 'bs/default' do |req, res|
    responseText=''
    aFileName = "#{CONF_DIR}/#{@@config['reset']['file']}"
    if File.file?(aFileName)
      file = File.open(aFileName, "r")
      input = file.read
      file.close
      docNew = REXML::Document.new(input.to_s)
      responseText = setMandatoryParameters
      responseText = responseText + setFromXml(docNew)
    else
      responseText = "Reset file #{aFileName} DOESN'T exist"
    end  
   res.body = responseText
 end
   
  #services defind base on base station param classes
  NecBs::PARAMS_CLASSES.each {|pc|
    claseName = eval pc
    
  s_description claseName.getInfo
  claseName.each { |n,p|
    s_param n,p[:name],p[:help]
    p p[:name]
  }
  service "bs/"+claseName.getName do |req, res|
    query = getAllParams(req)
    query_string = req.query_string()
    if ((not query.empty?) && (query_string.include? "="))
      begin 
        if processServiceQuerry( claseName, req )
          res.body = "BS needs to be rebooted for changes to take effect"
        else
          res.body = "OK"
        end         
      rescue Exception => e
        res.body = e.message
      end
    else   
      msgEmpty = "Failed to get basestation status"
      replyXML = buildXMLReply("STATUS", msgEmpty, msgEmpty) { |root, dummy|
        bsEl = root.add_element(claseName.getName.capitalize())
        harqst = processServiceStatus( claseName, req )
        addXMLElementsFromHash(bsEl,harqst)
      }
      self.setResponse(res, replyXML)
    end
  end
    }
    
  s_description "Set/Get Modulation-coding scheme."
  s_param :dl, '[dl]', 'Array of Dl link profile specification.'
  s_param :ul, '[ul]', 'Array of Up link profile specification.'
  service 'bs/mcsProfile' do |req, res|
    isget=true
    ret =""
    if(req.query.has_key?('dl'))
      dl = getParam(req,'dl')
      isget = false
      ret = ret + setULorDL("dl_profile",12,dl)
    end
    if(req.query.has_key?('ul'))
      ul = getParam(req,'ul')
      isget = false
      ret = ret + setULorDL("ul_profile",10,ul)
    end
    if isget
      #get DL/UL values
      root = REXML::Element.new("MCSProfile")
      dl_profile = getULorDL("dl_profile",12)
      ul_profile = getULorDL("ul_profile",10)
      root.elements <<  dl_profile
      root.elements <<  ul_profile
      self.setResponse(res, root)
    else
      responseText = ret
      res.body = responseText
    end
  end
  
  def self.setULorDL(name,no,listOfValues)
    profileValues = listOfValues.split(",")
    #profilesValues.sort!
    d_value = 255
    i=1
    ret = ""
    profileValues.each { |value|
      key = (name+i.to_s).to_sym
      ret = ret + @@bs.wiset(key, value)
      i+=1
    }
    for k in i..no
      key = (name+k.to_s).to_sym
      @@bs.wiset(key, d_value)
    end
    return ret
  end
  
  def self.getULorDL(name,no)
    d_value = 255
    i=1
    root = REXML::Element.new("#{name}")
    for k in 1..no
      key = (name+k.to_s)
      result = @@bs.wiget(key)
      category = result[key]
      element = category[key]
      index1 = element.rindex("(")+1
      index2 = element.rindex(")")
      value = element[index1..index2].to_i
      if value != d_value
        addXMLElement(root, key, value.to_s)
      end
    end
    return root
  end
  
    
    #------------ talk to db ---------------#
    
  s_description "This service saves current BS configuration to database."
  s_param :name, 'name', 'Name of configuration.'
  service 'bs/config/save' do |req, res|
    name = getParam(req, :name.to_s)
    msgEmpty = "Failed to get basestation status"
    replyXML = buildXMLReply("STATUS", msgEmpty, msgEmpty) { |root, dummy|
        bsEl = root.add_element("BaseStation")
        addXMLElementsFromHash(bsEl,@@bs.wigetAll())
      }
    begin
      conf = Configuration.first_or_create({:name=>name}).update({:configuration=>replyXML.to_s})
    rescue Exception => ex
      replyXML = buildXMLReply("Configuration", '', ex)
    end
    self.setResponse(res,replyXML)
 end
 
  s_description "This service load BS configuration from database."
  s_param :name, 'name', 'Name of configuration.'
  service 'bs/config/load' do |req, res|
    name = getParam(req, :name.to_s)
    conf = Configuration.first(:fields => [:configuration],:name => name)
    xmlConfig = conf.configuration
    
    begin
      if xmlConfig != nil
        docNew = REXML::Document.new(xmlConfig.to_s)
        responseText = setFromXml(docNew)
      else
        responseText = "There is no #{name} configuration"
      end
    rescue Exception => ex
      responseText = ex
    end
    res.body = responseText
 end
  
 s_description "This service lists names of all BS configurations from database."
  service 'bs/config/list' do |req, res|
    msgEmpty = "There is no saved configurations"
    result = Configuration.all()
    listConfig = Array.new
    result.each {|conf|
      listConfig << conf.name
    }
    replyXML = buildXMLReply("Configurations", listConfig, msgEmpty){ |root, dummy|
      addXMLElementFromArray(root,"name",listConfig)
    }
    self.setResponse(res,replyXML)
 end
 
  s_description "This service deletes BS configuration from database."
  s_param :name, 'name', 'Name of configuration.'
  service 'bs/config/delete' do |req, res|
    name = getParam(req, :name.to_s)
    conf = Configuration.first(:name => name)
    if conf.destroy
      responseText = "Configuration #{name} successfully deleted"
    else
      responseText = "There is no configuration #{name}"
    end
    res.body = responseText
 end
 
 s_description "Show named BS configuration from database."
  s_param :name, 'name', 'Name of configuration.'
  service 'bs/config/show' do |req, res|
    name = getParam(req, :name.to_s)
    conf = Configuration.first(:fields => [:configuration],:name => name)
    xmlConfig = conf.configuration
    doc = REXML::Document.new(xmlConfig.to_s)
    self.setResponse(res,doc)
 end
 # ---------- Implement sftables ------------------#
  #        sftables -L
  s_description "Show sftables list."
  service 'sftables/status' do |req, res|
    replyXML = SFTableParser.sftableList
    self.setResponse(res,replyXML)
  end
  

