//parameters
define($BSDEVICE eth1, $NETDEVICE eth2, $BSVLAN BAYSTATION_VLAN_ID, $NETVLAN NETWORK_VLAN_ID)

//elements declaration
ControlSocket(unix, /tmp/$NETVLAN.clicksocket)
switch :: EtherSwitch;
from_bs :: FromDevice($BSDEVICE.$BSVLAN, PROMISC true);
to_bs :: ToDevice($BSDEVICE.$BSVLAN);
from_net :: FromDevice($NETDEVICE.$NETVLAN, PROMISC true);
to_net :: ToDevice($NETDEVICE.$NETVLAN);

//dest address whitelist, the 2 Addresses are example and will be more than 2
filter_from_network :: {
filter_1 :: HostEtherFilter(00:1e:42:02:15:93, DROP_OWN false, DROP_OTHER true);
filter_2 :: HostEtherFilter(00:1e:42:02:1b:2c, DROP_OWN false, DROP_OTHER true);
input -> filter_1;
filter_1[0], filter_2[0] -> output;
filter_1[1] -> filter_2[1] -> sink :: Discard;
}

//source address whitelist, the 2 Addresses are example and will be more than 2
filter_from_bs :: {
filter_1 :: HostEtherFilter(00:1e:42:02:15:93, DROP_OWN true, DROP_OTHER false);
filter_2 :: HostEtherFilter(00:1e:42:02:1b:2c, DROP_OWN true, DROP_OTHER false);
input -> filter_1;
filter_1[1], filter_2[1] -> output;
filter_1[0] -> filter_2[0] -> sink :: Discard;
}

bs_queue :: Queue -> to_bs;
net_queue :: Queue -> to_net;

//take packet from the network, apply a whitelist of the destination addresses, remove vlan header and put them in the switch
from_net -> filter_from_network -> net_decap :: VLANDecap -> [0]switch; 
// setting vlan annotation for the packets directed to the network and putting them in queue
switch[0] -> vlan_to_net_encap :: VLANEncap($NETVLAN) -> net_queue;

//take packet from the BS, apply a whitelist of the source addresses, remove vlan header and put them in the switch
from_bs -> filter_from_bs -> bs_decap :: VLANDecap -> [1]switch;
//setting the vlan annotation for packets for the Baystation and putting them in queue
switch[1] -> vlan_to_bs_encap :: VLANEncap($BSVLAN) -> bs_queue;
