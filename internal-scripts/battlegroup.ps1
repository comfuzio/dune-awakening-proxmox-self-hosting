#Requires -RunAsAdministrator

# Logging Section
$logFile = "$scriptDir\..\.logs\battlegroup-$(Get-Date -Format 'yyyy-MM-dd_HH-mm-ss').log"
New-Item -ItemType Directory -Force -Path (Split-Path $logFile) | Out-Null
Start-Transcript -Path $logFile -Append | Out-Null

# Start

$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$directorPort = $null

# Check if VM exists
$vmName = 'dune-awakening'
$vm = Get-VM -Name $vmName -ErrorAction SilentlyContinue
if (-not $vm) {
    Write-Error "VM '$vmName' does not exist. Please create it first."
    exit 1
}

# Copy the bundled key to a fixed temp location and lock that copy down for ssh.
# We don't lock the bundled file in place because OpenSSH's strict ACL leaves
# users unable to delete the repo file later without taking ownership.
# Fixed path means reruns overwrite the same file rather than accumulating.
$bundledKey = "$scriptDir\ssh\sshKey"
$tempKey = Join-Path $env:TEMP 'dune-awakening-server-sshKey'
if (Test-Path $tempKey)
{
    takeown /f $tempKey 2>&1 | Out-Null
    icacls $tempKey /reset 2>&1 | Out-Null
    Remove-Item -Path $tempKey -Force -ErrorAction SilentlyContinue
}
Copy-Item -Path $bundledKey -Destination $tempKey -Force
icacls $tempKey /inheritance:r /grant:r "${env:USERNAME}:(R)" | Out-Null
$bundledKey = $tempKey

$ip = $null
if ($vm.State -eq 'Running') {
    $ip = (Get-VMNetworkAdapter -VMName $vmName).IPAddresses |
          Where-Object { $_ -match '^\d+\.\d+\.\d+\.\d+$' } |
          Select-Object -First 1
}

$_baseCommands = @(
    [pscustomobject]@{ Name = "list";                   Desc = "Lists all available battlegroups" }
    [pscustomobject]@{ Name = "status";                 Desc = "Shows the status of the selected battlegroup" }
    [pscustomobject]@{ Name = "start";                  Desc = "Starts the selected battlegroup" }
    [pscustomobject]@{ Name = "restart";                Desc = "Restarts the selected battlegroup" }
    [pscustomobject]@{ Name = "stop";                   Desc = "Stops the selected battlegroup" }
    [pscustomobject]@{ Name = "update";                 Desc = "Checks for new versions and applies them" }
    [pscustomobject]@{ Name = "edit-battlegroup";       Desc = "Edit settings of the battlegroup" }
    [pscustomobject]@{ Name = "logs-export";            Desc = "Retrieves logs from all pods in the selected battlegroup" }
    [pscustomobject]@{ Name = "operator-logs-export";   Desc = "Retrieves logs from all operator pods" }
    [pscustomobject]@{ Name = "open-file-browser";      Desc = "Open the file browser in a web browser" }
    [pscustomobject]@{ Name = "open-director";          Desc = "Open the director web app in a web browser" }
    [pscustomobject]@{ Name = "shell-vm";               Desc = "Open an SSH shell on the VM" }
    [pscustomobject]@{ Name = "shell-pod";              Desc = "Open a shell inside a pod of the selected battlegroup" }
)

$commands = $_baseCommands
if ($null -ne $_extraCommands -and $_extraCommands.Count -gt 0) {
    $commands = $_baseCommands + $_extraCommands
}

$_stoppedCommands = @(
    [pscustomobject]@{ Name = "start-vm"; Desc = "Start the VM ($vmName)" }
)

$_runningCommands = $commands + @(
    [pscustomobject]@{ Name = "stop-vm";      Desc = "Stop the VM ($vmName)" }
)

while ($true) {
    $vm = Get-VM -Name $vmName
    if ($vm.State -eq 'Running') { $menuCommands = $_runningCommands } else { $menuCommands = $_stoppedCommands }
    $quitIndex = $menuCommands.Count + 1

    Write-Host ""
    if ($vm.State -ne 'Running') {
        Write-Host "VM '$vmName' is currently $($vm.State)." -ForegroundColor Yellow
        Write-Host ""
    }
    Write-Host "Battlegroup commands:"
    Write-Host ""
    for ($i = 0; $i -lt $menuCommands.Count; $i++) {
        Write-Host ("  {0,2}. {1,-22} {2}" -f ($i + 1), $menuCommands[$i].Name, $menuCommands[$i].Desc)
    }
    Write-Host ("  {0,2}. {1,-22} {2}" -f $quitIndex, "quit", "Exit this script")
    Write-Host ""

    $choice = $null
    while ($null -eq $choice) {
        $selection = Read-Host "Select an option (1-$quitIndex)"
        if ($selection -match '^\d+$' -and [int]$selection -ge 1 -and [int]$selection -le $quitIndex) {
            $choice = [int]$selection
        } else {
            Write-Warning "Invalid selection. Enter a number between 1 and $quitIndex."
        }
    }

    if ($choice -eq $quitIndex) { break }

    $cmd = $menuCommands[$choice - 1].Name

    if ($cmd -eq "start-vm") {
        Write-Host "Starting VM '$vmName'..." -ForegroundColor Cyan
        Start-VM -Name $vmName | Out-Null
        do {
            Start-Sleep -Seconds 2
            $vm = Get-VM -Name $vmName
        } while ($vm.State -ne 'Running')
        Write-Host "VM started." -ForegroundColor Green

        $ip = $null
        $timeout = 120
        $elapsed = 0
        $dots = 0
        while (-not $ip -and $elapsed -lt $timeout) {
            $dots = ($dots % 3) + 1
            Write-Host -NoNewline "`rWaiting for VM to acquire an IP address$('.' * $dots)   "
            Start-Sleep -Seconds 1
            $elapsed += 1
            $ip = (Get-VMNetworkAdapter -VMName $vmName).IPAddresses |
                  Where-Object { $_ -match '^\d+\.\d+\.\d+\.\d+$' } |
                  Select-Object -First 1
        }
        Write-Host ""
        if (-not $ip) {
            Write-Warning "Could not determine VM IP after $timeout seconds. Check Hyper-V Manager or run: Get-VMNetworkAdapter -VMName '$vmName'"
        } else {
            Write-Host "VM ready at $ip. Proceeding to battlegroup commands..." -ForegroundColor Green
        }
        continue
    }

    if ($cmd -eq "open-file-browser") {
        Start-Process "http://${ip}:18888/"
        continue
    }

    if ($cmd -eq "open-director") {
        if (-not $directorPort) {
            $directorNodePort = ssh -o StrictHostKeyChecking=no -o LogLevel=QUIET -i "$bundledKey" "dune@$ip" `
                "sudo kubectl get svc -A -o jsonpath='{.items[*].spec.ports[?(@.port==11717)].nodePort}' 2>&1"
            if ($directorNodePort -match '^\d+$') {
                $directorPort = $directorNodePort.Trim()
                if ($null -ne $_onDirectorPortDetected) {
                    & $_onDirectorPortDetected $ip $directorPort
                }
            }
        }
        if (-not $directorPort) {
            Write-Warning "Could not determine Director port. Is the battlegroup running?"
            continue
        }
        Start-Process "http://${ip}:${directorPort}/"
        continue
    }

    if ($cmd -eq "shell-vm") {
        Write-Host "Opening shell in the VM. You can exit by typing 'exit'" -ForegroundColor Cyan
        ssh -t -o StrictHostKeyChecking=no -o LogLevel=QUIET -i "$bundledKey" "dune@$ip"
        continue
    }

    if ($cmd -eq "edit-battlegroup") {
        $bgPrefix = "funcom-seabass-"
        $nsList = ssh -o StrictHostKeyChecking=no -o LogLevel=QUIET -i "$bundledKey" "dune@$ip" "sudo kubectl get ns --no-headers -o custom-columns=NAME:.metadata.name | grep '^$bgPrefix'"
        $namespaces = @($nsList -split "`n" | ForEach-Object { $_.Trim() } | Where-Object { $_ })
        if ($namespaces.Count -eq 0) {
            Write-Warning "No battlegroup found."
            continue
        }
        if ($namespaces.Count -eq 1) {
            $ns = $namespaces[0]
        } else {
            Write-Host ""
            for ($i = 0; $i -lt $namespaces.Count; $i++) {
                Write-Host ("  {0,2}. {1}" -f ($i + 1), ($namespaces[$i] -replace "^$bgPrefix",''))
            }
            $ns = $null
            while ($null -eq $ns) {
                $sel = Read-Host "Select battlegroup (1-$($namespaces.Count))"
                if ($sel -match '^\d+$' -and [int]$sel -ge 1 -and [int]$sel -le $namespaces.Count) {
                    $ns = $namespaces[[int]$sel - 1]
                } else {
                    Write-Warning "Invalid selection."
                }
            }
        }

        $bgName = $ns -replace "^$bgPrefix",''

        $fields = @(
            [pscustomobject]@{ Name = "Region"; Key = "Region" }
        )
        Write-Host ""
        Write-Host "What do you want to edit?"
        for ($i = 0; $i -lt $fields.Count; $i++) {
            Write-Host ("  {0,2}. {1}" -f ($i + 1), $fields[$i].Name)
        }
        $field = $null
        while ($null -eq $field) {
            $sel = Read-Host "Select field (1-$($fields.Count))"
            if ($sel -match '^\d+$' -and [int]$sel -ge 1 -and [int]$sel -le $fields.Count) {
                $field = $fields[[int]$sel - 1].Key
            } else {
                Write-Warning "Invalid selection."
            }
        }

        if ($field -eq "Region") {
            $regions = @("Europe Test", "North America Test")
            Write-Host ""
            Write-Host "Choose new region:"
            for ($i = 0; $i -lt $regions.Count; $i++) {
                Write-Host ("  {0,2}. {1}" -f ($i + 1), $regions[$i])
            }
            $newRegion = $null
            while ($null -eq $newRegion) {
                $sel = Read-Host "Select region (1-$($regions.Count))"
                if ($sel -match '^\d+$' -and [int]$sel -ge 1 -and [int]$sel -le $regions.Count) {
                    $newRegion = $regions[[int]$sel - 1]
                } else {
                    Write-Warning "Invalid selection."
                }
            }

            Write-Host ""
            Write-Host "Updating FarmRegion to '$newRegion' on $ns/$bgName..." -ForegroundColor Cyan
            $remoteCmd = "sudo kubectl -n '$ns' get battlegroup '$bgName' -o yaml | sed -E 's|(- -FarmRegion=).*|\1$newRegion|; s|(dataCenter: ).*|\1$newRegion|; /name: BATTLEGROUP_REGION_NAME/{n;s|(value: ).*|\1$newRegion|;}' | sudo kubectl replace -f -"
            ssh -t -o StrictHostKeyChecking=no -o LogLevel=QUIET -i "$bundledKey" "dune@$ip" $remoteCmd
        }
        continue
    }

    if ($cmd -eq "shell-pod") {
        $bgPrefix = "funcom-seabass-"
        $nsList = ssh -o StrictHostKeyChecking=no -o LogLevel=QUIET -i "$bundledKey" "dune@$ip" "sudo kubectl get ns --no-headers -o custom-columns=NAME:.metadata.name | grep '^$bgPrefix'"
        $namespaces = @($nsList -split "`n" | ForEach-Object { $_.Trim() } | Where-Object { $_ })
        if ($namespaces.Count -eq 0) {
            Write-Warning "No battlegroup found."
            continue
        }
        if ($namespaces.Count -eq 1) {
            $ns = $namespaces[0]
        } else {
            Write-Host ""
            for ($i = 0; $i -lt $namespaces.Count; $i++) {
                Write-Host ("  {0,2}. {1}" -f ($i + 1), ($namespaces[$i] -replace "^$bgPrefix",''))
            }
            $ns = $null
            while ($null -eq $ns) {
                $sel = Read-Host "Select battlegroup (1-$($namespaces.Count))"
                if ($sel -match '^\d+$' -and [int]$sel -ge 1 -and [int]$sel -le $namespaces.Count) {
                    $ns = $namespaces[[int]$sel - 1]
                } else {
                    Write-Warning "Invalid selection."
                }
            }
        }

        $podList = ssh -o StrictHostKeyChecking=no -o LogLevel=QUIET -i "$bundledKey" "dune@$ip" "sudo kubectl get pods -n '$ns' --no-headers -o custom-columns=NAME:.metadata.name,ROLE:.metadata.labels.role"
        $pods = @($podList -split "`n" | ForEach-Object { $_.Trim() } | Where-Object { $_ } | ForEach-Object {
            $parts = $_ -split '\s+', 2
            [pscustomobject]@{
                Name    = $parts[0]
                Role    = if ($parts.Count -gt 1 -and $parts[1] -ne '<none>') { $parts[1] } else { '' }
                Display = $parts[0] -replace "^$($ns -replace '^funcom-seabass-','')-",''
            }
        })
        if ($pods.Count -eq 0) {
            Write-Warning "No pods found in namespace '$ns'."
            continue
        }
        Write-Host ""
        Write-Host "Pods in ${ns}:"
        $maxLen = ($pods | ForEach-Object { $_.Display.Length } | Measure-Object -Maximum).Maximum
        for ($i = 0; $i -lt $pods.Count; $i++) {
            Write-Host ("  {0,2}. {1,-$maxLen}  {2}" -f ($i + 1), $pods[$i].Display, $pods[$i].Role)
        }
        $pod = $null
        while ($null -eq $pod) {
            $sel = Read-Host "Select pod (1-$($pods.Count))"
            if ($sel -match '^\d+$' -and [int]$sel -ge 1 -and [int]$sel -le $pods.Count) {
                $pod = $pods[[int]$sel - 1].Name
            } else {
                Write-Warning "Invalid selection."
            }
        }

        Write-Host "Opening shell in $pod. You can exit by typing 'exit'" -ForegroundColor Cyan
        ssh -t -o StrictHostKeyChecking=no -o LogLevel=QUIET -i "$bundledKey" "dune@$ip" "sudo kubectl exec -it '$pod' -n '$ns' -- /bin/bash || sudo kubectl exec -it '$pod' -n '$ns' -- /bin/sh"
        continue
    }

    if ($cmd -eq "stop-vm") {
        Write-Host ""
        Write-Host "Stopping VM '$vmName'..." -ForegroundColor Cyan
        Stop-VM -Name $vmName -Force | Out-Null
        $ip = $null
        Write-Host "VM stopped." -ForegroundColor Green
        continue
    }

    if ($cmd -eq "logs-export") {
        ssh -t -o StrictHostKeyChecking=no -i "$bundledKey" "dune@$ip" "/home/dune/.dune/bin/battlegroup logs-export"

        $timestamp = Get-Date -Format "yyyy-MM-dd_HH-mm-ss"
        $localDir = Join-Path $env:USERPROFILE "Documents\BattlegroupLogs\Battlegroup_$timestamp"
        New-Item -ItemType Directory -Path $localDir -Force | Out-Null
        Write-Host ""
        Write-Host "Downloading log files..." -ForegroundColor Cyan
        $tarPath = Join-Path $env:TEMP "dune-bg-logs.tar.gz"
        $proc = Start-Process -FilePath "ssh" -ArgumentList @(
            "-o", "StrictHostKeyChecking=no",
            "-o", "LogLevel=QUIET",
            "-i", "`"$bundledKey`"",
            "dune@$ip",
            "tar -czf - -C /tmp/dune-bg-logs ."
        ) -RedirectStandardOutput $tarPath -NoNewWindow -Wait -PassThru
        if ($proc.ExitCode -ne 0) {
            Write-Host "Error: Failed to download log files." -ForegroundColor Red
            Remove-Item $tarPath -ErrorAction SilentlyContinue
            continue
        }
        tar -xzf $tarPath -C $localDir
        Remove-Item $tarPath
        Write-Host "Logs saved to: $localDir" -ForegroundColor Green
    } elseif ($cmd -eq "operator-logs-export") {
        ssh -t -o StrictHostKeyChecking=no -i "$bundledKey" "dune@$ip" "/home/dune/.dune/bin/battlegroup operator-logs-export"

        $timestamp = Get-Date -Format "yyyy-MM-dd_HH-mm-ss"
        $localDir = Join-Path $env:USERPROFILE "Documents\OperatorLogs\Operators_$timestamp"
        New-Item -ItemType Directory -Path $localDir -Force | Out-Null
        Write-Host ""
        Write-Host "Downloading operator log files..." -ForegroundColor Cyan
        $tarPath = Join-Path $env:TEMP "dune-operator-logs.tar.gz"
        $proc = Start-Process -FilePath "ssh" -ArgumentList @(
            "-o", "StrictHostKeyChecking=no",
            "-o", "LogLevel=QUIET",
            "-i", "`"$bundledKey`"",
            "dune@$ip",
            "tar -czf - -C /tmp/dune-operator-logs ."
        ) -RedirectStandardOutput $tarPath -NoNewWindow -Wait -PassThru
        if ($proc.ExitCode -ne 0) {
            Write-Host "Error: Failed to download operator log files." -ForegroundColor Red
            Remove-Item $tarPath -ErrorAction SilentlyContinue
            continue
        }
        tar -xzf $tarPath -C $localDir
        Remove-Item $tarPath
        Write-Host "Operator logs saved to: $localDir" -ForegroundColor Green
    } else {
        ssh -t -o StrictHostKeyChecking=no -o LogLevel=QUIET -i "$bundledKey" "dune@$ip" "/home/dune/.dune/bin/battlegroup $cmd"
    }

    if ($cmd -eq "start" -or $cmd -eq "restart") {
        $resolvedDirectorPort = $null
        $elapsed = 0
        $timeout = 60
        while (-not $resolvedDirectorPort -and $elapsed -lt $timeout)
        {
            $directorNodePort = ssh -o StrictHostKeyChecking=no -o LogLevel=QUIET -i "$bundledKey" "dune@$ip" `
                "sudo kubectl get svc -A -o jsonpath='{.items[*].spec.ports[?(@.port==11717)].nodePort}' 2>&1"
            if ($directorNodePort -match '^\d+$')
            {
                $resolvedDirectorPort = $directorNodePort.Trim()
            }
            if (-not $resolvedDirectorPort)
            {
                Start-Sleep -Seconds 5
                $elapsed += 5
            }
        }
        if (!$resolvedDirectorPort)
        {
            Write-Warning "Could not determine Director port from battlegroup after $timeout seconds."
        }
        else {
            $firstDetection = -not $directorPort
            $directorPort = $resolvedDirectorPort
            if ($firstDetection -and $null -ne $_onDirectorPortDetected) {
                & $_onDirectorPortDetected $ip $directorPort
            }
        }
    }

    if ($null -ne $_onBattlegroupStart -and ($cmd -eq "start" -or $cmd -eq "restart")) {
        & $_onBattlegroupStart $ip
    }
}
