# Architecture Deep Dive

## Why This Design?

I built this lab to mirror what you'd actually see in an enterprise: the attacker doesn't sit on the same subnet as the target. Traffic has to traverse a perimeter firewall, which means you get telemetry at both the network layer and the endpoint layer. If you only look at one, you're flying blind.

## Network Segments

### LAN Segment (Host-Only Primary): 192.168.56.0/24
This is the internal corporate network. The Domain Controller, Splunk SIEM, and management workstation all live here.

Key assets:
- VirtualBox Host Adapter: `192.168.56.1`
- OPNsense LAN Interface: `192.168.56.254`
- Domain Controller: `192.168.56.102`
- Splunk SIEM: `192.168.56.106`

### WAN Segment (Host-Only #2): 192.168.57.0/24
This simulates the external untrusted network. OPNsense faces this segment on its WAN interface at `192.168.57.254`. REMnux at `192.168.57.12` serves as the attack platform on this segment, providing a realistic perimeter-to-internal attack path through the OPNsense firewall to the DC.

### NAT Segment: 10.0.2.0/24
Standard VirtualBox NAT. Gives every VM outbound internet access for OS updates and tool downloads without bridging them to the host's physical network.

## How Traffic Actually Flows

When REMnux (`192.168.57.12`) initiates an SMB connection to the DC (`192.168.56.102`), here's what happens:

1. REMnux checks its routing table and sends the packet to its default gateway (`192.168.57.254`)
2. OPNsense receives it on the **WAN** interface
3. OPNsense evaluates its firewall rules. If SMB to the DC is allowed, it forwards the packet out the **LAN** interface
4. The packet hits the DC's network interface
5. The SMB authentication attempt gets logged as EventCode 4625 (failure) or 4624 (success)
6. The Splunk Universal Forwarder reads the Security log and transmits the event to `192.168.56.106:9997`
7. Splunk indexes the event, and the dashboard surfaces it in real time

One quirk: Splunk recorded the source IP as `192.168.56.1`, not `192.168.57.12` where REMnux actually lives. I never fully traced why — it could be VirtualBox adapter behavior, OPNsense NAT, or something else in the virtualized path. The detection still works perfectly, but precise IP attribution in this lab environment requires keeping that quirk in mind.

## Why OPNsense?

OPNsense has a responsive Web GUI, robust syslog export, and straightforward rule management. It accurately models enterprise perimeter behavior without the licensing headaches of commercial firewalls.

## Log Sources

| Source | sourcetype | How It Gets There | Port |
|--------|-----------|-------------------|------|
| Windows DC Security Log | WinEventLog:Security | Splunk Universal Forwarder (TCP) | 9997 |
| OPNsense Firewall | syslog | UDP Syslog forwarding | 514 |
| Splunk Internal | _internal | Local generation | N/A |

The Windows logs give you the authentication events. The firewall logs give you the perimeter visibility. You need both to tell the full story.
