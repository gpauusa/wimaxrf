require 'monitor'
require 'net/ssh'
require 'net/telnet'
require 'snmp'

class Netdev < MObject
  attr_reader :host, :port

  def initialize(config = {})
    @host = config['ip']
    @port = config['snmp_port'] || 161
    @readcommunity = config['read_community'] || 'public'
    @writecommunity = config['write_community'] || 'private'
    @manager = SNMP::Manager.new(:Host => @host, :Community => @readcommunity,
                                 :Port => @port, :WriteCommunity => @writecommunity)
    @manager.extend(MonitorMixin)
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
    @manager.synchronize {
      @manager.load_module(modfile)
    }
  end

  def snmp_get(snmpobj)
    @manager.synchronize {
      begin
        return @manager.get_value(snmpobj)
      rescue Exception => ex
        raise "Exception in snmp_get: '#{ex}'"
      end
    }
  end

  def snmp_get_multi(row, &block)
    @manager.synchronize {
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
    @manager.synchronize {
      @manager.mib.oid(name)
    }
  end

  def snmp_set(oid, value)
    @manager.synchronize {
      newoid = get_oid(oid)
      current = @manager.get_value(newoid)
      return :noError if current == value

      if value.is_a?(Fixnum)
        vb = SNMP::VarBind.new(newoid, SNMP::Integer.new(value))
      elsif value.is_a?(String)
        vb = SNMP::VarBind.new(newoid, SNMP::OctetString.new(value))
      else
        raise NotImplementedError.new("Unhandled value of type #{value.class.name} in snmp_set.")
      end

      status = @manager.set(vb).error_status
      if status != :noError
        # just warn for now, there are too many calls failing for random reasons
        debug("Setting SNMP object #{oid} to '#{value}' returned #{status}")
      end
      status
    }
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
        error("Exception in ssh command: #{e.message}\n\t#{e.backtrace.join("\n\t")}")
    end
  end

end
