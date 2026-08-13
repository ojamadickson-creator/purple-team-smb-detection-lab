# Troubleshooting Guide

This lab did not work on the first try. It evolved through several phases: starting with DetectionLab, adding OPNsense as a perimeter firewall, migrating from a Windows Splunk instance to Ubuntu, and eventually using REMnux as the attack platform. Each phase broke something. Here is what actually happened, separated into the issues I can prove and the issues documented in my setup guides.

---

## Problem: Windows Events Not Appearing in Splunk

**What happened:**

After migrating from the original Windows FlareVM Splunk to Ubuntu Splunk, the DC forwarder connected but no Windows events showed up in the index. I could see syslog from OPNsense, but `sourcetype=WinEventLog` returned nothing.

**The real cause:**

I used the wrong Splunk command to open the receiving port. I ran `splunk add tcp 9997`, which creates a raw TCP input expecting plain text. Universal Forwarders send compressed, encrypted "cooked" Splunk protocol data. Splunk could not parse it, so the forwarder timed out and stopped sending.

**The fix:**

Removed the wrong input with `splunk remove tcp 9997`, then added the correct forwarder listener with `splunk enable listen 9997`. Restarted Splunk and the DC forwarder, and Windows events started flowing immediately.

**Lesson:** Universal Forwarders and raw TCP inputs are not the same thing. The command you use to open the port determines whether cooked or plain text data gets accepted.

---

## Problem: Events Arrived But EventCode Field Was Missing

**What happened:**

Windows events were now reaching Splunk, but they looked like binary blobs with `\x00` characters. Fields like `EventCode`, `Account_Name`, and `LogonType` did not appear in the Interesting Fields panel. Any SPL query using `EventCode=4625` returned zero results.

**The real cause:**

Linux Splunk has no built-in Windows Event Log parser. On Windows Splunk, the operating system provides the parsing logic. On Linux, you must install the Splunk Add-on for Microsoft Windows (the Windows TA). Without it, Splunk sees the cooked forwarder envelope but cannot extract the XML fields.

**The fix:**

Downloaded the Windows TA from Splunkbase, transferred it to the Ubuntu VM, and installed it with `splunk install app`. After restarting Splunk, `EventCode` appeared as a clickable field and queries started returning results.

**Lesson:** Migrating a SIEM from Windows to Linux is not just about moving the software. You also need the parsing layer that Windows was providing for free.

---

## Problem: Forwarder Connected But Still No Events

**What happened:**

Even after fixing the TCP input and installing the Windows TA, `index=main sourcetype=WinEventLog` sometimes returned nothing. The forwarder log showed "Connected to idx=192.168.56.106:9997" but the search was empty.

**The real cause:**

The forwarder's `inputs.conf` was missing or empty. The forwarder was talking to Splunk but had no instructions about which Windows Event Logs to collect.

**The fix:**

Created `inputs.conf` on the DC with stanzas for Application, Security, and System logs, all pointing to `index=main`. Restarted the forwarder and events appeared within minutes.

**Lesson:** A forwarder connection does not mean data collection. Check that inputs.conf actually tells the forwarder what to ship.

---

## Problem: No Firewall Syslog in Splunk

**What happened:**

OPNsense syslog was not showing up in Splunk even though the firewall rules were generating traffic.

**The real cause:**

Ubuntu's built-in firewall `ufw` was blocking incoming UDP 514. Additionally, the OPNsense remote logging hostname was pointing to the old Windows Splunk IP instead of the new Ubuntu Splunk IP.

**The fix:**

Disabled `ufw` with `sudo ufw disable`. Verified OPNsense System -&gt; Settings -&gt; Logging -&gt; Remote pointed to `192.168.56.106:514`. Added the UDP input in Splunk with `splunk add udp 514 -sourcetype syslog -index main`.

**Lesson:** When you migrate a SIEM to a new host, every sender needs to know the new IP. Firewalls on the SIEM host itself can also block ingestion.

---

## Problem: OPNsense WAN IP Kept Changing

**What happened:**

After rebooting OPNsense, the WAN interface sometimes showed `10.0.0.5` instead of the configured `192.168.57.254`. Kali could not ping the firewall gateway.

**The real cause:**

A DHCP client was running at boot and grabbing a lease from the old VirtualBox DHCP range that was previously enabled on Host-Only Adapter #2.

**The fix:**

Re-ran the console IP assignment for WAN, set it to static `192.168.57.254/24`, and rebooted. Also disabled DHCP on Host-Only Adapter #2 in VirtualBox Host Network Manager to prevent the issue from recurring.

**Lesson:** VirtualBox host-only adapters with DHCP enabled can override your static configurations. Disable DHCP before the VM ever boots.

---

## Problem: Source IP Shows Wrong Address in Splunk

**What happened:**

I kept looking for `192.168.57.12` (REMnux's actual IP on the WAN segment) in Splunk and could not find it. The source IP field showed `192.168.56.1` instead.

**What I figured out:**

I never fully traced the exact mechanism, but the DC sees `192.168.56.1` as the source instead of the actual VM IP. It could be VirtualBox adapter behavior, OPNsense NAT, or something else in the virtualized path. This is specific to VirtualBox networking and would not happen on physical hardware or properly routed VLANs.

**Lesson:** Know your virtualization platform's networking quirks. Precise IP attribution in virtual labs requires understanding how the hypervisor handles traffic.

---

## Problem: Dashboard Time Range Shows No Data

**What happened:**

I built the dashboard, ran the attack, and saw nothing. The dashboard was blank.

**The real cause:**

The default time range was "Last 24 hours" and my attack had happened five minutes ago.

**The fix:**

Changed the panel time ranges to "Last 15 minutes" and the data appeared immediately.

**Lesson:** Always check your time range picker before assuming your query is broken.

---

## The Real Lesson

In a real SOC, you do not get a "404 Not Found" error when detection fails. You get silence. The firewall looks correct, the SIEM looks correct, but the logs do not show up. Working through these issues taught me to trust the process: check the obvious first, verify configs are pointing to the right places, and never assume a component is working just because it should be.
