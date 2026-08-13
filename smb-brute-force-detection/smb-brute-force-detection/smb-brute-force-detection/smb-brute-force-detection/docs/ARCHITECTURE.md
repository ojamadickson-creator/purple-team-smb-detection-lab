# Architecture Deep Dive

## Why This Design?

I built this lab to mirror what you'd actually see in an enterprise: the attacker doesn't sit on the same subnet as the target. Traffic has to traverse a perimeter firewall, which means you get telemetry at both the network layer and the endpoint layer. If you only look at one, you're flying blind.

## Network Segments

### LAN Segment (Host-Only Primary): 192.168.56.0/24
This is the internal corporate network. The Domain Controller, Splunk SIEM, and management workstation all live here. REMnux was placed on the WAN segment after Kali had Docker routing issues.

Key assets:
- Windows Host (Management): `192.168.56.1`
- OPNsense LAN Interface: `192.168.56.254`
- Domain Controller: `192.168.56.102`
- Splunk SIEM: `192.168.56.106`
- REMnux (Attack Origin): `192.168.57.12`

### WAN Segment (Host-Only #2): 192.168.57.0/24
This simulates the external untrusted network. OPNsense faces this segment on its WAN interface at `192.168.57.254`. I originally put Kali Linux here at `192.168.57.10` to test perimeter rules, but Docker's iptables NAT rules interfered with routing. I used REMnux at `192.168.57.12` on the same WAN segment, which provided a clean attack path through the OPNsense firewall to the DC.

### NAT Segment: 10.0.2.0/24
Standard VirtualBox NAT. Gives every VM outbound internet access for OS updates and tool downloads without bridging them to the host's physical network.

## How Traffic Actually Flows

When REMnux (`192.168.57.12`) initiates an SMB connection to the DC (`192.168.56.102`), here's what happens:

1. REMnux checks its routing table and sends the packet to its default gateway (`192.168.57.254`)
2. OPNsense receives it on the LAN interface
3. OPNsense evaluates its firewall rules. If SMB to the DC is allowed, it forwards the packet
4. The packet hits the DC's network interface
5. Windows Firewall on the DC evaluates the inbound connection
6. The SMB authentication attempt gets logged as EventCode 4625 (failure) or 4624 (success)
7. The Splunk Universal Forwarder reads the Security log and transmits the event to `192.168.56.106:9997`
8. Splunk indexes the event, and the dashboard surfaces it in real time

One quirk: Splunk recorded the source IP as `192.168.56.1`, not `192.168.56.12`. VirtualBox's host-only adapter does some NAT translation behind the scenes. The detection still works perfectly, but if you're trying to do precise attribution in a virtual lab, this is something to be aware of.

## Why OPNsense?

The original SOP I was working from mentioned pfSense, but the actual lab uses OPNsense 26.7 running on FreeBSD 15.1. OPNsense has a cleaner Web GUI, better syslog export options, and handles rule ordering in a way that made troubleshooting easier. It accurately models enterprise perimeter behavior without the licensing headaches of commercial firewalls.

## Log Sources

| Source | sourcetype | How It Gets There | Port |
|--------|-----------|-------------------|------|
| Windows DC Security Log | WinEventLog:Security | Splunk Universal Forwarder (TCP) | 9997 |
| OPNsense Firewall | syslog | UDP Syslog forwarding | 514 |
| Splunk Internal | _internal | Local generation | N/A |

The Windows logs give you the authentication events. The firewall logs give you the perimeter visibility. You need both to tell the full story.
