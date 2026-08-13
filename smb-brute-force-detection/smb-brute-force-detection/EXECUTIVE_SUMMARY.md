# Executive Summary: SMB Brute Force Detection & Response

**Project Owner:** [Your Name]  
**Date:** August 2026  
**Environment:** VirtualBox Lab with OPNsense, Splunk Enterprise 10.4.2, Windows Server 2016, REMnux  
**Classification:** Portfolio / Purple Team Demonstration

---

## The Bottom Line

This project demonstrates end-to-end detection engineering capability. I architected a segmented virtual network, simulated a realistic SMB brute force attack, and built a Splunk dashboard that detects the attack and confirms account compromise. The entire pipeline is automated and deployment-ready.

---

## Why This Matters

Brute force attacks against SMB remain one of the most common initial access vectors in enterprise environments. Attackers use tools like Hydra and CrackMapExec to spray credentials across Domain Controllers. Without proper detection, these attacks succeed silently. With proper detection, security teams can interdict the threat during the exploitation phase, before lateral movement begins.

This project answers a single critical question: can we detect and confirm an SMB brute force attack in real time, with high fidelity and low false positives?

The answer is yes, and this repository contains everything required to prove it.

---

## What Was Accomplished

A fully segmented network was built inside VirtualBox using OPNsense 26.7 as a perimeter firewall. A Windows Server 2016 Domain Controller served as the target. A Splunk Enterprise instance was deployed with the Universal Forwarder ingesting Windows Security Events. REMnux on the WAN segment served as the attack platform.

I generated a custom password list of one hundred entries, ending with the known-valid credential to guarantee a successful compromise for validation purposes. Hydra v9.5 was used to execute the attack over SMB port 445.

Three SPL queries were engineered to detect the attack. The primary query aggregates EventCode 4625 failures by source IP and applies a threshold of five attempts. A secondary query uses timechart visualization to reveal the attack burst pattern. A tertiary query correlates OPNsense firewall syslog with Windows events to reconstruct the full kill chain.

A Splunk dashboard named "Brute Force login Attempts" was built with three panels: failed login attribution, time-series visualization, and successful login confirmation. During live validation, the dashboard captured ninety-nine failed attempts from `192.168.56.1` followed by successful authentication of the `vagrant` account.

---

## Technical Highlights

**Network Architecture:** Dual host-only segments (LAN and WAN) with OPNsense routing between them. NAT segment for outbound internet connectivity.

**Firewall Configuration:** Granular pass rules for ICMP, DNS, LDAP, and SMB. Explicit rule ordering above default deny. Private network blocking disabled for lab RFC 1918 traffic.

**Attack Simulation:** Hydra v9.5 on REMnux at `192.168.57.12`. One hundred password attempts in approximately two seconds. Target: Domain Controller at `192.168.56.102` over SMB.

**Detection Logic:** Threshold-based alerting at five failed attempts. Time-windowed aggregation at one-minute spans. Cross-source correlation between firewall syslog and Windows Event Logs.

**Validation Results:** 99 failed logons (EventCode 4625), 1 successful logon (EventCode 4624), source IP attributed to `192.168.56.1`, attack duration approximately two seconds.

---

## Skills Profile

This project required and demonstrated the following capabilities:

1. **Network Security Architecture:** Designing and implementing segmented networks with proper routing, NAT, and firewall rule ordering.

2. **Adversarial Simulation:** Configuring attack tooling, generating custom wordlists, and executing password spray campaigns in a controlled environment.

3. **SIEM Engineering:** Authoring SPL queries, tuning detection thresholds, building real-time dashboards, and correlating disparate log sources.

4. **Incident Analysis:** Reconstructing attack timelines from raw logs, attributing activity to source IPs, and confirming compromise through EventCode correlation.

5. **Troubleshooting:** Used ping to verify layer-3 connectivity and systematically worked through OPNsense configuration until SMB authentication attempts and log ingestion succeeded.

---

## Return on Investment

For a security operations team, this detection pipeline translates directly into reduced mean time to detect (MTTD) and mean time to respond (MTTR). The dashboard allows a Tier 1 analyst to identify a brute force campaign and confirm compromise in seconds rather than hours. The threshold tuning eliminates false positives that create alert fatigue. The cross-source correlation provides the context needed for immediate escalation and containment.

For a hiring manager, this project proves the ability to build, simulate, and detect. It is not a tutorial walkthrough. It is an original engineering effort that produced a working result.

---

## Next Steps

1. Deploy the lab using the automated Vagrant scripts in the `deployment/` directory.
2. Execute the validation attack and observe the dashboard.
3. Review the SPL queries and dashboard XML for adaptation to a production environment.
4. Read the deep-dive documentation in `docs/` for architecture decisions and troubleshooting methodology.

---

*This project was built to demonstrate practical detection engineering. Every component was configured manually, and every detection was validated with live attack data.*
