# Troubleshooting Guide

This isn't a sanitized success story. These are the actual problems I hit, the rabbit holes I went down, and how I got out of them. If you're building this lab and something breaks, chances are I've already broken it worse.

## Problem: Splunk Shows Nothing At All

**What I Checked:**

First, I verified the Universal Forwarder service was actually running on the DC. It was. Then I tested network connectivity with `Test-NetConnection 192.168.56.106 -Port 9997`. That worked too. So the problem wasn't the network.

I checked the inputs.conf on the forwarder and realized the WinEventLog stanza was missing the `index = main` directive. Events were being forwarded but dropped because the indexer didn't know where to put them. Added the index, restarted the forwarder, and logs started flowing.

**Lesson:** Always check the obvious first. Is the service running? Is the port open? Is the config file actually pointing where you think it is?

---

## Problem: Hydra Can't Reach the DC

This one consumed about two hours of my life. The symptoms were weird: ping worked, but SMB connections timed out. No logs anywhere. Just silence.

**Layer 1: Physical/Virtual**
Checked that both VMs were on the same host-only network. They were. VirtualBox showed both adapters as "Up."

**Layer 2: ARP**
Ran `arp -a` on REMnux. The DC's MAC address was resolving correctly. So Layer 2 was fine.

**Layer 3: Routing**
`ip route get 192.168.56.102` on REMnux showed the packet going out `enp0s8` to `192.168.56.254`. That looked correct. But then I checked Kali (which I had on the WAN segment) and realized `ip route` showed a Docker bridge interface with a higher priority route. Docker was intercepting traffic meant for the DC and sending it into a container network that had no idea what to do with it.

**Layer 4: Firewall**
Even after fixing routing on Kali, SMB still failed. I checked OPNsense live logs (Firewall -> Log Files -> Live View) and saw nothing. That was suspicious. If traffic was hitting the firewall, I'd see drops or passes. The absence of logs meant the firewall wasn't even seeing the traffic.

Then I remembered: OPNsense has a default setting on WAN interfaces called "Block Private Networks." Since this is a lab using RFC 1918 addresses everywhere, OPNsense was dropping all WAN traffic before firewall rules were evaluated. I unchecked that box, and suddenly the live logs lit up with SMB pass events.

**Layer 7: Host-Based**
Now traffic was reaching the DC, but Windows Firewall blocked it. Even though I had added allow rules, the firewall was treating cross-subnet traffic as "Public" profile traffic. I temporarily disabled Windows Firewall with `Set-NetFirewallProfile -Enabled False`, confirmed the attack worked, then re-enabled it and added explicit allow rules for the lab subnets.

**Lesson:** Silent failures are the worst kind. When nothing shows up in logs, work backwards from Layer 7 to Layer 1. Something is dropping the traffic before it ever reaches your detection logic.

---

## Problem: Source IP Shows Wrong Address in Splunk

I spent twenty minutes looking for `192.168.56.12` in Splunk and couldn't find it. The source IP field showed `192.168.56.1` instead. I thought the Universal Forwarder was misconfigured.

Turns out VirtualBox's host-only adapter does NAT translation for traffic originating from VMs. The DC sees the VirtualBox host adapter IP (`192.168.56.1`) as the source, not the actual VM IP. This is specific to VirtualBox networking and wouldn't happen on physical hardware or proper routed VLANs.

**Lesson:** Know your virtualization platform's networking quirks. Attribution in virtual labs requires understanding how the hypervisor handles traffic.

---

## Problem: Dashboard Time Range Shows No Data

I built the dashboard, ran the attack, and saw... nothing. The dashboard was blank. I panicked for a minute, then realized the default time range was "Last 24 hours" and my attack had happened five minutes ago. I changed the panel time ranges to "Last 15 minutes" and the data appeared immediately.

**Lesson:** Always check your time range picker before assuming your query is broken.

---

## The Real Lesson

In a real SOC, you don't get a "404 Not Found" error when detection fails. You get silence. The firewall looks correct, the SIEM looks correct, but the logs don't show up. Working through these issues in a lab taught me to trust the process: isolate variables, test one layer at a time, and never assume a component is working just because it should be.
