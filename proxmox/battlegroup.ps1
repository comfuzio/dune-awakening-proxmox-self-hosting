#Requires -RunAsAdministrator

# Configuration
$vmIP = "192.168.1.50" # REPLACE THIS WITH YOUR PROXMOX VM IP
$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path

# Initialize SSH Key[cite: 1]
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

$menuCommands = @(
    [pscustomobject]@{ Name = "status";    Desc = "Shows status of battlegroup" }
    [pscustomobject]@{ Name = "start";     Desc = "Starts the battlegroup" }
    [pscustomobject]@{ Name = "stop";      Desc = "Stops the battlegroup" }
    [pscustomobject]@{ Name = "update";    Desc = "Updates game server binaries" }
    [pscustomobject]@{ Name = "shell-vm";  Desc = "Open SSH terminal to VM" }
)

while ($true) {
    Write-Host "`n--- Dune Proxmox Manager ($vmIP) ---" -ForegroundColor Yellow
    for ($i = 0; $i -lt $menuCommands.Count; $i++) {
        Write-Host ("  {0,2}. {1,-22} {2}" -f ($i + 1), $menuCommands[$i].Name, $menuCommands[$i].Desc)
    }
    Write-Host ("  {0,2}. quit" -f ($menuCommands.Count + 1))

    $choice = Read-Host "`nSelect an option"
    if ($choice -eq ($menuCommands.Count + 1)) { break }
    
    $cmd = $menuCommands[[int]$choice - 1].Name

    if ($cmd -eq "shell-vm") {
        ssh -t -o StrictHostKeyChecking=no -i "$bundledKey" "dune@$vmIP"
    } else {
        # Remote execution of the internal battlegroup tool[cite: 1]
        ssh -t -o StrictHostKeyChecking=no -i "$bundledKey" "dune@$vmIP" "/home/dune/.dune/bin/battlegroup $cmd"
    }
}
