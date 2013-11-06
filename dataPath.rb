require 'omf-common/mobject'

class DataPath < MObject
  attr_reader :name

  def initialize(config)
    super()
    @mobiles = {}
    @name = config['name']
  end

  # Adds the client to this datapath.
  def add(mac, client)
    @mobiles[mac] = client
  end

  # Removes the client from this datapath.
  def delete(mac)
    @mobiles.delete(mac)
  end

  # Returns the number of clients currently using this datapath.
  def length
    @mobiles.length
  end

  # Starts the datapath. Must be implemented by subclasses.
  def start
    raise NotImplementedError.new("You must implement DataPath#start in your subclass.")
  end

  # Stops the datapath. Must be implemented by subclasses.
  def stop
    raise NotImplementedError.new("You must implement DataPath#stop in your subclass.")
  end

  # Stops and restarts the datapath. Can be overridden by subclasses
  # that wish to provide a different or more efficient restart method.
  def restart
    stop
    start
  end

end
