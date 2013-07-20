class Authenticator < MObject
  attr_accessor :bs

  def add_client(mac, interface, vlan, ip=nil)
    client = AuthClient.first_or_create(:macaddr   => mac,
                                        :interface => interface,
                                        :vlan      => vlan,
                                        :ipaddress => ip)
    client.save
    notify(:on_client_added, client)
  end

  def update_client(mac, changes={})
    client = AuthClient.get(mac)
    return false if client.nil?
    notify(:on_client_deleted, client)
    client.update(changes)
    notify(:on_client_added, client)
    true
  end

  def del_client(mac)
    client = AuthClient.get(mac)
    return false if client.nil?
    notify(:on_client_deleted, client)
    client.destroy
    true
  end

  def del_all_clients
    AuthClient.destroy
  end

  def get_client(mac)
    AuthClient.get(mac)
  end

  def list_clients(interface, vlan=nil)
    if vlan
      # Condition by vlan
      AuthClient.all(:vlan => vlan.to_s, :interface => interface)
    else
      AuthClient.all
    end
  end

  private

  def notify(event, *args)
    if @bs && @bs.respond_to? event
      @bs.call(event, *args)
    end
  end

end
