#!/bin/bash
set -euo pipefail

# Clean up any old namespaces
sudo ip netns del ns1 2>/dev/null || true
sudo ip netns del ns2 2>/dev/null || true

# Create namespaces
sudo ip netns add ns1
sudo ip netns add ns2

# Create veth pair
sudo ip link add veth-ns1 type veth peer name veth-ns2
sudo ip link set veth-ns1 netns ns1
sudo ip link set veth-ns2 netns ns2

# Assign IP addresses
sudo ip netns exec ns1 ip addr add 10.0.0.1/24 dev veth-ns1
sudo ip netns exec ns2 ip addr add 10.0.0.2/24 dev veth-ns2

# Bring interfaces up
sudo ip netns exec ns1 ip link set dev veth-ns1 up
sudo ip netns exec ns2 ip link set dev veth-ns2 up
sudo ip netns exec ns1 ip link set lo up
sudo ip netns exec ns2 ip link set lo up

# Create run directories for Zebra
sudo mkdir -p /var/run/frr-ns1
sudo mkdir -p /var/run/frr-ns2

# Start Zebra in both namespaces
sudo ip netns exec ns1 /usr/lib/frr/zebra -d -A 127.0.0.1 \
    -z /var/run/frr-ns1/zserv.api \
    -i /var/run/frr-ns1/zebra.pid

sudo ip netns exec ns2 /usr/lib/frr/zebra -d -A 127.0.0.1 \
    -z /var/run/frr-ns2/zserv.api \
    -i /var/run/frr-ns2/zebra.pid

# Wait a few seconds for Zebra to initialize
sleep 2

# Create gobgp config files
mkdir -p ns1 ns2

cat > ns1/gobgp.yaml <<'EOF'
global:
  config:
    as: 65001
    router-id: 10.0.0.1

zebra:
  config:
    enabled: true
    url: unix:/var/run/frr-ns1/zserv.api

neighbors:
  - config:
      neighbor-address: 10.0.0.2
      peer-as: 65002
EOF

cat > ns2/gobgp.yaml <<'EOF'
global:
  config:
    as: 65002
    router-id: 10.0.0.2

zebra:
  config:
    enabled: true
    url: unix:/var/run/frr-ns2/zserv.api

neighbors:
  - config:
      neighbor-address: 10.0.0.1
      peer-as: 65001
EOF

# Start gobgpd in each namespace
sudo ip netns exec ns1 gobgpd -f ns1/gobgp.yaml -l info &
sudo ip netns exec ns2 gobgpd -f ns2/gobgp.yaml -l info &

# Wait a few seconds for BGP session to establish
sleep 5

# Advertise a test route from ns2
sudo ip netns exec ns2 gobgp global rib add 10.200.200.0/24 nexthop 10.0.0.2

# Show the routes in ns1 (manager)
echo "Routes learned in ns1:"
sudo ip netns exec ns1 gobgp global rib
sudo ip netns exec ns1 ip route show 10.200.200.0/24
