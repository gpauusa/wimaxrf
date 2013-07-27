class Authenticator < MObject
  attr_accessor :bs

  # Adds a new client to the auth db.
  # Returns true on success, false if the given mac already exists.
  def add_client(mac, interface, vlan, ip=nil)
    client = AuthClient.create(:macaddr   => mac,
                               :interface => interface,
                               :vlan      => vlan,
                               :ipaddress => ip)
    return false unless client.saved?
    notify(:on_client_added, client)
    true
  end

  # Modifies a client in the auth db.
  # Returns true on success, false if the client does not exist.
  def update_client(mac, changes)
    client = AuthClient.get(mac)
    return false if client.nil?
    notify(:on_client_deleted, client)
    client.update(changes)
    notify(:on_client_added, client)
    true
  end

  # Deletes the given mac address from the auth db.
  # Returns true on success, false if the client does not exist.
  def del_client(mac)
    client = AuthClient.get(mac)
    return false if client.nil?
    notify(:on_client_deleted, client)
    client.destroy
    true
  end

  # Deletes all clients from the auth db.
  def del_all_clients
    AuthClient.all.each do |client|
      notify(:on_client_deleted, client)
      client.destroy
    end
    true
  end

  # Returns an AuthClient instance for the given mac address,
  # or nil if the mac address is not authorized.
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
    if @bs && @bs.respond_to?(event)
      @bs.send(event, *args)
    end
  end

end
