# BGP Route Advertisement with Linux Namespaces, GoBGP, and FRR

This repository provides a simple, hands-on environment to experiment with **BGP route advertisement** using Linux namespaces, **GoBGP** (`gobgpd`), and **FRR/Zebra**. The goal is to demonstrate how BGP routes can be advertised between nodes, installed in the kernel routing table, and optionally verified via Zebra.

The setup simulates a minimal network with **two nodes** (`ns1` and `ns2`) connected via a virtual Ethernet (veth) link.

## Purpose

- Learn how GoBGP can advertise routes between isolated network namespaces.
- Observe how routes propagate into the **kernel routing table**.
- Understand the role of Zebra in managing and verifying BGP-installed routes.

## How It Works

1. **Namespace creation**: Two Linux namespaces (`ns1` as manager, `ns2` as worker) are created.
2. **Virtual link**: Namespaces are connected via a veth pair with IPs `10.0.0.1` (`ns1`) and `10.0.0.2` (`ns2`).
3. **Zebra setup**: Zebra is started in each namespace to manage kernel route installation.
4. **GoBGP setup**: `gobgpd` is started in each namespace with BGP peering between `ns1` and `ns2`.
5. **Route advertisement**: A test route (`10.200.200.0/24`) is advertised from `ns2` to `ns1`.

## Verifying the Result

After the script runs:

- The **GoBGP RIB** in each namespace shows the advertised routes.
- The **kernel routing table** confirms that routes have been installed correctly.
- Zebra can optionally be queried to verify which BGP routes are present in the kernel.
- The script provides a **fancy verification output** marking each route as present (`✔`) or missing (`✖`) for easy inspection.
- `ns1/gobgp.yaml` and `ns2/gobgp.yaml`: GoBGP configuration files used by the script.

## Requirements

- Linux with `iproute2` (for namespaces and veth interfaces).
- GoBGP (`gobgpd`) installed.
- FRR (`zebra`) installed.

## More details

**GoBGP RIB:** This shows the routes that GoBGP knows internally, including
routes learned from peers and locally advertised routes. Think of it as
GoBGP’s “route database” before the system actually uses them to forward packets.

RIB stands for Routing Information Base. In the context of GoBGP (and most
BGP implementations):

  * RIB is the internal table where a BGP speaker stores all the routes it
    learns from its peers or generates locally.

  * It is essentially a database of routes, before any selection rules are
    applied to install routes into the kernel or forward packets.

  * There are typically two main RIBs in BGP systems:

    1. **Adj-RIB-In:** routes learned from BGP peers.

    2. **Loc-RIB:** routes that have been processed and selected as best paths
       (the “active” routes).

So when your script shows GoBGP RIB:, it’s displaying the routes that GoBGP
knows about internally, including both locally advertised routes and those
received from its peer.

**Kernel routing table:** These are the routes that the Linux kernel is using
for actual packet forwarding. In our case it shows which routes actually made
it into the system’s IP stack for packet forwarding, via the GoBGP advertisment.

**Zebra routes via vtysh:** Shows which routes FRR’s Zebra has installed or
knows about.

## How to Run

**Script Options:**

  **--inspect:** Pause the script after namespaces and veth setup,
                 before starting Zebra, allowing you to inspect the
                 routing tables manually. Press Enter to continue.

  **--clean:** Remove all created namespaces and cleanup runtime directories
               without running the full setup.

```bash
chmod +x setup-netns-bgp.sh
./setup-netns-bgp.sh
```

After running the script, ns1 will learn the test route 10.200.200.0/24 via
BGP, and ns2 will learn the test route 10.100.100.0/24.

You can inspect the route table inside the namespace:

```bash
sudo ip netns exec ns1 ip route
sudo ip netns exec ns1 gobgp global rib
```
### Optional Inspection Mode

You can pause the script after the namespaces are created but before starting
Zebra and GoBGP, to inspect the network state:

```bash
./setup-netns-bgp.sh --inspect
...
=== INSPECTION PAUSE ===
The namespaces are set up. You can inspect the routing tables now:
  sudo ip netns exec ns1 ip route
  sudo ip netns exec ns2 ip route
Press RETURN to continue and start Zebra...
...
```

## Example Run

```bash
❯ ./setup-netns-bgp.sh
=== Cleanig up /var/run/frr-ns1 ===
=== Cleanig up /var/run/frr-ns2 ===
=== Removing old namespaces ===
=== Creating namespaces ===
=== Creating veth pair ===
=== Configuring IP addresses ===
=== Creating FRR runtime directories on host ===
=== Creating GoBGP configuration files ===
=== Starting Zebra in each namespace ===
=== Wait for Zebra to be started ===
=== Starting GoBGP in each namespace and adding test routes ===
=== GoBGP setup done ===

=== Terminal reset complete ===

=== Verifying advertised test routes in kernel routing tables ===

--- Namespace: ns1 ---
GoBGP RIB:
  Network               Next             Hop
  *>                    10.200.200.0/24  10.0.0.2
Kernel routing table:
  10.0.0.0/24           via veth-ns1         dev kernel     proto link  metric 10.0.0.1
  10.200.200.0/24       via 4                dev 10.0.0.2   proto veth-ns1 metric bgp
Zebra routes via vtysh:
  ✖ 10.200.200.0/24 missing
  ✔ 10.100.100.0/24 present

--- Namespace: ns2 ---
GoBGP RIB:
  Network               Next             Hop
  *>                    10.100.100.0/24  10.0.0.1
Kernel routing table:
  10.0.0.0/24           via veth-ns2         dev kernel     proto link  metric 10.0.0.2
  10.100.100.0/24       via 4                dev 10.0.0.1   proto veth-ns2 metric bgp
Zebra routes via vtysh:
  ✖ 10.200.200.0/24 missing
  ✔ 10.100.100.0/24 present

=== Test route verification complete ===
=== Done ===
```

Notes:

✖ indicates a route missing from Zebra (expected if the route was added only via GoBGP).

✔ indicates the route is present.

Kernel routing table shows actual forwarding entries.

GoBGP RIB shows the route GoBGP is aware of internally.

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
