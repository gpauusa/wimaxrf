require 'rubygems'
require 'data_mapper'

class Configuration
  # keep various BS configuration
  include DataMapper::Resource
  property :id,            Serial  # An auto-increment integer key
  property :name,          String, :length => 1..64, :required => true
  property :configuration, Text
end

class Datapath
  include DataMapper::Resource
  property :interface,  String, :length => 1..20,  :required => true, :key => true
  property :vlan,       String, :length => 1..4,   :required => true, :key => true
  property :type,       String, :length => 1..20,  :required => true
  has n, :dpattributes, :parent_key => [:interface, :vlan], :child_key => [:interface, :vlan], :constraint => :destroy
  def name
    "#{self[:interface]}-#{self[:vlan]}"
  end
end

class Dpattribute
  include DataMapper::Resource
  belongs_to :datapath, :parent_key => [:interface, :vlan], :child_key => [:interface, :vlan], :key => true
  property :name,  Text, :key => true
  property :value, Text
end

class AuthClient
  include DataMapper::Resource
  storage_names[:default] = 'clients'
  property :macaddr,    String, :length => 1..20, :key => true
  property :vlan,       String, :length => 1..4,  :field => 'vlanid'
  property :interface,  String, :length => 1..20, :required => true
  property :ipaddress,  String, :length => 1..20
  property :sliceid,    Text
  property :greup,      Text
  property :gredown,    Text
  def dpname
    "#{self[:interface]}-#{self[:vlan]}"
  end
end

class ClientStatus
  # keep various clients status configuration; not using any more
  include DataMapper::Resource
  property :id,     Serial  # An auto-increment integer key
  property :name,   String, :length => 1..64, :required => true
  property :status, Text
end

class DataPathConfig
  # keep various datapath configuration
  include DataMapper::Resource
  property :id,     Serial  # An auto-increment integer key
  property :name,   String, :length => 1..64, :required => true
  property :vlan,   Text
  property :status, Text
end

DataMapper.finalize
