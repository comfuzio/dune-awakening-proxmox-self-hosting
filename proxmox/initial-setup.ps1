#Requires -RunAsAdministrator

# Configuration
$vmIP = "192.168.1.50" # REPLACE THIS WITH YOUR PROXMOX VM IP
$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path

# 1. SSH Key Logic (Maintained from original)
$bundledKey = "$scriptDir\ssh\sshKey"
$tempKey = Join-Path $env:TEMP 'dune-awakening-server-sshKey'
if (Test-Path $tempKey) {
    takeown /f $tempKey 2>&1 | Out-Null
    icacls $tempKey /reset 2>&1 | Out-Null
    Remove-Item -Path $tempKey -Force
}
Copy-Item -Path $bundledKey -Destination $tempKey -Force
icacls $tempKey /inheritance:r /grant:r "${env:USERNAME}:(R)" | Out-Null
$bundledKey = $tempKey

Write-Host "Connecting to Proxmox VM at $vmIP..." -ForegroundColor Cyan

# 2. Detect Public IP (Maintained from original)
$publicIP = $null
try {
    $remoteCmd = "wget -qO- --timeout=5 'https://api.ipify.org' 2>/dev/null"
    $raw = & ssh -o StrictHostKeyChecking=no -o LogLevel=QUIET -i "$bundledKey" "dune@$vmIP" $remoteCmd 2>$null
    $publicIP = ($raw | Out-String).Trim()
} catch { $publicIP = $null }

# 3. IP Selection Logic
Write-Host "Select the IP that players will connect to:"
Write-Host "  1. $publicIP [Public IP]" -ForegroundColor Cyan
Write-Host "  2. $vmIP [Private IP]" -ForegroundColor Cyan
$sel = Read-Host "Choice [1/2]"
$selectedIP = if ($sel -eq '1') { $publicIP } else { $vmIP }

# 4. Write settings to VM
Write-Host "Writing IP to VM settings..." -ForegroundColor Cyan
ssh -o StrictHostKeyChecking=no -o LogLevel=QUIET -i "$bundledKey" "dune@$vmIP" "printf '\n\n\n$selectedIP\n' > /home/dune/.dune/settings.conf"

# 5. Run the Bootstrap (The file you just found)[cite: 1]
Write-Host "Running internal Alpine setup script..." -ForegroundColor Cyan
ssh -t -o StrictHostKeyChecking=no -o LogLevel=QUIET -i "$bundledKey" "dune@$vmIP" "/home/dune/.dune/bin/setup"

Write-Host "Setup Complete! You can now manage the server via battlegroup.ps1" -ForegroundColor Green
