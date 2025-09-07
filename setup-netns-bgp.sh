#!/usr/bin/env bash
set -euo pipefail

# Cleanup old namespaces
echo "=== Removing old namespaces ==="
sudo ip netns del ns1 2>/dev/null || true
sudo ip netns del ns2 2>/dev/null || true

# Create namespaces
echo "=== Creating namespaces ==="
sudo ip netns add ns1
sudo ip netns add ns2

echo "=== Creating veth pair ==="
sudo ip link add veth-ns1 type veth peer name veth-ns2
sudo ip link set veth-ns1 netns ns1
sudo ip link set veth-ns2 netns ns2

echo "=== Configuring IP addresses ==="
sudo ip netns exec ns1 ip addr add 10.0.0.1/24 dev veth-ns1
sudo ip netns exec ns1 ip link set dev veth-ns1 up
sudo ip netns exec ns1 ip link set lo up

sudo ip netns exec ns2 ip addr add 10.0.0.2/24 dev veth-ns2
sudo ip netns exec ns2 ip link set dev veth-ns2 up
sudo ip netns exec ns2 ip link set lo up

echo "=== Creating FRR runtime directories ==="
sudo mkdir -p /var/run/frr-ns1 /var/run/frr-ns2

echo "=== Creating GoBGP configuration files ==="
cat > ns1/gobgp.yaml <<'EOF'
global:
  config:
    as: 65001
    router-id: 192.0.2.1

zebra:
  config:
    enabled: true
    url: unix:/var/run/frr-ns1/zserv.api
EOF

cat > ns2/gobgp.yaml <<'EOF'
global:
  config:
    as: 65002
    router-id: 192.0.2.2

zebra:
  config:
    enabled: true
    url: unix:/var/run/frr-ns2/zserv.api
EOF

echo "=== Starting Zebra in each namespace ==="
sudo ip netns exec ns1 /usr/lib/frr/zebra -d -A 127.0.0.1 -i /var/run/frr-ns1/zebra.pid -z /var/run/frr-ns1/zserv.api
sudo ip netns exec ns2 /usr/lib/frr/zebra -d -A 127.0.0.1 -i /var/run/frr-ns2/zebra.pid -z /var/run/frr-ns2/zserv.api

echo "=== Starting GoBGP daemons ==="
sudo ip netns exec ns1 gobgpd -f ns1/gobgp.yaml -l info &
sudo ip netns exec ns2 gobgpd -f ns2/gobgp.yaml -l info &

echo "=== Waiting a few seconds for daemons to start ==="
sleep 5

echo "=== Adding a test route via GoBGP in ns2 ==="
sudo ip netns exec ns2 gobgp global rib add 10.200.200.0/24 nexthop 10.0.0.2

echo "=== Showing routes in ns2 ==="
sudo ip netns exec ns2 ip route show 10.200.200.0/24
