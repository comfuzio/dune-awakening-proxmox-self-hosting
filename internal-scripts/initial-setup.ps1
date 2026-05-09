#Requires -RunAsAdministrator

# Logging Section
$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$logFile = "$scriptDir\..\.logs\initial-setup-$(Get-Date -Format 'yyyy-MM-dd_HH-mm-ss').log"
New-Item -ItemType Directory -Force -Path (Split-Path $logFile) | Out-Null

# Hyper-V module check
if (-not (Get-Module -ListAvailable -Name Hyper-V)) {
    Write-Error "The Hyper-V PowerShell module is not installed or enabled. This script requires Hyper-V to manage the virtual machine server."
    Write-Host "`nPlease ensure Hyper-V is enabled on your system:" -ForegroundColor Yellow
    exit 1
}

# Hyper-V service check
if ((Get-Service -Name vmms -ErrorAction SilentlyContinue).Status -ne 'Running') {
    Write-Error "The Hyper-V Virtual Machine Management service (vmms) is not running. It may be disabled or not installed."
    Write-Host "`nPlease check your Hyper-V installation and ensure the 'Hyper-V Virtual Machine Management' service is started." -ForegroundColor Yellow
    exit 1
}

Start-Transcript -Path $logFile -Append | Out-Null

# Start

$vmcx = Get-Item "$scriptDir\..\Virtual Machines\*.vmcx" -ErrorAction SilentlyContinue | Select-Object -First 1

if (-not $vmcx) 
{
    Write-Error "No .vmcx file found in '$scriptDir\..\Virtual Machines\'"
    exit 1
}

# Drive selection
$availableDrives = Get-PSDrive -PSProvider FileSystem | Where-Object { $_.Free -gt 100GB }

if ($availableDrives.Count -eq 0)
{
    Write-Error "No drives with enough free space (>100GB) detected. Installation cannot proceed."
    exit 1
}

$selectedDrive = $null

if ($availableDrives.Count -gt 1)
{
    Write-Host "Multiple drives with enough free space (>100GB) detected." -ForegroundColor Cyan
    Write-Host "Select a drive to install the VM:"
    
    $driveList = @()
    for ($i = 0; $i -lt $availableDrives.Count; $i++)
    {
        $drive = $availableDrives[$i]
        $freeGB = [math]::Round($drive.Free / 1GB, 2)
        Write-Host ("  {0}. {1} ({2} GB free)" -f ($i + 1), $drive.Name, $freeGB)
        $driveList += $drive.Name
    }

    $driveChoice = Read-Host "Select drive (1-$($availableDrives.Count))"
    if ($driveChoice -match '^\d+$' -and [int]$driveChoice -ge 1 -and [int]$driveChoice -le $availableDrives.Count)
    {
        $selectedDrive = $driveList[[int]$driveChoice - 1] + ":"
    }
    else
    {
        Write-Error "Invalid or no selection made. Installation aborted."
        exit 1
    }
}
else
{
    $selectedDrive = $availableDrives[0].Name + ":"
    Write-Host "Using drive $selectedDrive for installation." -ForegroundColor Cyan
}

$dest = "$selectedDrive\DuneAwakeningServer"

$existingVm = Get-VM -Name 'dune-awakening' -ErrorAction SilentlyContinue

if ($existingVm) 
{
    Write-Host "A VM named 'dune-awakening' already exists on this machine at: $($existingVm.ConfigurationLocation)" -ForegroundColor Yellow
    Write-Host "***************************************************" -ForegroundColor Red
    Write-Host "! WARNING: This will delete the existing VM files !" -ForegroundColor Red
    Write-Host "***************************************************" -ForegroundColor Red
    $answer = Read-Host "Do you want to remove it and continue? [Y/N]"

    if ($answer -ne 'Y') 
    {
        Write-Host "Skipping setup. Proceeding to connectivity check..."
        $skipImport = $true
    }
    else 
    {
        if ($existingVm.State -eq 'Running') 
        {
            Write-Warning "The VM 'dune-awakening' is currently running."
            $stopAnswer = Read-Host "Turn off the VM now? [Y/N]"
            if ($stopAnswer -ne 'Y') 
            {
                Write-Host "Exiting without changes."
                exit 1
            }
            Stop-VM -Name 'dune-awakening' -TurnOff -Force -ErrorAction Stop
            Write-Host "VM turned off." -ForegroundColor Cyan
        }

        Write-Host "Removing existing VM..."
        Remove-VM -Name 'dune-awakening' -Force -ErrorAction Stop
        Write-Host "VM removed." -ForegroundColor Cyan

        if (Test-Path $dest)
        {
            Write-Host "Clearing destination folder..."
            Get-ChildItem $dest -Recurse -Force | Sort-Object FullName -Descending | ForEach-Object {
                Remove-Item $_.FullName -Force -ErrorAction SilentlyContinue
                if (Test-Path $_.FullName) {
                    Write-Warning "Could not remove: $($_.FullName) (file may still be in use)"
                }
            }
            Remove-Item $dest -Force -ErrorAction SilentlyContinue
            if (Test-Path $dest) {
                Write-Warning "Destination folder could not be fully cleared. Some files may still be in use."
            } else {
                Write-Host "Destination folder cleared." -ForegroundColor Cyan
            }
        }

    }
}


if (-not $skipImport) 
{
    if (Test-Path $dest)
    {
        Write-Host "Destination folder already exists, clearing leftover files before import..."
        Get-ChildItem $dest -Recurse -Force | Sort-Object FullName -Descending | ForEach-Object {
            Remove-Item $_.FullName -Force -ErrorAction SilentlyContinue
        }
        Remove-Item $dest -Force -ErrorAction SilentlyContinue
        if (Test-Path $dest) {
            Write-Warning "Could not fully clear destination folder. Some files may still be in use."
        } else {
            Write-Host "Destination folder cleared." -ForegroundColor Cyan
        }
    }

    Write-Host "Checking VM compatibility..."
    $compatibility = Compare-VM -Path $vmcx.FullName -Copy -VirtualMachinePath $dest -VhdDestinationPath "$dest\Virtual Hard Disks" -ErrorAction Stop

    if ($compatibility.Incompatibilities.Count -gt 0) 
    {
        Write-Warning "This machine may not be fully compatible with the VM:"
        foreach ($issue in $compatibility.Incompatibilities) 
        {
            Write-Warning "  - $($issue.Message)"
        }
        $answer = Read-Host "Incompatibilities detected. Continue anyway? [Y/N]"
        if ($answer -ne 'Y') 
        {
            Write-Host "Exiting without changes."
            exit 1
        }
    } 
    else 
    {
        Write-Host "VM is compatible with this machine." -ForegroundColor Cyan
    }

    Write-Host "Installing Dune Awakening Server to: $dest"

    Import-VM -CompatibilityReport $compatibility -ErrorAction Stop | Out-Null

    # Find the switch to use with the VM
    $physicalNics = @(Get-NetAdapter | Where-Object { $_.Status -eq 'Up' -and $_.InterfaceDescription -notmatch 'Hyper-V|Virtual' })

    if ($physicalNics.Count -eq 0)
    {
        Write-Error "No active physical network adapters found, a network adapter is required to run a server"
        exit 1
    }

    $existingSwitches = @(Get-VMSwitch -ErrorAction SilentlyContinue)

    if ($existingSwitches.Count -gt 0 -and $physicalNics.Count -eq 1)
    {
        $selectedNic = $physicalNics[0]
        $boundSwitch = @(Get-VMSwitch -SwitchType External | Where-Object { $_.NetAdapterInterfaceDescription -eq $selectedNic.InterfaceDescription })
        if ($boundSwitch)
        {
            $switchName = $boundSwitch.Name
        }
    }

    # No switch found yet — need to ask and potentially create one
    if ([string]::IsNullOrEmpty($switchName))
    {
        Write-Host "Creating external switch for VM networking..." -ForegroundColor Cyan
        $switchName = 'DuneAwakeningServerSwitch'

        if ($physicalNics.Count -eq 1)
        {
            $selectedNic = $physicalNics[0]
        }
        else
        {
            $physicalNics = @($physicalNics | Sort-Object { if ($_.Name -match 'ethernet') { 0 } else { 1 } })

            Write-Host "VM is using bridge mode and needs a physical network adapter to bind to. This might cause you to briefly lose connection to the internet"
            Write-Host "Multiple network adapters detected. Select one to use for the VM's external switch"
            Write-Host "(If you're unsure, select the first option):"
            for ($i = 0; $i -lt $physicalNics.Count; $i++)
            {
                Write-Host ("  {0}. {1} ({2})" -f ($i + 1), $physicalNics[$i].Name, $physicalNics[$i].InterfaceDescription)
            }
            
            $nicChoice = $null
            while ($null -eq $nicChoice)
            {
                $sel = Read-Host "Select adapter (1-$($physicalNics.Count))"
                if ($sel -match '^\d+$' -and [int]$sel -ge 1 -and [int]$sel -le $physicalNics.Count)
                {
                    $nicChoice = [int]$sel
                }
                else
                {
                    Write-Warning "Invalid selection."
                }
            }
            $selectedNic = $physicalNics[$nicChoice - 1]
        }

        $boundSwitch = @(Get-VMSwitch -SwitchType External | Where-Object { $_.NetAdapterInterfaceDescription -eq $selectedNic.InterfaceDescription })
        if ($boundSwitch)
        {
            $switchName = $boundSwitch.Name
        }
        else
        {
            New-VMSwitch -Name $switchName -NetAdapterName $selectedNic.Name -AllowManagementOS $true -ErrorAction Stop
            Write-Host "External switch '$switchName' created." -ForegroundColor Cyan
        }
    }

    Connect-VMNetworkAdapter -VMName 'dune-awakening' -SwitchName $switchName -ErrorAction Stop
    Write-Host "VM network adapter connected to '$switchName'." -ForegroundColor Cyan

    $vhdx = Get-Item "$dest\Virtual Hard Disks\*.vhdx" -ErrorAction SilentlyContinue | Select-Object -First 1
    if ($vhdx) 
    {
        Resize-VHD -Path $vhdx.FullName -SizeBytes 100GB -ErrorAction Stop
        Write-Host "Virtual disk initialized" -ForegroundColor Cyan
    } 
    else 
    {
        Write-Warning "No .vhdx file found in $dest\Virtual Hard Disks. Skipping disk resize"
    }

    $vhdxBoot = Get-VMHardDiskDrive -VMName 'dune-awakening' | Select-Object -First 1
    if ($vhdxBoot)
    {
        Set-VMFirmware -VMName 'dune-awakening' -FirstBootDevice $vhdxBoot
    }
    else
    {
        Write-Warning "Could not find a Drive boot entry to set as first boot device."
    }

    Write-Host "How much memory would you like to allocate to the VM?"
    Write-Host "  1) 20GB (Recomended for a Hagga Basin Sietch)"
    Write-Host "  2) 30GB (Recomended for a Hagga Basin Sietch + Story/Social maps)"
    Write-Host "  3) 40GB (Recomended for Hagga Basin + Story/Social maps + Deep Desert)"
    $memBytes = $null
    while ($null -eq $memBytes)
    {
        $memChoice = Read-Host "Enter choice [1/2/3]"
        $memBytes = switch ($memChoice) {
            '1' { 20GB }
            '2' { 30GB }
            '3' { 40GB }
            default { Write-Warning "Invalid choice"; $null }
        }
    }
    $memGB = $memBytes / 1GB
    Set-VMMemory -VMName 'dune-awakening' -StartupBytes $memBytes
    Write-Host "VM memory set to ${memGB}GB" -ForegroundColor Cyan

    Write-Host "Initial setup complete. Starting the VM..."
    Start-VM -Name 'dune-awakening' -ErrorAction Stop
    Write-Host "VM 'dune-awakening' finished importing" -ForegroundColor Cyan

}

# This is the test connectivity section
$ip = $null
$timeout = 120
$elapsed = 0
$dots = 0
while (-not $ip -and $elapsed -lt $timeout) 
{
    $dots = ($dots % 3) + 1
    Write-Host -NoNewline "`rWaiting for VM to acquire an IP address$('.' * $dots)   "
    Start-Sleep -Seconds 1
    $elapsed += 1
    $ip = (Get-VMNetworkAdapter -VMName 'dune-awakening').IPAddresses |
          Where-Object { $_ -match '^\d+\.\d+\.\d+\.\d+$' } |
          Select-Object -First 1
}
Write-Host ""

if (-not $ip) 
{
    Write-Warning "Could not determine VM IP after $timeout seconds. Check Hyper-V Manager or run: Get-VMNetworkAdapter -VMName 'dune-awakening'"
    exit 1
}

Write-Host "VM IP address: $ip" -ForegroundColor Cyan

# Copy the bundled key to a fixed temp location and lock that copy down for ssh.
# We don't lock the bundled file in place because OpenSSH's strict ACL leaves
# users unable to delete the repo file later without taking ownership.
# Fixed path means reruns overwrite the same file rather than accumulating.
$bundledKey = "$scriptDir\ssh\sshKey"
$tempKey = Join-Path $env:TEMP 'dune-awakening-server-sshKey'
if (Test-Path $tempKey)
{
    # Prior run left this file with /inheritance:r and only Read ACL, so we
    # cannot change attributes or overwrite it without first restoring access.
    # Take ownership (we are elevated) and reset the ACL to inherited defaults.
    takeown /f $tempKey 2>&1 | Out-Null
    icacls $tempKey /reset 2>&1 | Out-Null
    Remove-Item -Path $tempKey -Force -ErrorAction SilentlyContinue
}
Copy-Item -Path $bundledKey -Destination $tempKey -Force
icacls $tempKey /inheritance:r /grant:r "${env:USERNAME}:(R)" | Out-Null
$bundledKey = $tempKey

Write-Host ""
Write-Host "How do you want the VM to be assigned an IP?"
Write-Host "  1) Automatically by the router with DHCP (recommended)"
Write-Host "  2) I want to manually set the VM IP (static)"

$ipMode = $null
while ($null -eq $ipMode)
{
    $sel = Read-Host "Choice [1/2]"
    if ($sel -eq '1' -or $sel -eq '2') { $ipMode = $sel }
    else { Write-Warning "Invalid selection." }
}

if ($ipMode -eq '2')
{
    $hostGateway = $null
    try
    {
        $hostGateway = (Get-NetRoute -DestinationPrefix '0.0.0.0/0' -ErrorAction SilentlyContinue |
                        Sort-Object RouteMetric |
                        Select-Object -First 1).NextHop
    }
    catch
    {
        $hostGateway = $null
    }

    Write-Host ""
    Write-Host "Static IP configuration:"
    Write-Host "  1) Simple - just enter the IP (uses host's gateway, /24 subnet, 1.1.1.1 DNS)"
    Write-Host "  2) Advanced - specify CIDR, gateway and DNS too"

    $advancedMode = $null
    while ($null -eq $advancedMode)
    {
        $sel = Read-Host "Choice [1/2]"
        if ($sel -eq '1') { $advancedMode = $false }
        elseif ($sel -eq '2') { $advancedMode = $true }
        else { Write-Warning "Invalid selection." }
    }

    $iface = 'eth0'

    $staticIp = Read-Host "Enter the static IP for the VM [$ip]"
    if ([string]::IsNullOrWhiteSpace($staticIp)) { $staticIp = $ip }
    if ($staticIp -notmatch '^\d+\.\d+\.\d+\.\d+$')
    {
        Write-Error "Invalid IP address: $staticIp"
        exit 1
    }

    if ($advancedMode)
    {
        $staticCidr = Read-Host "Enter the CIDR suffix (e.g. /24) [/24]"
        if ([string]::IsNullOrWhiteSpace($staticCidr)) { $staticCidr = '/24' }
        if ($staticCidr -notmatch '^/\d+$')
        {
            Write-Error "Invalid CIDR suffix: $staticCidr"
            exit 1
        }

        $gwPrompt = if ($hostGateway) { "Enter the gateway IP [$hostGateway]" } else { "Enter the gateway IP" }
        $staticGw = Read-Host $gwPrompt
        if ([string]::IsNullOrWhiteSpace($staticGw)) { $staticGw = $hostGateway }
        if ($staticGw -notmatch '^\d+\.\d+\.\d+\.\d+$')
        {
            Write-Error "Invalid gateway IP: $staticGw"
            exit 1
        }

        $staticDns = Read-Host "Enter the DNS server [1.1.1.1]"
        if ([string]::IsNullOrWhiteSpace($staticDns)) { $staticDns = '1.1.1.1' }
    }
    else
    {
        if (-not $hostGateway)
        {
            Write-Error "Could not detect the host's default gateway. Re-run and choose advanced mode to enter it manually."
            exit 1
        }
        $staticCidr = '/24'
        $staticGw = $hostGateway
        $staticDns = '1.1.1.1'
        Write-Host "Using gateway $staticGw, subnet $staticCidr, DNS $staticDns" -ForegroundColor Cyan
    }

    $interfacesContent = "auto lo`niface lo inet loopback`n`nauto $iface`niface $iface inet static`n    address $staticIp$staticCidr`n    gateway $staticGw`n"
    $b64Interfaces = [Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes($interfacesContent))
    $b64Resolv = [Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes("nameserver $staticDns`n"))

    Write-Host "Applying static network configuration to the VM..." -ForegroundColor Cyan

    $applyScript = @"
#!/bin/sh
set -e
echo $b64Interfaces | base64 -d | sudo -n tee /etc/network/interfaces > /dev/null
echo $b64Resolv | base64 -d | sudo -n tee /etc/resolv.conf > /dev/null
echo APPLY_OK
nohup sudo -n sh -c 'sleep 2; rc-service networking restart' </dev/null >/dev/null 2>&1 &
"@
    $applyScript = $applyScript -replace "`r`n", "`n"
    $b64Apply = [Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes($applyScript))
    $applyCmd = "echo $b64Apply | base64 -d | sh"

    $applyRaw = & ssh -o StrictHostKeyChecking=no -o LogLevel=QUIET -i "$bundledKey" "dune@$ip" $applyCmd 2>&1
    $applyOut = ($applyRaw | Out-String)
    if ($LASTEXITCODE -ne 0 -or $applyOut -notmatch 'APPLY_OK')
    {
        Write-Host "ssh output:" -ForegroundColor Yellow
        Write-Host $applyOut
        Write-Error "Failed to write static network configuration to the VM. Most likely cause: the 'dune' user does not have passwordless sudo for tee/rc-service. Check /etc/sudoers."
        exit 1
    }

    Write-Host "Waiting for VM to come back on $staticIp..." -ForegroundColor Cyan
    Start-Sleep -Seconds 5
    $reachable = $false
    $waitElapsed = 0
    $waitTimeout = 90
    while (-not $reachable -and $waitElapsed -lt $waitTimeout)
    {
        & ssh -o StrictHostKeyChecking=no -o LogLevel=QUIET -o ConnectTimeout=3 -i "$bundledKey" "dune@$staticIp" "true" 2>$null | Out-Null
        if ($LASTEXITCODE -eq 0) { $reachable = $true; break }
        Start-Sleep -Seconds 2
        $waitElapsed += 2
    }

    if (-not $reachable)
    {
        Write-Error "VM did not become reachable on $staticIp within $waitTimeout seconds"
        exit 1
    }

    $ip = $staticIp
    Write-Host "VM is now using static IP: $ip" -ForegroundColor Cyan
}

Write-Host "Detecting public IP from the VM..." -ForegroundColor Cyan
$publicIP = $null
try
{
    $remoteCmd = "wget -qO- --timeout=5 'https://api.ipify.org' 2>/dev/null"
    $raw = & ssh -o StrictHostKeyChecking=no -o LogLevel=QUIET -i "$bundledKey" "dune@$ip" $remoteCmd 2>$null
    $out = ($raw | Out-String).Trim()
    if ($LASTEXITCODE -eq 0 -and -not [string]::IsNullOrWhiteSpace($out))
    {
        $publicIP = $out
    }
}
catch
{
    $publicIP = $null
}

if (-not $publicIP)
{
    Write-Warning "Could not retrieve public IP from the VM"
}

Write-Host "Select the IP that players will connect to (If you're unsure, select the first option):"
Write-Host ""
if ($publicIP)
{
    Write-Host "  1. $publicIP " -NoNewline
    Write-Host "[VM's public IP]" -ForegroundColor Cyan -NoNewline
    Write-Host " - requires port forwarding - players from outside your network will be able to connect"
}
Write-Host "  2. $ip " -NoNewline
Write-Host "[VM's private IP]" -ForegroundColor Cyan -NoNewline
Write-Host " - does not require port forwarding - only players within your network can connect"
Write-Host "  3. Enter manually"
Write-Host ""
$selectedIP = $null
while ($null -eq $selectedIP)
{
    $sel = Read-Host "Choice"
    if ($sel -eq '1')
    {
        if ($publicIP)
        {
            $selectedIP = $publicIP
        }
        else
        {
            Write-Warning "Public IP is unavailable. Choose another option."
        }
    }
    elseif ($sel -eq '2')
    {
        $selectedIP = $ip
    }
    elseif ($sel -eq '3')
    {
        $selectedIP = Read-Host "Enter IP"
    }
    else
    {
        Write-Warning "Invalid selection."
    }
}

Write-Host "Writing IP to VM settings..." -ForegroundColor Cyan
ssh -o StrictHostKeyChecking=no -o LogLevel=QUIET -i "$bundledKey" "dune@$ip" "printf '\n\n\n$selectedIP\n' > /home/dune/.dune/settings.conf"

if ($LASTEXITCODE -ne 0)
{
    Write-Error "Failed to write IP to VM settings (ssh exited with code $LASTEXITCODE). Check the output above for details."
    exit 1
}

Write-Host "Uploading bootstrap files to the VM..." -ForegroundColor Cyan

$bootstrapDir = "$scriptDir\bootstrap"
$bootstrapSetup = Join-Path $bootstrapDir 'setup'
if (-not (Test-Path $bootstrapSetup))
{
    Write-Error "Bootstrap file not found: $bootstrapSetup"
    exit 1
}

$setupText     = (Get-Content $bootstrapSetup -Raw) -replace "`r`n", "`n"
$b64Setup     = [Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes($setupText))

$uploadScript = @"
#!/bin/sh
set -e
echo $b64Setup | base64 -d | sudo -n tee /home/dune/.dune/bin/setup > /dev/null
sudo -n chmod +x /home/dune/.dune/bin/setup
echo UPLOAD_OK
"@
$uploadScript = $uploadScript -replace "`r`n", "`n"
$b64Upload = [Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes($uploadScript))
$uploadCmd = "echo $b64Upload | base64 -d | sh"

$uploadRaw = & ssh -o StrictHostKeyChecking=no -o LogLevel=QUIET -i "$bundledKey" "dune@$ip" $uploadCmd 2>&1
$uploadOut = ($uploadRaw | Out-String)
if ($LASTEXITCODE -ne 0 -or $uploadOut -notmatch 'UPLOAD_OK')
{
    Write-Host "ssh output:" -ForegroundColor Yellow
    Write-Host $uploadOut
    Write-Error "Failed to upload bootstrap files to the VM."
    exit 1
}

Write-Host "Running first time battlegroup setup..." -ForegroundColor Cyan
ssh -t -o StrictHostKeyChecking=no -o LogLevel=QUIET -i "$bundledKey" "dune@$ip" "/home/dune/.dune/bin/setup"

if ($LASTEXITCODE -ne 0)
{
    Write-Error "Initial setup failed (ssh exited with code $LASTEXITCODE). Check the output above for details."
    exit 1
}

Write-Host "Initial setup complete. You can now start the battlegroup by running Battlegroup.bat and selecting the Start option" -ForegroundColor Green
