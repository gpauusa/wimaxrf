class Authenticator < MObject
  attr_reader :maclist, :config

  def add_client(mac,interface,vlan, ipaddr=nil)
    client = AuthClient.first_or_create(:macaddr=>mac,:vlan=>vlan,:ipaddress=>ipaddr,:interface=>interface)
    client.save
  end

  def add_ip_address(mac, ipaddr)
  end

  def del_client(mac)
    client = AuthClient.get(mac)
    client.destroy
  end

  def del_all_clients()
    AuthClient.destroy
  end

  def update_client(mac,uHash={})
    client = AuthClient.get(mac)
    client.update(uHash)
  end

  def get(mac)
    return AuthClient.get(mac)
  end

  def getIP(mac)
    client = AuthClient.get(mac)
    return nil if (client.nil?)
    return client.ipaddress, client.vlan
  end

  def list_clients(interface,vlan=nil)
    if (vlan != nil)
      # Condition by vlan
      clients = AuthClient.all(:vlan=>vlan.to_s,:interface=>interface)
    else
      clients = AuthClient.all
    end
    return clients
  end
end
