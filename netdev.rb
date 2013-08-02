require 'snmp'
require 'monitor'
require 'net/ssh'
require 'net/scp'
require 'net/telnet'

class Netdev < MObject
  attr_reader :host, :port

  def initialize(config = {})
    @host = config['ip']
    @port = config['snmp_port'] || 161
    @readcommunity = config['read_community'] || 'public'
    @writecommunity = config['write_community'] || 'private'
    @manager = SNMP::Manager.new(:Host => @host, :Community => @readcommunity,
                                 :Port => @port, :WriteCommunity => @writecommunity)
    @snmp_lock = Monitor.new
    @telnetuser = config[:telnetuser]
    @telnetpass = config[:telnetpass]
    @telnetprompt = config[:telnetprompt] || "[$%#>] \z/n"
    if @telnetuser
      @sw = Net::Telnet::new("Host" => @host, "Timeout" => 10, "Prompt" => @telnetuser)
      @sw.login(@telnetuser)
    else
      @sw = nil
    end
    @sshuser = config[:sshuser] || 'root'
    @sshpass = config[:sshpass] || ''
    debug("Initialized networking device at #{@host}")
  end

  def close
    @manager.close
    @sw.close unless @sw.nil?
  end

  def telnet_get(command)
    #logs in and retrieves OF info from switch
    @sw.cmd(command).split(/\n/)
  end

  def add_snmp_module(modfile)
    @snmp_lock.synchronize {
      @manager.load_module(modfile)
    }
  end

  def snmp_get(snmpobj)
    @snmp_lock.synchronize {
      begin
        return @manager.get_value(snmpobj)
      rescue Exception => ex
        raise "Exception in snmp_get: '#{ex}'"
      end
    }
  end

  def snmp_get_multi(row, &block)
    @snmp_lock.synchronize {
      begin
        @manager.walk(row) do |result|
          yield(result)
        end
      rescue Exception => ex
        raise "Exception in snmp_get_multi: '#{ex}'"
      end
    }
  end

  def get_oid(name)
    @snmp_lock.synchronize {
      @manager.mib.oid(name)
    }
  end

  def snmp_set(oid, value)
    status = ''
    @snmp_lock.synchronize {
      begin
        # uses snmp to set MIB values - needs to check previous state and be able to handle more OID's
        newoid = get_oid(oid)
        val = @manager.get_value(newoid)
        if val != value
          if value.is_a?(Fixnum)
            #print "INT #{newoid}=#{value.to_s}\n"
            vb = SNMP::VarBind.new(newoid, SNMP::Integer.new(value))
            status = "#{newoid} value changed to #{value}"
          elsif value.is_a?(String)
            #print "STR #{newoid}=#{val}\n"
            vb = SNMP::VarBind.new(newoid, SNMP::OctetString.new(value))
            status = "#{newoid} value changed to #{value}"
          end
          resp = @manager.set(vb)
          #print "got error #{resp.error_status()}\n"
          #val = @manager.get_value(newoid)
          #print "#{newoid} value now set to #{val}\n"
        else
          status = "#{newoid} value already set to #{value}"
        end
      rescue SNMP::RequestTimeout
        begin
          tryAgain = true
          #print "Try to get new value"
          val = @manager.get_value(newoid)
          status = "#{newoid} value changed to #{value}"
        rescue SNMP::RequestTimeout
          while tryAgain
            print "RETRY"
            retry
          end
        end
      rescue Exception => ex
        raise "Exception in snmp_set: '#{ex}'"
      end
    }
    status
  end

  def ssh(command)
    begin
      tryAgain = true
      Net::SSH.start(@host, @sshuser, :password => @sshpass, :paranoid => false) do |ssh|
        return ssh.exec!(command)
      end
      rescue Errno::ECONNRESET
        while tryAgain
          print "RETRY SSH - Errno::ECONNRESET"
          retry
        end
      rescue Errno::ECONNREFUSED
        while tryAgain
          print "RETRY SSH - Errno::ECONNREFUSED"
          retry
        end
      rescue Errno::EHOSTUNREACH
        while tryAgain
          print "RETRY SSH - Errno::EHOSTUNREACH"
          retry
        end
      rescue => e
        error("Exception in ssh command: #{e.message}\n#{e.backtrace.join("\n\t")}")
    end
  end

  def create_vlan(vlan)
  end

  def delete_vlan(vlan)
  end
end
