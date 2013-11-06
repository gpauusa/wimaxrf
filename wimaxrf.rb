#
# Copyright (c) 2006-2011 National ICT Australia (NICTA), Australia
# Copyright (c) 2004-2013 WINLAB, Rutgers University, USA
# Copyright (c) 2012-2013 University of California, Los Angeles, USA
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
require 'omf-aggmgr/ogs_wimaxrf/authenticator'
require 'omf-aggmgr/ogs_wimaxrf/dbClasses'
require 'omf-aggmgr/ogs_wimaxrf/mobileClients'
require 'omf-aggmgr/ogs_wimaxrf/util'

WIMAXRF_DIR = File.expand_path(File.dirname(__FILE__))

class WimaxrfService < LegacyGridService
  # used to register/mount the service, the service's url will be based on it
  name 'wimaxrf'
  info serviceName, 'Service to configure and control WiMAX (Base Station) RF Section'

  #
  # Configure the service through a hash of options
  #
  # - config = the Hash holding the config parameters for this service
  #
  def self.configure(config)
    @config = config
    %w(bs database datapath).each do |sect|
      raise("Missing configuration section '#{sect}' in wimaxrf.yaml") unless @config[sect]
    end
    @bstype = @config['bs']['type'].to_s.downcase
    raise("'type' cannot be empty in 'bs' section in wimaxrf.yaml") if @bstype.empty?
    @manageInterface = !!@config['datapath']['manage_interface']

    # load database
    dbFile = "#{WIMAXRF_DIR}/#{@config['database']['dbFile']}"
    debug(serviceName, "Loading database file #{dbFile}")
    DataMapper.setup(:default, "sqlite://#{dbFile}")
    DataMapper.auto_upgrade!

    # create datapaths
    @dpath = {}
    Datapath.all.each do |dp|
      begin
        @dpath[dp.name] = createDataPath(dp)
      rescue => e
        error(serviceName, "Failed to create #{dp.name} datapath: #{e.message}")
      end
    end

    @auth = Authenticator.new
    @mobs = MobileClients.new(@auth, @dpath)

    # load BS management module
    debug(serviceName, "Loading #{@bstype.capitalize} base station module")
    require "omf-aggmgr/ogs_wimaxrf/#{@bstype}bs"
    @bs = Kernel.const_get("#{@bstype.capitalize}Bs").new(@mobs, @config['bs'])

    @auth.bs = @bs
    initMethods

#    if not checkMandatoryParameters
#      #setMandatoryParameters
#    end
  end

  # check database for datapath with given interface and vlan
  def self.datapathExists?(interface, vlan)
    !!Datapath.get(interface, vlan)
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
    if result == :Error
      addXMLElement(root, "ERROR", "Error when accessing the Inventory Database")
    elsif result == nil || result.empty?
      addXMLElement(root, "ERROR", "#{msg}")
    else
      yield(root, result)
    end
    root
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
    m_isatt = isatt
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
    query = req.query
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
      addXMLElementsFromHash(bsEl,@bs.get_info())
    }
    self.setResponse(res, replyXML)
  end

  s_description "Get status of WiMAX RF service"
  service 'bs/status' do |req, res|
    msgEmpty = "Failed to get basestation status"
    replyXML = buildXMLReply("STATUS", msgEmpty, msgEmpty) { |root, dummy|
      bsEl = root.add_element("BaseStation")
      ifs = bsEl.add_element("Interfaces")
      addXMLElementsFromHash(ifs,@bs.get_bs_interface_traffic())
      pdu = bsEl.add_element("Throughput")
      addXMLElementsFromHash(pdu,@bs.get_bs_pdu_stats())
      mbEl = bsEl.add_element("Clients")
      #add_attribute_hash(mbEl)
    }
    self.setResponse(res, replyXML)
  end

  s_description "Restart the Base Station"
  service 'bs/restart' do |req, res|
    msgEmpty = "Failed to restart basestation"
    responseText = @bs.restart()
    setResponsePlainText(res, responseText)
  end


  def self.processServiceQuery( servDef, req )
    rst = false
    servDef.each { |n,p|
      if ((p[:name] =~ /\[/) != 0)
        value = getParam(req,n)
      else
        value = getParamDef(req,n,p[:default])
      end
      rst ||= @bs.checkAndSetParam(value, n.to_s,p)
    }
    rst
  end


  s_description "Get Basestation Static Parameter"
  service 'bs/get' do |req, res|
    query = getAllParams(req)
    if not query.empty?
      msgEmpty = "Failed to get basestation status"
      #take first parameter
      replyXML = buildXMLReply("STATUS", msgEmpty, msgEmpty) { |root, dummy|
        bsEl = root.add_element("BaseStation")
        query.each { |key,value| addXMLElementsFromHash(bsEl,@bs.get(key)) }
      }
      self.setResponse(res, replyXML)
    else
      raise HTTPStatus::BadRequest, "Missing parameter"
    end
  end

  s_description "Set Basestation Static Parameter"
  service 'bs/set' do |req, res|
    query = getAllParams(req)
    responseText = ''
    if not query.empty?
      query.each { |key,value| responseText = responseText+"\n"+@bs.set(key,value) }
      res.body = responseText
    else
      raise HTTPStatus::BadRequest, "Missing parameter"
    end
  end

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

  def self.findAttributeDef(name)
    attDef = nil
    @bs.class.const_get('PARAMS_CLASSES').each do |pc|
      className = Kernel.const_get(pc)
      className.each { |n, p|
        if name == p[:bsname]
          attDef = p
          break
        end
      }
    end
    attDef
  end

#def self.setFromXml(docNew)
#  responseText=""
#  hash_conf = @bs.wigetAll()
#  #to take BaseStation element
#  bsEl = docNew.root.elements["BaseStation"]
#  changed = false
#  if bsEl==nil
#    # report and error
#    responseText='BaseStation attribute is missing'
#  else
#    bsEl.elements.each { |c1|
#      #go trough all group of attributes
#      c1.elements.each { |c|
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
#            debug(serviceName, "Restore #{c.name} back to #{c.text}")
#            responseText = responseText +"\n"+"Change #{c.name} -> #{c.text} [OK]"
#            debug(serviceName, "#{c.name}")
#            attdef=findAttributeDef(c.name)
#            debug(serviceName, "#{attdef}")
#            if attdef == nil
#              @bs.wiset(c.name,c.text)
#            else
#              if attdef[:type] == 'integer'
#                if c.text == c.text.to_i.to_s
#                  @bs.wiset(c.name,c.text)
#                else
#                  if attdef[:conversion] !=nil
#                    cf = eval attdef[:conversion]
#                    newvalue = cf.call(c.text)
#                    @bs.wiset(c.name,newvalue)
#                  end
#                end
#              else
#                @bs.wiset(c.name,c.text)
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
#    responseText
#end


#def self.setMandatoryParameters
#  changed = false
#  responseText = ""
#  className = eval 'WirelessService'
#  p = className.getParam(:freq)
#  resultAll = @bs.wiget(className.getCategoryName)
#  result = resultAll[className.getCategoryName]
#  if result[p[:bsname]].to_i != @config['bs']['frequency'].to_i
#    @bs.wiset(p[:bsname],@config['bs']['frequency'])
#    responseText = responseText +"\n"+"Change #{p[:bsname]} -> #{@config['bs']['frequency']} [OK]"
#    changed = true
#  end
#  className = eval 'UnexposedParams'
#  resultAll = @bs.wiget(className.getCategoryName)
#  #resultAll is a hash of bs class categories
#  #we nedd to integrate all categories in one hash....
#  result = {}
#  resultAll.each { |key,value| result.merge!(value) }
#  bsid = mac2Hex(@config['bs']['bsid'])
#  asngwip = ip2Hex(@config['asngw']['ip'])
#  asngwid = id2Hex(@config['asngw']['id'])
#  asngwport = Integer((@config['asngw']['port']).to_s)
#  p = className.getParam(:bsid)
#  if result[p[:bsname]].casecmp(bsid) != 0
#    @bs.wiset(p[:bsname],bsid)
#    responseText = responseText +"\n"+"Change #{p[:bsname]} -> #{@config['bs']['bsid']} [OK]"
#    changed = true
#  end
#  p = className.getParam(:gwepip)
#  if result[p[:bsname]].casecmp(asngwip) != 0
#    @bs.wiset(p[:bsname],asngwip)
#    responseText = responseText +"\n"+"Change #{p[:bsname]} -> #{@config['asngw']['ip']} [OK]"
#    changed = true
#  end
#  p = className.getParam(:gwepport)
#  if Integer(result[p[:bsname]]) != asngwport
#    @bs.wiset(p[:bsname],asngwport)
#    responseText = responseText +"\n"+"Change #{p[:bsname]} -> #{@config['asngw']['port']} [OK]"
#    changed = true
#  end
#  p = className.getParam(:gwdpip)
#  if result[p[:bsname]].casecmp(asngwip) != 0
#    @bs.wiset(p[:bsname],asngwip)
#    responseText = responseText +"\n"+"Change #{p[:bsname]} -> #{@config['asngw']['ip']} [OK]"
#    changed = true
#  end
#  p = className.getParam(:gwdpport)
#  if Integer(result[p[:bsname]]) != asngwport
#    @bs.wiset(p[:bsname],asngwport)
#    responseText = responseText +"\n"+"Change #{p[:bsname]} -> #{@config['asngw']['port']} [OK]"
#    changed = true
#  end
#  p = className.getParam(:authid)
#  if result[p[:bsname]].casecmp(asngwid) != 0
#    @bs.wiset(p[:bsname],asngwid)
#    responseText = responseText +"\n"+"Change #{p[:bsname]} -> #{@config['asngw']['id']} [OK]"
#    changed = true
#  end
#  p = className.getParam(:authip)
#  if result[p[:bsname]].casecmp(asngwip) != 0
#    @bs.wiset(p[:bsname],asngwip)
#    responseText = responseText +"\n"+"Change #{p[:bsname]} -> #{@config['asngw']['ip']} [OK]"
#    changed = true
#  end
#  p = className.getParam(:authport)
#  if Integer(result[p[:bsname]]) != asngwport
#    @bs.wiset(p[:bsname],asngwport)
#    responseText = responseText +"\n"+"Change #{p[:bsname]} -> #{@config['asngw']['port']} [OK]"
#    changed = true
#  end
#  p = className.getParam(:gwid)
#  if result[p[:bsname]].casecmp(asngwid) != 0
#    @bs.wiset(p[:bsname],asngwid)
#    responseText = responseText +"\n"+"Change #{p[:bsname]} -> #{@config['asngw']['id']} [OK]"
#    changed = true
#  end
#  p = className.getParam(:bsrxport)
#  if Integer(result[p[:bsname]]) != asngwport
#    @bs.wiset(p[:bsname],asngwport)
#    responseText = responseText +"\n"+"Change #{p[:bsname]} -> #{@config['asngw']['port']} [OK]"
#    changed = true
#  end
#  if changed
#    responseText = responseText +"\n"+"These mandatory parameters will be changed on reboot"
#  end
#  responseText
#end

#def self.checkMandatoryParameters
#  debug(serviceName, "Mandatory parameters value check")
#  correct = true
#  className = eval 'WirelessService'
#  p = className.getParam(:freq)
#  resultAll = @bs.wiget(className.getCategoryName)
#  result = resultAll[className.getCategoryName]
#  if result[p[:bsname]].to_i != @config['bs']['frequency'].to_i
#    debug(serviceName, "#{result[p[:bsname]].to_i} FOR #{p[:bsname]} IS INCORRECT ")
#    correct = false
#  end
#  className = eval 'UnexposedParams'
#  resultAll = @bs.wiget(className.getCategoryName)
#  #resultAll is a hash of bs class categories
#  #we nedd to integrate all categories in one hash....
#  result = {}
#  resultAll.each { |key,value| result.merge!(value) }
#  bsid = mac2Hex(@config['bs']['bsid'])
#  asngwip = ip2Hex(@config['asngw']['ip'])
#  asngwid = id2Hex(@config['asngw']['id'])
#  asngwport = Integer((@config['asngw']['port']).to_s)
#  p = className.getParam(:bsid)
#  if result[p[:bsname]].casecmp(bsid) != 0
#    debug(serviceName, "#{result[p[:bsname]]} FOR #{p[:bsname]} IS INCORRECT, SHOULD BE #{@config['bs']['bsid']}")
#    correct = false
#  end
#  p = className.getParam(:gwepip)
#  if result[p[:bsname]].casecmp(asngwip) != 0
#    debug(serviceName, "#{result[p[:bsname]]} FOR #{p[:bsname]} IS INCORRECT, SHOULD BE #{@config['asngw']['ip']}")
#    correct = false
#  end
#  p = className.getParam(:gwepport)
#  if Integer(result[p[:bsname]]) != asngwport
#    debug(serviceName, "#{result[p[:bsname]]} FOR #{p[:bsname]} IS INCORRECT, SHOULD BE #{@config['asngw']['port']}")
#    correct = false
#  end
#  p = className.getParam(:gwdpip)
#  if result[p[:bsname]].casecmp(asngwip) != 0
#    debug(serviceName, "#{result[p[:bsname]]} FOR #{p[:bsname]} IS INCORRECT, SHOULD BE #{@config['asngw']['ip']}")
#    correct = false
#  end
#  p = className.getParam(:gwdpport)
#  if Integer(result[p[:bsname]]) != asngwport
#    debug(serviceName, "#{result[p[:bsname]]} FOR #{p[:bsname]} IS INCORRECT, SHOULD BE #{@config['asngw']['port']}")
#    correct = false
#  end
#  p = className.getParam(:authid)
#  if result[p[:bsname]].casecmp(asngwid) != 0
#    debug(serviceName, "#{result[p[:bsname]]} FOR #{p[:bsname]} IS INCORRECT, SHOULD BE #{@config['asngw']['id']}")
#    correct = false
#  end
#  p = className.getParam(:authip)
#  if result[p[:bsname]].casecmp(asngwip) != 0
#    debug(serviceName, "#{result[p[:bsname]]} FOR #{p[:bsname]} IS INCORRECT, SHOULD BE #{@config['asngw']['ip']}")
#    correct = false
#  end
#  p = className.getParam(:authport)
#  if Integer(result[p[:bsname]]) != asngwport
#    debug(serviceName, "#{result[p[:bsname]]} FOR #{p[:bsname]} IS INCORRECT, SHOULD BE #{@config['asngw']['port']}")
#    correct = false
#  end
#  p = className.getParam(:gwid)
#  if result[p[:bsname]].casecmp(asngwid) != 0
#    debug(serviceName, "#{result[p[:bsname]]} FOR #{p[:bsname]} IS INCORRECT, SHOULD BE #{@config['asngw']['id']}")
#    correct = false
#  end
#  p = className.getParam(:bsrxport)
#  if Integer(result[p[:bsname]]) != asngwport
#    debug(serviceName, "#{result[p[:bsname]]} FOR #{p[:bsname]} IS INCORRECT, SHOULD BE #{@config['asngw']['port']}")
#    correct = false
#  end
#  correct
#end

#  s_description "Restore Base Station parameters from default configuration"
#  service 'bs/default' do |req, res|
#    responseText=''
#    aFileName = "#{WIMAXRF_DIR}/#{@config['reset']['file']}"
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

  s_description "Add datapath"
  s_param :type, 'type', 'Type of datapath'
  s_param :vlan, 'vlan', 'VLAN ID'
  s_param :interface, 'interface', 'Name of the network interface that hosts the VLAN'
  service 'datapath/add' do |req, res|
    type = getParam(req, 'type')
    vlan = getParam(req, 'vlan')
    interface = getParam(req, 'interface')
    params = getAllParams(req)
    params.delete('type')
    params.delete('vlan')
    params.delete('interface')
    # backward compatibility
    if type == 'click'
      type = 'click1'
    end
    result = addDataPath(type, vlan, interface, params)
    setResponsePlainText(res, result)
  end

  def self.addDataPath(type,vlan,interface,params)
    return "Datapath #{interface}-#{vlan} already exists" if datapathExists?(interface, vlan)
    return "Cannot create datapath: interface #{interface} doesn't exist" unless Util.interface_exists?(interface)

    if @manageInterface
      if type.start_with?('click') and vlan != '0'
        if Util.interface_exists?(interface, vlan)
          return "Cannot create datapath: manage_interface is true but #{interface}.#{vlan} already exists"
        end
        debug(serviceName, "Creating VLAN #{interface}.#{vlan}")
        cmd = "ip link add link #{interface} name #{interface}.#{vlan} type vlan id #{vlan}"
        if not system(cmd)
          return "Could not create VLAN: command '#{cmd}' failed with status #{$?.exitstatus}"
        end
        cmd = "ip link set #{interface}.#{vlan} up"
        if not system(cmd)
          return "Could not bring interface up: command '#{cmd}' failed with status #{$?.exitstatus}"
        end
      end
    elsif vlan != '0' and not Util.interface_exists?(interface, vlan)
      return "Cannot create datapath: interface #{interface}.#{vlan} doesn't exist"
    end

    # add to database
    newdp = Datapath.create(:type => type, :vlan => vlan, :interface => interface)
    params.each do |name, value|
      newdp.dpattributes.create(:name => name, :value => value)
    end

    begin
      @dpath[newdp.name] = createDataPath(newdp)
      "Datapath #{newdp.name} added"
    rescue => e
      # rollback db changes
      newdp.destroy
      "Failed to create datapath: #{e.message}"
    end
  end

  def self.createDataPath(dp)
    info(serviceName, "Creating #{dp.type} datapath #{dp.name}")
    dpconf = {}
    dpconf['name'] = dp.name
    dpconf['vlan'] = dp.vlan
    dpconf['interface'] = dp.interface
    dpconf['bs_interface'] = @config['bs']['data_if']
    dpconf['bstype'] = @bstype
    %w(click_command click_socket_dir click_timeout).each do |k|
      dpconf[k] = @config['datapath'][k] if @config['datapath'].has_key?(k)
    end
    dp.dpattributes.each { |k, v| dpconf[k] = v }

    # backward compatibility
    dptype = dp.type.downcase == 'click' ? 'Click1' : dp.type.capitalize

    # load and instantiate datapath class
    begin
      require "omf-aggmgr/ogs_wimaxrf/dp#{dptype}"
      Kernel.const_get("#{dptype}Datapath").new(dpconf)
    rescue ScriptError, StandardError => e
      raise(e.message)
    end
  end

  s_description "Delete datapath"
  s_param :vlan, 'vlan', 'VLAN ID'
  s_param :interface, 'interface', 'Name of the network interface that hosts the VLAN'
  service 'datapath/delete' do |req, res|
    vlan = getParam(req, 'vlan')
    interface = getParam(req, 'interface')
    result = deleteDataPath(vlan, interface)
    setResponsePlainText(res, result)
  end

  def self.deleteDataPath(vlan,interface)
    dp = Datapath.get(interface, vlan)
    return "Unknown datapath #{interface}-#{vlan}" unless dp
    # check if there's any client in this vlan
    nodes = @auth.list_clients(interface, vlan)
    return "Cannot delete datapath: there are still #{nodes.length} clients using it" unless nodes.empty?

    dpname = dp.name
    # stop datapath before removing it
    @dpath[dpname].stop

    if @manageInterface
      if dp.type.start_with?('click') and vlan != '0'
        debug(serviceName, "Deleting VLAN #{interface}.#{vlan}")
        cmd = "ip link set #{interface}.#{vlan} down"
        if not system(cmd)
          return "Could not bring interface down: command '#{cmd}' failed with status #{$?.exitstatus}"
        end
        cmd = "ip link delete #{interface}.#{vlan}"
        if not system(cmd)
          return "Could not delete VLAN: command '#{cmd}' failed with status #{$?.exitstatus}"
        end
      end
    end

    # remove from database
    if dp.destroy
      # remove from hash
      @dpath.delete(dpname)
      "Datapath #{interface}-#{vlan} deleted"
    else
      "Database error while deleting datapath #{interface}-#{vlan}"
    end
  end

  s_description "List all available datapaths"
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

  s_description "Get the status of a datapath"
  s_param :vlan, 'vlan', 'VLAN ID'
  s_param :interface, 'interface', 'Name of the network interface that hosts the VLAN'
  service 'datapath/status' do |req, res|
    vlan = getParam(req, 'vlan')
    interface = getParam(req, 'interface')
    root = getDatapathStatus(interface, vlan)
    setResponse(res, root)
  end

  def self.getDatapathStatus(interface,vlan)
    root = REXML::Element.new("DataPath")
    dpath = Datapath.first(:vlan => vlan, :interface => interface)
    if dpath != nil
      root.add_attribute("vlan", dpath.vlan)
      root.add_attribute("type", dpath.type)
      root.add_attribute("interface", dpath.interface)
      root.add_attribute("name", dpath.name)
      dpath.dpattributes.each do |att|
        addXMLElement(root, att.name, att.value)
      end
      clients = @auth.list_clients(interface, vlan)
      cl = root.add_element("Clients")
      if clients != nil
        clients.each do |c|
          node = cl.add_element("client")
          node.add_attribute("macaddr", c.macaddr)
          node.add_attribute("ipaddress", c.ipaddress)
        end
      end
    end
    root
  end

  s_description "Delete all datapaths"
  service 'datapath/clean' do |req, res|
    @auth.del_all_clients
    results = []
    Datapath.all.each do |dp|
      results << deleteDataPath(dp.vlan, dp.interface)
    end
    setResponsePlainText(res, results.join("\n"))
  end

  s_description "This service saves current datapath client configuration database."
  s_param :name, 'name', 'Name of status'
  s_param :vlan, 'vlan', 'VLAN ID'
  s_param :interface, 'interface', 'Name of the network interface that hosts the VLAN'
  service 'datapath/config/save' do |req, res|
    name = getParam(req, :name.to_s)
    vlan = getParam(req, :vlan.to_s)
    interface = getParam(req, :interface.to_s)
    replyXML = getDatapathStatus(interface,vlan)
    begin
      conf = DataPathConfig.first_or_create({:name => name}).update({:status => replyXML.to_s, :vlan => vlan})
    rescue => ex
      replyXML = buildXMLReply("Clients", '', ex)
    end
    self.setResponse(res,replyXML)
  end

  s_description "This service loads datapath client configuration from database."
  s_param :name, 'name', 'Name of client\'s status'
  service 'datapath/config/load' do |req, res|
    name = getParam(req, :name.to_s)
    conf = DataPathConfig.first(:fields => [:status], :name => name)
    begin
      if conf
        xmlConfig = conf.status
        docNew = REXML::Document.new(xmlConfig.to_s)
        #@auth.del_all_clients
        responseText = loadDataPath(docNew)
      else
        responseText = "There is no #{name} datapath configuration saved"
      end
    rescue => ex
      responseText = ex
    end
    setResponsePlainText(res, responseText)
  end

  def self.loadDataPath(docNew)
    #get datapath attributes from xml
    dp = docNew.elements["DataPath"]
    vlan = dp.attributes["vlan"]
    type = dp.attributes["type"]
    interface = dp.attributes["interface"]
    params = {}
    dp.elements.each do |att|
      if (att.name <=> "Clients") != 0 #element Clients define clients not datapath attribute
        params[att.name] = att.text
      end
    end
    addDataPath(type,vlan,interface,params)
    clientsXml = dp.elements["Clients"]
    loadClients(interface,vlan,clientsXml)
  end

  def self.loadClients(interface,vlan,docNew)
    message = " "
    begin
      clients = docNew.root.elements["Clients"].elements
      if clients.nil?
        message << "Not a valid datapath clients configuration"
      else
        message << "Load complete"
        clients.each do |c|
          if c.attributes["macaddr"]
            macaddr = c.attributes["macaddr"]
            ipaddress = c.attributes["ipaddress"]
            client = @auth.get_client(macaddr)
            if client.nil?
              @auth.add_client(macaddr, interface, vlan, ipaddress)
              message << "\nClient #{macaddr} added"
            else
              modifyClient(client, interface, vlan, ipaddress)
              message << "\nClient #{macaddr} updated"
            end
          end
        end
      end
    rescue => e
      debug(serviceName, "#{e.message}\n(at #{e.backtrace})")
      message = e.message
    end
    message
  end

  s_description "This service lists all datapath client configurations from database."
  service 'datapath/config/list' do |req, res|
    msgEmpty = "There is no saved datapath configurations"
    result = DataPathConfig.all()
    listConfig = []
    result.each { |conf| listConfig << conf.name }
    replyXML = buildXMLReply("Status", listConfig, msgEmpty) do |root, dummy|
      addXMLElementFromArray(root,"name",listConfig)
    end
    self.setResponse(res, replyXML)
  end

  s_description "This service deletes saved datapath client configuration from database."
  s_param :name, 'name', 'Name of configuration'
  service 'datapath/config/delete' do |req, res|
    name = getParam(req, :name.to_s)
    conf = DataPathConfig.first(:name => name)
    if conf.destroy
      responseText = "Datapath configuration #{name} successfully deleted from database"
    else
      responseText = "There is no datapath configuration #{name} in database"
    end
    setResponsePlainText(res, responseText)
  end

  s_description "Show named datapath client configuration from database."
  s_param :name, 'name', 'Name of saved status'
  service 'datapath/config/show' do |req, res|
    name = getParam(req, :name.to_s)
    conf = DataPathConfig.first(:fields => [:status], :name => name)
    if conf != nil
      xmlConfig = conf.status
      doc = REXML::Document.new(xmlConfig.to_s)
      self.setResponse(res, doc)
    else
      root = REXML::Element.new("DataPath")
      msg = "There is no #{name} datapath configuration saved"
      addXMLElement(root, "ERROR", "#{msg}")
      self.setResponse(res, root)
    end
  end

  s_description "Add a client to a datapath"
  s_param :macaddr, 'macaddr', 'Client MAC address'
  s_param :interface, 'interface', 'Datapath interface'
  s_param :vlan, 'vlan', 'VLAN ID'
  s_param :ipaddress, '[ipaddress]', 'Client IP address'
  service 'datapath/clients/add' do |req, res|
    macaddr = getParam(req, 'macaddr')
    interface = getParam(req, 'interface')
    vlan = getParam(req, 'vlan')
    if req.query.has_key?('ipaddress')
      ipaddress = getParam(req, 'ipaddress')
    else
      ipaddress = nil
    end
    begin
      if datapathExists?(interface, vlan)
        @auth.add_client(macaddr, interface, vlan, ipaddress)
        msg = "Client added"
      else
        msg = "Cannot add client, datapath does not exist"
      end
    rescue => e
      msg = e.message
    end
    setResponsePlainText(res, msg)
  end

  s_description "Delete a client from its datapath"
  s_param :macaddr, 'macaddr', 'Client MAC address'
  service 'datapath/clients/delete' do |req, res|
    macaddr = getParam(req, 'macaddr')
    begin
      if @auth.del_client(macaddr)
        msg = "Client deleted"
      else
        msg = "Client not found"
      end
    rescue => e
      msg = e.message
    end
    setResponsePlainText(res, msg)
  end

  s_description "Change a client's datapath and/or IP address"
  s_param :macaddr, 'macaddr', 'Client MAC address'
  s_param :ipaddress, '[ipaddress]', 'New IP address'
  s_param :interface, '[interface]', 'New interface'
  s_param :vlan, '[vlan]', 'New VLAN ID'
  service 'datapath/clients/modify' do |req, res|
    macaddr = getParam(req, 'macaddr')
    client = @auth.get_client(macaddr)
    begin
      if client
        if req.query.has_key?('vlan')
          vlan = getParam(req, 'vlan')
        else
          vlan = client.vlan
        end
        if req.query.has_key?('interface')
          interface = getParam(req, 'interface')
        else
          interface = client.interface
        end
        if req.query.has_key?('ipaddress')
          ipaddress = getParam(req, 'ipaddress')
        else
          ipaddress = nil
        end
        msg = modifyClient(client, interface, vlan, ipaddress)
      else
        msg = "Client not found"
      end
    rescue => e
      msg = e.message
    end
    setResponsePlainText(res, msg)
  end

  def self.modifyClient(client,interface,vlan,ipaddress)
    updates = {}
    message = ''

    # prepare datapath change
    if datapathExists?(interface, vlan)
      if client.vlan != vlan || client.interface != interface
        updates[:vlan] = vlan
        updates[:interface] = interface
        message << "Datapath for #{client.macaddr} updated"
      end
    else
      message << "Cannot modify vlan/interface, datapath #{interface}-#{vlan} does not exist"
    end

    # prepare ip address change
    if ipaddress != nil && ipaddress != client.ipaddress
      updates[:ipaddress] = ipaddress
      message << "\nIP address for #{client.macaddr} updated"
    end

    if !updates.empty?
      # apply changes
      @auth.update_client(client.macaddr, updates)
    end
    message
  end

  s_description "List current clients configuration"
  s_param :vlan, '[vlan]', 'VLAN ID'
  s_param :interface, '[interface]', 'Name of the network interface that hosts the VLAN'
  service 'datapath/clients/list' do |req, res|
    if req.query.has_key?('vlan')
      vlan = getParam(req, 'vlan')
      interface = getParam(req, 'interface')
    else
      vlan = nil
      interface = nil
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

  # services defined on base station param classes
  def self.initMethods
    @bs.class.const_get('PARAMS_CLASSES').each do |pc|
      className = Kernel.const_get(pc)

      s_description className.getInfo
      className.each do |n, p|
        s_param n, p[:name], p[:help]
      end

      service "bs/#{className.getName}" do |req, res|
        query = getAllParams(req)
        query_string = req.query_string()
        if !query.empty? && query_string.include?('=') # set bs parameters
          begin
            if processServiceQuery(className, req)
              res.body = "BS needs to be rebooted for changes to take effect"
            else
              res.body = "OK"
            end
          rescue => e
            res.body = e.message
          end
        else # get bs parameters
          msgEmpty = "Failed to get basestation status"
          replyXML = buildXMLReply("STATUS", msgEmpty, msgEmpty) { |root, dummy|
            bsEl = root.add_element(className.getName.capitalize)
            harqst = @bs.processServiceStatus(className, query)
            addXMLElementsFromHash(bsEl, harqst)
          }
          self.setResponse(res, replyXML)
        end
      end
    end
  end


    #------------ talk to db ---------------#

#  s_description "This service saves current BS configuration to database."
#  s_param :name, 'name', 'Name of configuration.'
#  service 'bs/config/save' do |req, res|
#    name = getParam(req, :name.to_s)
#    msgEmpty = "Failed to get basestation status"
#    replyXML = buildXMLReply("STATUS", msgEmpty, msgEmpty) { |root, dummy|
#        bsEl = root.add_element("BaseStation")
#        addXMLElementsFromHash(bsEl,@bs.wigetAll())
#      }
#    begin
#      conf = Configuration.first_or_create({:name => name}).update({:configuration => replyXML.to_s})
#    rescue => ex
#      replyXML = buildXMLReply("Configuration", '', ex)
#    end
#    self.setResponse(res,replyXML)
# end

#  s_description "This service load BS configuration from database."
#  s_param :name, 'name', 'Name of configuration.'
#  service 'bs/config/load' do |req, res|
#    name = getParam(req, :name.to_s)
#    conf = Configuration.first(:fields => [:configuration], :name => name)
#    xmlConfig = conf.configuration
#
#    begin
#      if xmlConfig != nil
#        docNew = REXML::Document.new(xmlConfig.to_s)
#        responseText = setFromXml(docNew)
#      else
#        responseText = "There is no #{name} configuration"
#      end
#    rescue => ex
#      responseText = ex.message
#    end
#    res.body = responseText
# end

# s_description "This service lists names of all BS configurations from database."
#  service 'bs/config/list' do |req, res|
#    msgEmpty = "There is no saved configurations"
#    result = Configuration.all()
#    listConfig = []
#    result.each { |conf| listConfig << conf.name }
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
#    conf = Configuration.first(:fields => [:configuration], :name => name)
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
