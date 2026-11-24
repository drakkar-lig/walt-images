**Title:** PoE: make the mapping from switch ports to PoE ports more reliable

### Context

The network topology recorded by walt identifies switch ports by their **LLDP port number** (from the LLDP neighbor table, or from the Q-BRIDGE forwarding table, which uses the same numbering). To turn PoE on or off, `snmp/poe.py` has to map this port number to a POWER-ETHERNET-MIB port index `(pethPsePortGroupIndex, pethPsePortIndex)`.

There is currently no reliable way to do this, so `get_poe_port_mapping()` uses heuristics:
1. it lists the switch interfaces, keyed by **ifIndex** (from `ifSpeed` / `ifType`);
2. it guesses which of these interfaces match the PoE port indexes returned by `pethPsePortAdminEnable`;
3. it looks up the resulting table with the **LLDP port number**.

So the heuristics implicitly assume that **LLDP port number == ifIndex**. That holds on the switches of our testbed (checked on a Netgear GS110TP and a TP-Link switch: `dot1dBasePort == ifIndex` on all ports), but not in general. Some vendors use ifIndex values such as 10101 for the first port, or put VLAN or LAG interfaces before the physical ports. On such switches, walt may turn PoE on or off on the wrong port.

### Proposal

**1. LLDP port number → ifIndex: use the standard mapping.**
LLDP-MIB defines `LldpPortNumber` as the `dot1dBasePort` on bridges, and BRIDGE-MIB gives `dot1dBasePortIfIndex[dot1dBasePort] = ifIndex`. So before applying the heuristics, convert the LLDP port number with `dot1dBasePortIfIndex` (if this table is not available, keep the current behavior, i.e. assume they are equal). The cached mapping could store the converted entries.

(LLDP-V2-MIB indexes ports directly by ifIndex, so a future LLDP-V2 variant would not need this conversion.)

**2. ifIndex → PoE port: improve the heuristics where possible.**
As far as I know, no standard MIB links an ifIndex to a POWER-ETHERNET-MIB port index:
- RFC 3621 explicitly leaves this mapping to the implementation;
- ENTITY-MIB (`entAliasMappingTable`) links physical entities to ifIndex values, but I'm not aware of a standard link between these entities and the PSE ports;
- some vendor MIBs provide it (Cisco, for example), which could be added as variants.

A cheap and safe additional rule: when all PoE ports are in group 1, and their indexes match bridge port numbers, map `pethPsePortIndex` directly to `dot1dBasePort`. This is the case on the Netgear switch of our testbed (PoE ports `(1,1)`…`(1,8)`).

**3. Make mismatches visible.**
When the heuristics cannot find a convincing mapping, log it (and possibly refuse PoE operations on this switch, or report it in `walt device show`), rather than silently operating on a guessed port.

### Related

Since v11, before turning PoE off for a node, `walt-set-poe` checks that the node MAC address is still detected on the switch port (LLDP neighbor table and forwarding table). This check uses the LLDP port numbers directly and does not depend on this mapping, but it does not protect the PoE operation itself from a wrong mapping.
