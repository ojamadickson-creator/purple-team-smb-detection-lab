# SMB Brute Force Attack Detection & Response

[![Lab](https://img.shields.io/badge/Environment-VirtualBox-blue)](https://www.virtualbox.org/)
[![SIEM](https://img.shields.io/badge/SIEM-Splunk%2010.4.2-green)](https://www.splunk.com/)
[![Firewall](https://img.shields.io/badge/Firewall-OPNsense-orange)](https://opnsense.org/)
[![Attacker](https://img.shields.io/badge/Attacker-REMnux-red)](https://remnux.org/)
[![Target](https://img.shields.io/badge/Target-Windows%20Server%202016-purple)](https://www.microsoft.com/)

> **YouTube Demo:** [Watch the full attack and detection walkthrough](https://www.youtube.com/watch?v=wYPfKIGx95Y) 

---

## What This Project Is About

I built this lab because I got tired of reading about detection engineering in theory and wanted to actually do it. You know how it goes. You read a hundred blog posts about "best practices for brute force detection" but nobody shows you the part where nothing works for three hours and you question every life choice that led you to this moment.

So I built the whole thing from scratch inside VirtualBox. Every VM. Every firewall rule. Every Splunk query. I didn't follow a tutorial step by step because honestly, tutorials never break the way real infrastructure breaks. I broke things myself, fixed them, broke them again, and documented what actually happened.

The attack is simple enough: Hydra on REMnux sprays one hundred passwords against a Windows Domain Controller over SMB port 445. The detection side is where it gets interesting. I stood up Splunk Enterprise, tuned the Universal Forwarder on the DC, and built a dashboard that turns raw Event IDs into something you can actually read in seconds.

---

## The Architecture

The entire lab lives inside VirtualBox across three network segments. Two are host-only for internal traffic, and one is NAT for internet access.

**LAN Segment (Host-Only Primary):** `192.168.56.0/24`

This is the internal corporate network. The Domain Controller lives here at `192.168.56.102`. Splunk is at `192.168.56.106`. REMnux, which I used as the attack platform, sits at `192.168.57.12` on the WAN segment.

**WAN Segment (Host-Only #2):** `192.168.57.0/24`

This simulates the external untrusted network. OPNsense faces this segment on its WAN interface at `192.168.57.254`. I originally put Kali Linux here at `192.168.57.10` to test perimeter rules, but routing issues forced me to pivot. More on that later.

**NAT Segment:** `10.0.2.0/24`

Standard VirtualBox NAT. Gives every VM outbound internet access for updates without bridging them to the host's physical network.

The attack path that actually worked looks like this:

```
REMnux (192.168.57.12) 
  -> OPNsense LAN Gateway (192.168.56.254) 
  -> Domain Controller (192.168.56.102:445) 
  -> Windows Event Log (4625/4624) 
  -> Splunk Universal Forwarder 
  -> Splunk SIEM (192.168.56.106) 
  -> Detection Dashboard
```

One weird thing I noticed: Splunk recorded the source IP as 192.168.56.1, not 192.168.57.12 where REMnux actually lives. I never fully traced why — it could be VirtualBox adapter behavior, OPNsense NAT, or something else in the virtualized path. The detection still works fine, but precise IP attribution in this lab environment requires keeping that quirk in mind.
---

## What I Actually Built

### Network Segmentation with OPNsense

I used OPNsense 26.7 as the perimeter firewall. The WAN interface faces the untrusted segment, and the LAN interface faces the internal network. I had to uncheck "Block Private Networks" on the WAN interface because this is a lab using RFC 1918 addresses everywhere. Without that change, OPNsense drops traffic before firewall rules even get evaluated.

The rules I configured are simple but deliberate:
- Allow ICMP for diagnostics
- Allow DNS to the DC for resolution
- Allow LDAP for enumeration
- Allow SMB (port 445) for the attack vector
- Default deny everything else

Rule order matters. A lot. If the deny rule sits above the pass rule, nothing gets through. I learned that the hard way.

### Windows Domain Controller Hardening

The DC runs Windows Server 2016.After fixing OPNsense, traffic still wasn't getting through to the DC. Based on my troubleshooting notes, Windows Firewall was blocking the SMB connection attempts. I worked through the firewall configuration until authentication attempts started succeeding. The exact sequence involved testing with the firewall disabled to isolate the variable, then re-enabling it with proper allow rules.

### Log Ingestion Pipeline

I deployed the Splunk Universal Forwarder on the DC to ship `WinEventLog: Security, Application, and System logs to the main index. For network visibility, I configured OPNsense to forward firewall syslogs via UDP 514. That dual visibility is what makes the cross-source correlation possible. Without the firewall logs, you're blind to reconnaissance. Without the endpoint logs, you're blind to whether the attack actually succeeded.

### Detection Engineering

This is where the project gets fun. I wrote three SPL queries that work together.

**Failed Login Detection:**
```spl
index=main sourcetype=WinEventLog EventCode=4625
| stats count by src_ip
| where count > 5
```

Why five? Because normal users don't fat-finger their password six times in a row. Automated tools like Hydra do. Five is the sweet spot. Low enough to catch real attacks fast, high enough to avoid alert fatigue from someone who just got a new keyboard.

**Time-Series Visualization:**
```spl
index=main sourcetype=WinEventLog EventCode=4625
| timechart span=1m count by src_ip
```

This produces a chart that tells the story visually. During the attack, you see a massive spike in a one-minute window. Normal authentication looks flat. A brute force looks like a skyscraper.

**Cross-Source Correlation:**
```spl
index=main (sourcetype=syslog "pass") OR (host=dc EventCode=4625)
| eval attack_phase=case(
    sourcetype="syslog" AND dst_port="445", "Phase 3: SMB Auth Attempt",
    host="dc" AND EventCode=4625, "Phase 3a: Failed Windows Logon")
| stats count by _time, attack_phase, src_ip
| sort _time
```

This fuses perimeter and endpoint telemetry into a single timeline. You can see the firewall allowing the SMB connection, then the DC rejecting the credentials, all attributed to the same source. That's the difference between knowing something hit your perimeter and knowing something is actively compromising your domain.

### The Dashboard

I built a Splunk dashboard called "Brute Force login Attempts" with three panels:

1. **Failed Login Table:** Source IP and total count, filtered to anything above five. During validation, this showed `192.168.56.1` with exactly 99 failed attempts.

2. **Failed Login Chart:** A column chart showing volume per minute. The attack produced a sharp spike that dominates the timeline.

3. **Successful Logins Table:** Lists EventCode 4624 entries. This answers the question that matters most: did they get in? In my test, the answer was yes. One successful login from `192.168.56.1` confirmed the `vagrant` account was compromised.

---

## The Attack Simulation

On REMnux, I generated a custom password list of one hundred entries. The last entry was `vagrant`, the known-valid credential for this lab environment. I did this so the simulation would guarantee a successful compromise for validation purposes. In a real scenario, the attacker wouldn't know the password, but the detection logic works the same either way.

The command:
```bash
hydra -l vagrant -P /tmp/passwordlist smb://192.168.56.102
```

Hydra v9.5 completed its run in about two seconds. Yes, seconds. It tried all one hundred passwords, failed on ninety-nine of them, and succeeded on the last one. The Splunk dashboard captured every single event.

---

## What Went Wrong (And How I Fixed It)

This project would have been a lot shorter if everything worked the first time. It didn't. Here's what actually happened.

**The Silent Drop**

My initial attack attempts failed silently. Based on my troubleshooting notes, OPNsense was dropping traffic because the WAN interface had "Block Private Networks" enabled by default. Once I unchecked that setting, traffic started flowing. I documented this in my lab notes but didn't capture screenshots of the initial failure state.

**Windows Firewall Said No**

After fixing OPNsense, traffic still wasn't getting through to the DC. Based on my lab notes, I worked through Windows Firewall configuration until SMB authentication attempts succeeded. The exact steps involved isolating whether the host-based firewall was the blocking control and adjusting the rules accordingly.

**Docker Hijacked My Routing**


I initially planned to use Kali Linux on the WAN segment, but ran into routing complications. I pivoted to REMnux on the WAN segment at 192.168.57.12, which gave me a clean attack path through the OPNsense firewall to the DC. The attack succeeded from that position, validating the perimeter-to-internal detection pipeline.

**The IP Mismatch**

I kept looking for 192.168.57.12 in Splunk and couldn't find it. The source IP showed up as 192.168.56.1 instead. I never fully traced why — it could be VirtualBox adapter behavior, OPNsense NAT, or something else in the virtualized path. The detection still works fine, but precise IP attribution in this lab environment requires keeping that quirk in mind.

---

## MITRE ATT&CK Mapping

| Tactic | Technique ID | Technique Name | Evidence |
|--------|-------------|----------------|----------|
| Credential Access | T1110 | Brute Force | 99 failed authentication attempts in approximately 2 seconds |
| Credential Access | T1110.001 | Password Guessing | Hydra iterating a custom password list against SMB |
| Initial Access | T1078 | Valid Accounts | Successful logon with compromised vagrant credentials |
SMB/445 was the protocol used for initial access, which could also map to T1021.002 under Lateral Movement in a multi-system scenario.
I didn't include T1083 (File and Directory Discovery) because this simulation only covers authentication, not post-compromise activity. If I expand this project later, that would be a natural next step.

---

## Skills I Used

| Skill | How I Used It |
|-------|---------------|
| Network Security Architecture | Designed segmented networks with OPNsense, configured NAT traversal, and managed subnet isolation |
| Adversarial Simulation | Configured Hydra on REMnux, built a custom password list, and executed a password spray campaign |
| SIEM Detection Engineering | Wrote SPL queries, tuned the threshold at five attempts, built timechart visualizations, and used sub search logic |
| Incident Analysis | Correlated EventCode 4625 with 4624, attributed activity to source IPs, and reconstructed the attack timeline |
| Troubleshooting | Used ping to verify layer-3 connectivity from REMnux to the DC, then iteratively diagnosed why SMB traffic wasn't reaching the target through the OPNsense firewall and Windows host-based controls |
| Cross-Source Correlation | Fused OPNsense syslog with Windows Event Logs to create a multi-dimensional view of the attack |

---

## Repository Layout

```
smb-brute-force-detection/
├── README.md                          # This file
├── EXECUTIVE_SUMMARY.md               # One-page summary for hiring managers
├── deployment/                        # One-click deployment scripts
│   ├── Vagrantfile                    # Multi-VM orchestration
│   ├── scripts/
│   │   ├── setup_splunk.sh            # Automated Splunk installation
│   │   ├── setup_dc.ps1               # DC hardening and UF deployment
│   │   ├── setup_remnux.sh            # Attack platform configuration
│   │   └── setup_opnsense.sh          # Firewall bootstrap commands
│   └── deploy.sh                      # Master deployment script
├── spl_queries/                       # Production-ready SPL
│   ├── failed_login_detection.spl
│   ├── successful_compromise.spl
│   ├── cross_correlation.spl
│   └── timechart_visualization.spl
├── dashboards/                        # Splunk dashboard XML
│   └── brute_force_dashboard.xml
├── password_lists/                    # Sample wordlist for testing
│   └── top_100.txt
├── docs/                              # Deep-dive documentation
│   ├── ARCHITECTURE.md
│   ├── TROUBLESHOOTING.md
│   └── VALIDATION.md
└── assets/                            # Screenshots and diagrams
    ├── topology.png
    ├── dashboard_results.png
    ├── attack_terminal.png
    └── mindmap.png


---

## What I Learned

**Layered detection actually matters. Combining perimeter firewall logs with endpoint events gives you context that neither source provides alone. The firewall tells you someone is knocking. The DC tells you whether they got in.

**Threshold tuning requires deliberate thought. I settled on five failed attempts because normal users rarely miss their password more than twice, while automated tools like Hydra generate dozens or hundreds in seconds. In production you'd baseline this against real user behavior.

**Dashboards should tell stories. A table of raw events is useless under pressure. My three-panel layout guides the analyst: first, here's the attack. Second, here's what it looks like over time. Third, here's whether we lost. That's the entire investigation in one screen.

**The hardest part wasn't the attack. It was getting the traffic to flow correctly through OPNsense and ensuring Splunk was actually receiving the logs. That's exactly what SOC analysts do when an expected alert doesn't fire.
---


> I built this lab because I wanted to know if I could detect a brute force attack from start to finish. Not just write a query, but architect the network, simulate the attacker, and build a dashboard that tells the story. Getting the traffic to flow correctly through OPNsense and into Splunk was where most of the learning happened.

> My dashboard has three panels that answer three questions. First: is someone attacking us? The failed login table shows 99 attempts from one IP, well above my threshold of five. Second: what does the attack look like? The timechart shows a massive spike in a one-minute window, which is the signature of automated tooling. Third: did they succeed? The successful login panel shows one EventCode 4624 from the same IP, confirming the vagrant account was compromised. In a production SOC, that third panel triggers an immediate escalation.
---

## Connect

If you're a recruiter, hiring manager, or security engineer who wants to talk shop, I'd love to hear from you. This repository has everything you need to replicate the lab, adapt the detection logic, or just see how I think through problems.

**LinkedIn:** https://www.linkedin.com/in/ojama-d-28a13814a  
**YouTube:** https://www.youtube.com/watch?v=wYPfKIGx95Y  
**Email:** ojamadickson@gmail.com

---

*Built with patience, packet captures, and the stubborn refusal to accept "it should work" as an answer.*
