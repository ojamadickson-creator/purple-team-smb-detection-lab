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

This is the internal corporate network. The Domain Controller lives here at `192.168.56.102`. Splunk is at `192.168.56.106`. REMnux, which I used as the attack platform, sits at `192.168.57.12`.

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

One weird thing I noticed: Splunk recorded the source IP as `192.168.56.1`, not `192.168.56.12`. Turns out VirtualBox's host-only adapter does some NAT trickery behind the scenes. It doesn't break the detection, but it's worth knowing if you're trying to attribute traffic in a virtual environment.

---

## What I Actually Built

### Network Segmentation with OPNsense

I used OPNsense 26.7 as the perimeter firewall. The original SOP I was working from mentioned pfSense, but the actual lab uses OPNsense. The WAN interface faces the untrusted segment, and the LAN interface faces the internal network. I had to uncheck "Block Private Networks" on the WAN interface because this is a lab using RFC 1918 addresses everywhere. Without that change, OPNsense drops traffic before firewall rules even get evaluated.

The rules I configured are simple but deliberate:
- Allow ICMP for diagnostics
- Allow DNS to the DC for resolution
- Allow LDAP for enumeration
- Allow SMB (port 445) for the attack vector
- Default deny everything else

Rule order matters. A lot. If the deny rule sits above the pass rule, nothing gets through. I learned that the hard way.

### Windows Domain Controller Hardening

The DC runs Windows Server 2016. I enabled all three Windows Firewall profiles (Domain, Public, Private) and added granular allow rules for the lab subnets. Here's the thing about Windows Firewall that caught me off guard: it treats cross-subnet traffic as "external" even when everything is in a lab. So traffic from the WAN segment gets evaluated against the Public profile, not Domain. I had to explicitly allow SMB from the lab IP ranges to get authentication attempts through.

### Log Ingestion Pipeline

I deployed the Splunk Universal Forwarder on the DC to ship `WinEventLog:Security` to the main index. For network visibility, I configured OPNsense to forward firewall syslogs via UDP 514. That dual visibility is what makes the cross-source correlation possible. Without the firewall logs, you're blind to reconnaissance. Without the endpoint logs, you're blind to whether the attack actually succeeded.

### Detection Engineering

This is where the project gets fun. I wrote three SPL queries that work together.

**Failed Login Detection:**
```spl
index=main sourcetype=WinEventLog EventCode=4625
| stats count by src_ip
| where count > 5
| rename count as Failed_Attempts
| sort - Failed_Attempts
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

My first attack attempt failed completely. No logs. No errors. Just silence. I spent an hour checking Splunk queries before I realized the traffic wasn't even reaching the DC. OPNsense was dropping all private network traffic on the WAN interface because "Block Private Networks" was checked by default. The fix was simple once I found it, but finding it required checking OPNsense live logs and realizing the firewall was rejecting packets before rules were evaluated.

**Windows Firewall Said No**

After fixing OPNsense, the traffic reached the DC but got blocked by Windows Firewall. Even though I had added allow rules, the firewall treated cross-subnet SMB as external traffic and applied the Public profile. I temporarily disabled the firewall to isolate the variable, confirmed traffic flowed, then re-enabled it and added explicit rules for the lab subnets.

**Docker Hijacked My Routing**

Kali Linux had Docker installed, and Docker's iptables NAT rules were intercepting inter-subnet traffic. I flushed the Docker rules and eventually moved the attack to REMnux on the LAN segment to simplify the topology.

**The IP Mismatch**

I kept looking for `192.168.56.12` in Splunk and couldn't find it. The source IP showed up as `192.168.56.1` instead. After some head-scratching, I realized VirtualBox's host-only adapter was doing NAT translation. The detection still works, but attribution in virtual labs requires understanding this behavior.

These aren't bugs in the project. They're realistic troubleshooting scenarios. In a real SOC, you deal with silent failures, misconfigured firewalls, and routing issues every day. Working through them in a lab is exactly the kind of experience that translates to production environments.

---

## MITRE ATT&CK Mapping

| Tactic | Technique ID | Technique Name | Evidence |
|--------|-------------|----------------|----------|
| Credential Access | T1110 | Brute Force | 99 failed authentication attempts in under three minutes |
| Credential Access | T1110.001 | Password Guessing | Hydra iterating a custom password list against SMB |
| Initial Access | T1078 | Valid Accounts | Successful logon with compromised `vagrant` credentials |
| Lateral Movement | T1021.002 | SMB/Windows Admin Shares | SMB over TCP 445 used for authentication attempts |

I didn't include T1083 (File and Directory Discovery) because this simulation only covers authentication, not post-compromise activity. If I expand this project later, that would be a natural next step.

---

## Skills I Used

| Skill | How I Used It |
|-------|---------------|
| Network Security Architecture | Designed segmented networks with OPNsense, configured NAT traversal, and managed subnet isolation |
| Adversarial Simulation | Configured Hydra on REMnux, built a custom password list, and executed a password spray campaign |
| Host-Based Hardening | Managed Windows Firewall profiles, created granular inbound rules, and validated cross-subnet behavior |
| SIEM Detection Engineering | Wrote SPL queries, tuned the threshold at five attempts, built timechart visualizations, and used subsearch logic |
| Incident Analysis | Correlated EventCode 4625 with 4624, attributed activity to source IPs, and reconstructed the attack timeline |
| Troubleshooting | Used ping, traceroute, arping, iptables, and OPNsense live logs to isolate silent failures layer by layer |
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
```

---

## Quick Start

### What You Need
- VirtualBox 7.0 or newer
- Vagrant 2.4 or newer
- At least 16 GB RAM for the VMs
- About 100 GB free disk space

### Deploy Everything
```bash
git clone https://github.com/YOUR_USERNAME/smb-brute-force-detection.git
cd smb-brute-force-detection/deployment
chmod +x deploy.sh
./deploy.sh
```

The script validates your environment, creates the host-only networks, imports the base boxes, provisions each VM, and gives you the access URLs.

### Validate the Detection
After deployment:
1. Open Splunk at `http://192.168.56.106:8000`
2. Open OPNsense at `https://192.168.57.254`
3. SSH into REMnux and run: `hydra -l vagrant -P /tmp/passwordlist smb://192.168.56.102`
4. Watch the Splunk dashboard populate with failed attempts, then the successful login

---

## What I Learned

**Layered detection actually matters.** Combining perimeter firewall logs with endpoint events gives you context that neither source provides alone. The firewall tells you someone is knocking. The DC tells you whether they got in.

**Threshold tuning is an art, not a science.** I started with a threshold of two and got flooded with noise from my own testing. I bumped it to twenty and realized I'd miss a slow password spray. Five attempts in five minutes felt right for this environment, but in production you'd baseline against real user behavior.

**Dashboards should tell stories.** A table of raw events is useless under pressure. My three-panel layout guides the analyst: first, here's the attack. Second, here's what it looks like over time. Third, here's whether we lost. That's the entire investigation in one screen.

**The hardest part wasn't the attack. It was the silence.** When Hydra failed the first time, there was no error message. No log. Just nothing. Diagnosing that required checking ARP tables, routing tables, firewall logs, and host-based controls. That's exactly what SOC analysts do when an expected alert doesn't fire.

---

## Interview Talking Points

> "I built this lab because I wanted to know if I could detect a brute force attack from start to finish. Not just write a query, but architect the network, simulate the attacker, troubleshoot the failures, and build a dashboard that tells the story. The first attack failed completely. OPNsense was dropping private network traffic before rules were evaluated. Windows Firewall was blocking cross-subnet SMB. Docker on Kali hijacked the routing table. Working through those issues taught me more than any tutorial could."

> "My dashboard has three panels that answer three questions. First: is someone attacking us? The failed login table shows 99 attempts from one IP, well above my threshold of five. Second: what does the attack look like? The timechart shows a massive spike in a two-minute window, which is the signature of automated tooling. Third: did they succeed? The successful login panel shows one EventCode 4624 from the same IP, confirming the vagrant account was compromised. In a production SOC, that third panel triggers an immediate escalation."

---

## Connect

If you're a recruiter, hiring manager, or security engineer who wants to talk shop, I'd love to hear from you. This repository has everything you need to replicate the lab, adapt the detection logic, or just see how I think through problems.

**LinkedIn:** https://www.linkedin.com/in/ojama-d-28a13814a  
**YouTube:** [Your YouTube Channel URL]  
**Email:** [Your Email Address]

---

*Built with patience, packet captures, and the stubborn refusal to accept "it should work" as an answer.*
