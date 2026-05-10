#Requires -RunAsAdministrator

# 1. Configuration (GitHub Default)
$vmIP = "192.168.1.50" 
$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$bundledKey = Join-Path $scriptDir "ssh\sshKey"
$directorPort = $null

# 2. Initialize SSH Key
$tempKey = Join-Path $env:TEMP 'dune-mgmt-key'
if (Test-Path $tempKey) { Remove-Item $tempKey -Force -ErrorAction SilentlyContinue }
Copy-Item $bundledKey $tempKey -Force
icacls $tempKey /inheritance:r /grant:r "${env:USERNAME}:(R)" | Out-Null

$menuCommands = @(
    [pscustomobject]@{ Name = "list";                   Desc = "Lists all available battlegroups" }
    [pscustomobject]@{ Name = "status";                 Desc = "Shows the status of the selected battlegroup" }
    [pscustomobject]@{ Name = "start";                  Desc = "Starts the selected battlegroup" }
    [pscustomobject]@{ Name = "restart";                Desc = "Restarts the selected battlegroup" }
    [pscustomobject]@{ Name = "stop";                   Desc = "Stops the selected battlegroup" }
    [pscustomobject]@{ Name = "update";                 Desc = "Checks for new versions and applies them" }
    [pscustomobject]@{ Name = "edit-battlegroup";       Desc = "Edit settings of the battlegroup" }
    [pscustomobject]@{ Name = "logs-export";            Desc = "Retrieves logs from all pods to your PC" }
    [pscustomobject]@{ Name = "operator-logs-export";   Desc = "Retrieves logs from all operator pods" }
    [pscustomobject]@{ Name = "open-file-browser";      Desc = "Open the file browser in a web browser" }
    [pscustomobject]@{ Name = "open-director";          Desc = "Open the director web app in a web browser" }
    [pscustomobject]@{ Name = "shell-vm";               Desc = "Open an SSH shell on the VM" }
    [pscustomobject]@{ Name = "shell-pod";              Desc = "Open a shell inside a specific pod" }
)

while ($true) {
    Write-Host "`n--- Dune Proxmox Manager ($vmIP) ---" -ForegroundColor Yellow
    for ($i = 0; $i -lt $menuCommands.Count; $i++) {
        Write-Host ("  {0,2}. {1,-22} {2}" -f ($i + 1), $menuCommands[$i].Name, $menuCommands[$i].Desc)
    }
    Write-Host ("  {0,2}. {1,-22} {2}" -f ($menuCommands.Count + 1), "quit", "Exit this script")

    $selection = Read-Host "`nSelect an option"
    if ($selection -eq ($menuCommands.Count + 1)) { break }
    try { $cmd = $menuCommands[[int]$selection - 1].Name } catch { continue }

    if ($cmd -eq "open-file-browser") { Start-Process "http://${vmIP}:18888/"; continue }

    if ($cmd -eq "open-director") {
        $directorNodePort = ssh -o StrictHostKeyChecking=no -o LogLevel=QUIET -i "$tempKey" "root@$vmIP" "kubectl get svc -A -o jsonpath='{.items[*].spec.ports[?(@.port==11717)].nodePort}'"
        if ($directorNodePort -match '^\d+') { Start-Process "http://${vmIP}:$($directorNodePort.Trim())/" }
        else { Write-Warning "Director not ready." }; continue
    }

    if ($cmd -eq "shell-vm") { ssh -t -o StrictHostKeyChecking=no -i "$tempKey" "root@$vmIP"; continue }

    if ($cmd -eq "logs-export" -or $cmd -eq "operator-logs-export") {
        ssh -t -o StrictHostKeyChecking=no -i "$tempKey" "root@$vmIP" "/home/dune/.dune/bin/battlegroup $cmd"
        $localDir = Join-Path $env:USERPROFILE "Documents\DuneLogs\$cmd"
        New-Item -ItemType Directory -Path $localDir -Force | Out-Null
        $remotePath = if ($cmd -eq "logs-export") { "/tmp/dune-bg-logs" } else { "/tmp/dune-operator-logs" }
        & scp -r -o StrictHostKeyChecking=no -i "$tempKey" "root@${vmIP}:${remotePath}/*" "$localDir"
        Write-Host "Logs saved to $localDir" -ForegroundColor Green; continue
    }

    ssh -t -o StrictHostKeyChecking=no -i "$tempKey" "root@$vmIP" "/home/dune/.dune/bin/battlegroup $cmd"
}
