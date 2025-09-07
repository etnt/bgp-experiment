#!/usr/bin/env bash
set -euo pipefail

NS1=ns1
NS2=ns2
VETH1=veth-ns1
VETH2=veth-ns2
IP1=10.0.0.1/24
IP2=10.0.0.2/24
FRR_DIR1=/var/run/frr-ns1
FRR_DIR2=/var/run/frr-ns2
GOBGP_DIR1=ns1
GOBGP_DIR2=ns2

# Define a log file for GoBGP output
GOBGP_LOG_NS1="ns1/gobgp.log"
GOBGP_LOG_NS2="ns2/gobgp.log"

# Wait for Zebra socket to be ready
wait_for_zebra() {
    local ns="$1"
    local sock="$2"
    local retries=10
    local wait=0.5

    for i in $(seq 1 $retries); do
        if sudo ip netns exec "$ns" test -S "$sock"; then
            # Optionally check writability too
            if sudo ip netns exec "$ns" test -w "$sock"; then
                return 0
            fi
        fi
        sleep "$wait"
    done

    echo "⚠ Zebra socket $sock in namespace $ns not ready after $retries attempts" >&2
    return 1
}

# Wait for GoBGP to establish Zebra connection
wait_for_gobgp_zebra() {
  NS=$1
  LOG=$2
  until grep -q "success to connect to Zebra" "$LOG"; do
    sleep 0.2
  done
}

echo "=== Cleanig up ${FRR_DIR1} ==="
sudo rm -f ${FRR_DIR1}/*

echo "=== Cleanig up ${FRR_DIR2} ==="
sudo rm -f ${FRR_DIR2}/*

echo "=== Removing old namespaces ==="
sudo ip netns del $NS1 2>/dev/null || true
sudo ip netns del $NS2 2>/dev/null || true

echo "=== Creating namespaces ==="
sudo ip netns add $NS1
sudo ip netns add $NS2

echo "=== Creating veth pair ==="
sudo ip link add $VETH1 type veth peer name $VETH2
sudo ip link set $VETH1 netns $NS1
sudo ip link set $VETH2 netns $NS2

echo "=== Configuring IP addresses ==="
sudo ip netns exec $NS1 ip addr add $IP1 dev $VETH1
sudo ip netns exec $NS2 ip addr add $IP2 dev $VETH2
sudo ip netns exec $NS1 ip link set $VETH1 up
sudo ip netns exec $NS2 ip link set $VETH2 up
sudo ip netns exec $NS1 ip link set lo up
sudo ip netns exec $NS2 ip link set lo up

echo "=== Creating FRR runtime directories on host ==="
sudo mkdir -p $FRR_DIR1 $FRR_DIR2
sudo chown frr:frr $FRR_DIR1 $FRR_DIR2
sudo chmod 755 $FRR_DIR1 $FRR_DIR2

echo "=== Creating GoBGP configuration files ==="
mkdir -p $GOBGP_DIR1 $GOBGP_DIR2
# Here you would write the gobgp.yaml files into ns1/ and ns2/ directories
# (keep your previous working config that doesn’t include 'redistribute-route-type-list')

echo "=== Starting Zebra in each namespace ==="
sudo ip netns exec $NS1 /usr/lib/frr/zebra -d \
  -i $FRR_DIR1/zebra.pid \
  -z $FRR_DIR1/zserv.api \
  -A 127.0.0.1 > "ns1/zebra.log" 2>&1

sudo ip netns exec $NS2 /usr/lib/frr/zebra -d \
  -i $FRR_DIR2/zebra.pid \
  -z $FRR_DIR2/zserv.api \
  -A 127.0.0.1 > "ns2/zebra.log" 2>&1


echo "=== Wait for Zebra to be started ==="
wait_for_zebra ns1 /var/run/frr-ns1/zserv.api
wait_for_zebra ns2 /var/run/frr-ns2/zserv.api

echo '=== Starting GoBGP in each namespace and adding test routes ==='

# Start gobgpd in NS1
sudo ip netns exec ns1 gobgpd -f ns1/gobgp.yaml -l debug > "$GOBGP_LOG_NS1" 2>&1 &
wait_for_gobgp_zebra ns1 "$GOBGP_LOG_NS1"

# Add a test route in NS1
sudo ip netns exec ns1 gobgp global rib add 10.200.200.0/24 nexthop 10.0.0.2 || true

# Start gobgpd in NS2
sudo ip netns exec ns2 gobgpd -f ns2/gobgp.yaml -l debug > "$GOBGP_LOG_NS2" 2>&1 &
wait_for_gobgp_zebra ns2 "$GOBGP_LOG_NS2"

# Add a test route in NS2
sudo ip netns exec ns2 gobgp global rib add 10.100.100.0/24 nexthop 10.0.0.1 || true

echo '=== GoBGP setup done ==='

# Reset text formatting and line wrapping
tput sgr0   # reset attributes (colors, bold, etc.)
tput rmcup  # reset alternate screen buffer if used
stty sane  # restore sane tty settings
echo
echo "=== Terminal reset complete ==="

# Fancy terminal colors
GREEN=$(tput setaf 2)
RED=$(tput setaf 1)
YELLOW=$(tput setaf 3)
RESET=$(tput sgr0)
BOLD=$(tput bold)

echo
echo "${BOLD}=== Verifying advertised test routes in kernel routing tables ===${RESET}"

for ns in ns1 ns2; do
    echo
    echo "${YELLOW}--- Namespace: $ns ---${RESET}"

    # GoBGP RIB
    echo "${BOLD}GoBGP RIB:${RESET}"
    sudo ip netns exec "$ns" gobgp global rib | awk '{printf "  %-20s  %-15s  %s\n", $1, $2, $3}'

    # Kernel routes
    echo "${BOLD}Kernel routing table:${RESET}"
    sudo ip netns exec "$ns" ip route show | awk '{printf "  %-20s  via %-15s  dev %-10s proto %-5s metric %s\n", $1, $3, $5, $7, $9}'

    # Zebra routes
    echo "${BOLD}Zebra routes via vtysh:${RESET}"
    zebra_output=$(sudo ip netns exec "$ns" vtysh -c "show ip route" 2>/dev/null)

    for prefix in 10.200.200.0/24 10.100.100.0/24; do
        if echo "$zebra_output" | grep -q "$prefix"; then
            echo "  ${GREEN}✔ $prefix present${RESET}"
        else
            echo "  ${RED}✖ $prefix missing${RESET}"
        fi
    done
done

echo
echo "${BOLD}=== Test route verification complete ===${RESET}"


echo "=== Done ==="
