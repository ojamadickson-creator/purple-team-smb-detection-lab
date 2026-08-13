# Validation Procedure

This is the exact process I used to confirm the detection pipeline works. Follow these steps and you should see the same results I did.

## Before You Start

Make sure everything is running:
- All VMs are powered on and reachable
- Splunk is accessible at `http://192.168.56.106:8000`
- The "Brute Force login Attempts" dashboard has been created (or import it from `dashboards/brute_force_dashboard.xml`)
- REMnux on WAN can ping the DC through OPNsense: `ping 192.168.56.102`

## Step 1: Check the Password List

On REMnux, verify the wordlist exists and has the right number of entries:

```bash
wc -l /tmp/passwordlist
```

You should see:
```
100 /tmp/passwordlist
```

The last entry should be `vagrant`, which is the known-valid credential for this lab.

## Step 2: Launch the Attack

On REMnux, run Hydra:

```bash
hydra -l vagrant -P /tmp/passwordlist smb://192.168.56.102
```

Hydra will report something like this:
```
[445][smb] host: 192.168.56.102 login: vagrant password: vagrant
1 of 1 target successfully completed, 1 valid password found
```

The whole run takes about two seconds for one hundred passwords. Hydra is fast.

## Step 3: Check the Dashboard

Open Splunk and navigate to your "Brute Force login Attempts" dashboard. Set the time range to "Last 15 minutes" and look for three things:

**Panel 1: Failed Login**
- Source IP: `192.168.56.1`
- Count: 99 failed attempts

**Panel 2: Failed Login Chart**
- A sharp spike in the one-minute window where Hydra was running
- The rest of the timeline should be flat

**Panel 3: Successful Logins**
- Source IP: `192.168.56.1`
- Count: 1 successful authentication

If you see all three, the detection pipeline is working.

## Step 4: Run the Correlation Query

Paste this into Splunk Search:

```spl
index=main (sourcetype=syslog "pass") OR (host=dc EventCode=4625)
| eval attack_phase=case(
    sourcetype="syslog" AND dst_port="445", "Phase 3: SMB Auth Attempt",
    host="dc" AND EventCode=4625, "Phase 3a: Failed Windows Logon")
| stats count by _time, attack_phase, src_ip
| sort _time
```

You should see a chronological table showing:
- Windows failed logon events
- All attributed to `192.168.56.1`

This proves your perimeter and endpoint telemetry are aligned.

## What Success Looks Like

The validation passes if:
1. Hydra finds the correct password
2. Splunk records at least 90 EventCode 4625 events
3. Splunk records at least 1 EventCode 4624 event from the attacker IP
4. The dashboard visualizes the attack burst clearly
5. Cross-source correlation shows both the phase of attack
## A Note on Source IP Attribution

Splunk will show the source IP as `192.168.56.1`, not `192.168.56.12` (REMnux's actual IP). This is because VirtualBox's host-only adapter performs NAT translation. The detection logic works exactly the same, but if you need precise attribution in a production environment, use physical switches or properly routed VLANs instead of VirtualBox host-only networking.
