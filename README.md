# Linux Namespace BGP Setup with GoBGP and Zebra

This repository provides a simple example to experiment with BGP route advertisement using Linux namespaces, GoBGP (`gobgpd`), and Zebra (`FRR`).  

The setup simulates a small network with two nodes (`ns1` and `ns2`) connected via a virtual Ethernet (veth) link.

## Files

- `setup-netns-bgp.sh`: Bash script that:
  1. Creates two Linux namespaces (`ns1` as manager, `ns2` as worker).
  2. Connects them via a veth pair with IPs `10.0.0.1` (ns1) and `10.0.0.2` (ns2).
  3. Starts Zebra in each namespace for route installation.
  4. Starts `gobgpd` in each namespace with BGP peering between ns1 and ns2.
  5. Advertises a test route (`10.200.200.0/24`) from ns2 to ns1.
  6. Displays learned routes in ns1.

- `ns1/gobgp.yaml` and `ns2/gobgp.yaml`: GoBGP configuration files used by the script.

## Requirements

- Linux with `iproute2` (for namespaces and veth interfaces).
- GoBGP (`gobgpd`) installed.
- FRR (`zebra`) installed.

## How to Run

```bash
chmod +x setup-netns-bgp.sh
./setup-netns-bgp.sh
```

After running the script, ns1 will learn the test route 10.200.200.0/24 via BGP.

You can inspect the route table inside the namespace:

```bash
sudo ip netns exec ns1 ip route
sudo ip netns exec ns1 gobgp global rib
```

## Notes

The `redistribute-route-type-list` configuration is not used, because in some
Zebra setups it causes connection issues.

The BGP session remains active as long as the namespaces exist.

To clean up:

```bash
sudo ip netns del ns1
sudo ip netns del ns2
```

This will remove all interfaces, routes, and running daemons.
