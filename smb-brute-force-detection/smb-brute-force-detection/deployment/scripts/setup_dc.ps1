# Domain Controller Setup and Hardening Script
# Run this as Administrator on the Windows Server 2016 VM

Write-Host "========================================" -ForegroundColor Cyan
Write-Host "Domain Controller Configuration" -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan

# Start Windows Firewall service
Start-Service mpssvc -ErrorAction SilentlyContinue
Set-Service mpssvc -StartupType Automatic

# Enable all firewall profiles
Set-NetFirewallProfile -Profile Domain,Public,Private -Enabled True
Write-Host "[*] Windows Firewall enabled on all profiles" -ForegroundColor Green

# Add granular allow rules for lab traffic
New-NetFirewallRule -DisplayName "Allow Lab ICMP" `
    -Direction Inbound -Protocol ICMPv4 `
    -RemoteAddress @("192.168.56.0/24", "192.168.57.0/24") `
    -Action Allow -ErrorAction SilentlyContinue

New-NetFirewallRule -DisplayName "Allow Lab SMB" `
    -Direction Inbound -Protocol TCP -LocalPort 445 `
    -RemoteAddress @("192.168.56.0/24", "192.168.57.0/24") `
    -Action Allow -ErrorAction SilentlyContinue

Write-Host "[*] Firewall rules added for ICMP and SMB" -ForegroundColor Green

# Install Splunk Universal Forwarder
$UFInstaller = "C:\vagrant\splunkforwarder.msi"
if (Test-Path $UFInstaller) {
    Start-Process msiexec.exe -ArgumentList "/i `"$UFInstaller`" AGREETOLICENSE=Yes /quiet" -Wait
    Write-Host "[*] Splunk Universal Forwarder installed" -ForegroundColor Green

    # Configure inputs for Security log forwarding
    $InputsDir = "C:\Program Files\SplunkUniversalForwarder\etc\apps\WinEventLog\local"
    New-Item -ItemType Directory -Path $InputsDir -Force | Out-Null

    @"
[WinEventLog://Security]
disabled = 0
start_from = oldest
current_only = 0
checkpointInterval = 5
index = main
"@ | Set-Content "$InputsDir\inputs.conf"

    # Configure outputs to Splunk indexer
    $OutputsDir = "C:\Program Files\SplunkUniversalForwarder\etc\system\local"
    New-Item -ItemType Directory -Path $OutputsDir -Force | Out-Null

    @"
[tcpout]
defaultGroup = default-autolb-group

[tcpout:default-autolb-group]
server = 192.168.56.106:9997

[tcpout-server://192.168.56.106:9997]
"@ | Set-Content "$OutputsDir\outputs.conf"

    Restart-Service SplunkForwarder
    Write-Host "[*] Universal Forwarder configured and started" -ForegroundColor Green
} else {
    Write-Host "[!] Splunk Forwarder installer not found at $UFInstaller" -ForegroundColor Yellow
    Write-Host "    Place splunkforwarder.msi in the deployment directory" -ForegroundColor Yellow
}

# Verify configuration
Write-Host "`n[*] Firewall Status:" -ForegroundColor Cyan
Get-NetFirewallProfile | Select-Object Name, Enabled | Format-Table

Write-Host "[*] Network Configuration:" -ForegroundColor Cyan
Get-NetIPAddress -AddressFamily IPv4 | Where-Object { $_.IPAddress -like "192.168.56.*" } | Format-Table IPAddress, InterfaceAlias

Write-Host "`n========================================" -ForegroundColor Green
Write-Host "Domain Controller setup complete" -ForegroundColor Green
Write-Host "========================================" -ForegroundColor Green
