#requires -Version 5.1
<#
.SYNOPSIS
    Secure Windows Wi-Fi profile backup, restore and repair toolkit.
.DESCRIPTION
    Inventories saved WLAN profiles, exports profiles without plaintext keys by
    default, supports explicit sensitive exports with restricted ACLs, imports
    selected profile XML files, and repairs local WLAN service, DNS and adapter state.
.NOTES
    Created by Dewald Pretorius - L2 IT Support Engineer.
#>

[CmdletBinding(SupportsShouldProcess = $true, ConfirmImpact = 'High')]
param(
    [ValidateSet('Diagnose','ExportProfiles','ExportProfilesWithKeys','ImportProfiles','RepairAllSafe','RestartWlanService','RestartAdapter','FlushDns','DeleteProfile')]
    [string]$Action = 'Diagnose',
    [string]$ProfileName,
    [string]$AdapterName,
    [string]$ExportPath,
    [string]$ImportPath,
    [ValidateSet('Current','All')]
    [string]$ImportScope = 'Current',
    [string]$OutputPath,
    [switch]$DryRun,
    [switch]$Yes
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$ScriptVersion = '1.0.0'
$Stamp = Get-Date -Format 'yyyyMMdd_HHmmss'
$ExitCode = 0

if ([string]::IsNullOrWhiteSpace($OutputPath)) {
    $OutputPath = Join-Path ([Environment]::GetFolderPath('Desktop')) "WiFi_Profile_Toolkit_$Stamp"
}
New-Item -ItemType Directory -Path $OutputPath -Force | Out-Null
$BackupPath = Join-Path $OutputPath 'backup'
New-Item -ItemType Directory -Path $BackupPath -Force | Out-Null
$LogPath = Join-Path $OutputPath 'toolkit.log'

function Write-Log {
    param(
        [Parameter(Mandatory)][string]$Message,
        [ValidateSet('INFO','WARN','ERROR','SUCCESS','DRYRUN')][string]$Level = 'INFO'
    )
    $line = '{0} [{1}] {2}' -f (Get-Date -Format 'yyyy-MM-dd HH:mm:ss'), $Level, $Message
    Add-Content -LiteralPath $LogPath -Value $line -Encoding UTF8
    switch ($Level) {
        'WARN' { Write-Host $Message -ForegroundColor Yellow }
        'ERROR' { Write-Host $Message -ForegroundColor Red }
        'SUCCESS' { Write-Host $Message -ForegroundColor Green }
        'DRYRUN' { Write-Host "DRY RUN: $Message" -ForegroundColor Cyan }
        default { Write-Host $Message }
    }
}

function Test-IsAdministrator {
    $identity = [Security.Principal.WindowsIdentity]::GetCurrent()
    $principal = New-Object Security.Principal.WindowsPrincipal($identity)
    return $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

function Require-Administrator {
    if (-not (Test-IsAdministrator)) {
        throw 'This action requires an elevated PowerShell session.'
    }
}

function Confirm-Action {
    param(
        [Parameter(Mandatory)][string]$Message,
        [string]$Token = 'REPAIR'
    )
    if ($DryRun -or $Yes) { return $true }
    return (Read-Host "$Message Type $Token to continue") -eq $Token
}

function Protect-SensitiveDirectory {
    param([Parameter(Mandatory)][string]$Path)

    $currentSid = [Security.Principal.WindowsIdentity]::GetCurrent().User
    $systemSid = New-Object Security.Principal.SecurityIdentifier('S-1-5-18')
    $acl = New-Object Security.AccessControl.DirectorySecurity
    $acl.SetAccessRuleProtection($true, $false)

    $inheritance = [Security.AccessControl.InheritanceFlags]'ContainerInherit, ObjectInherit'
    $propagation = [Security.AccessControl.PropagationFlags]::None
    $allow = [Security.AccessControl.AccessControlType]::Allow

    $acl.AddAccessRule((New-Object Security.AccessControl.FileSystemAccessRule($currentSid, 'FullControl', $inheritance, $propagation, $allow)))
    $acl.AddAccessRule((New-Object Security.AccessControl.FileSystemAccessRule($systemSid, 'FullControl', $inheritance, $propagation, $allow)))
    Set-Acl -LiteralPath $Path -AclObject $acl
}

function Get-WlanProfileText {
    $text = & netsh.exe wlan show profiles 2>&1 | Out-String
    return $text
}

function Get-WlanInterfaceText {
    $text = & netsh.exe wlan show interfaces 2>&1 | Out-String
    return $text
}

function Get-WirelessAdapters {
    return @(
        Get-NetAdapter -Physical -ErrorAction SilentlyContinue |
            Where-Object { $_.InterfaceDescription -match 'Wireless|Wi-Fi|802\.11|WLAN' -or $_.Name -match 'Wi-Fi|Wireless|WLAN' } |
            Select-Object Name, InterfaceDescription, Status, LinkSpeed, MacAddress, ifIndex
    )
}

function Save-State {
    param([Parameter(Mandatory)][string]$Stage)

    $profileText = Get-WlanProfileText
    $interfaceText = Get-WlanInterfaceText
    $service = Get-Service -Name WlanSvc -ErrorAction SilentlyContinue
    $adapters = @(Get-WirelessAdapters)

    $profileText | Set-Content -LiteralPath (Join-Path $OutputPath "$Stage-saved-profiles.txt") -Encoding UTF8
    $interfaceText | Set-Content -LiteralPath (Join-Path $OutputPath "$Stage-wlan-interfaces.txt") -Encoding UTF8
    $adapters | Export-Csv -LiteralPath (Join-Path $OutputPath "$Stage-wireless-adapters.csv") -NoTypeInformation -Encoding UTF8

    $state = [ordered]@{
        Stage = $Stage
        Generated = (Get-Date).ToString('o')
        ScriptVersion = $ScriptVersion
        Computer = $env:COMPUTERNAME
        User = "$env:USERDOMAIN\$env:USERNAME"
        IsAdministrator = (Test-IsAdministrator)
        WlanService = if ($service) {
            [ordered]@{ Status = [string]$service.Status; StartType = [string]$service.StartType }
        } else { $null }
        WirelessAdapters = $adapters
        SavedProfilesTextFile = "$Stage-saved-profiles.txt"
        InterfaceTextFile = "$Stage-wlan-interfaces.txt"
    }

    $state | ConvertTo-Json -Depth 7 | Set-Content -LiteralPath (Join-Path $OutputPath "$Stage.json") -Encoding UTF8
    Write-Log "Saved $Stage Wi-Fi state." 'SUCCESS'
    return $state
}

function Resolve-ExportDirectory {
    param([switch]$Sensitive)

    if (-not [string]::IsNullOrWhiteSpace($ExportPath)) {
        $path = $ExportPath
    } else {
        $folder = if ($Sensitive) { 'Profiles-With-Plaintext-Keys' } else { 'Profiles-No-Plaintext-Keys' }
        $path = Join-Path $OutputPath $folder
    }

    New-Item -ItemType Directory -Path $path -Force | Out-Null
    if ($Sensitive) { Protect-SensitiveDirectory -Path $path }
    return (Resolve-Path -LiteralPath $path).Path
}

function Invoke-ExportProfiles {
    param([switch]$IncludeKeys)

    $token = if ($IncludeKeys) { 'SENSITIVE' } else { 'BACKUP' }
    $message = if ($IncludeKeys) {
        'Export Wi-Fi profiles with plaintext keys into a restricted folder? Never commit or share the exported XML files.'
    } else {
        'Export saved Wi-Fi profiles without requesting plaintext keys?'
    }
    if (-not (Confirm-Action -Message $message -Token $token)) { throw 'User cancelled.' }

    $destination = Resolve-ExportDirectory -Sensitive:$IncludeKeys
    if ($DryRun) {
        Write-Log "Would export Wi-Fi profiles to $destination. IncludeKeys=$IncludeKeys" 'DRYRUN'
        return
    }

    $arguments = @('wlan','export','profile')
    if (-not [string]::IsNullOrWhiteSpace($ProfileName)) {
        $arguments += "name=$ProfileName"
    }
    if ($IncludeKeys) { $arguments += 'key=clear' }
    $arguments += "folder=$destination"

    & netsh.exe @arguments 2>&1 | Add-Content -LiteralPath $LogPath
    if ($LASTEXITCODE -ne 0) { throw "Wi-Fi profile export returned exit code $LASTEXITCODE." }

    $xmlFiles = @(Get-ChildItem -LiteralPath $destination -Filter '*.xml' -File -ErrorAction SilentlyContinue)
    if ($xmlFiles.Count -eq 0) { throw 'No Wi-Fi profile XML files were exported.' }

    if ($IncludeKeys) {
        $manifest = foreach ($file in $xmlFiles) {
            $containsKey = Select-String -LiteralPath $file.FullName -Pattern '<keyMaterial>' -Quiet
            [pscustomobject]@{ FileName = $file.Name; ContainsPlaintextKey = [bool]$containsKey }
        }
        $manifest | Export-Csv -LiteralPath (Join-Path $destination 'SENSITIVE-MANIFEST.csv') -NoTypeInformation -Encoding UTF8
        Set-Content -LiteralPath (Join-Path $destination 'DO-NOT-COMMIT.txt') -Encoding UTF8 -Value 'This folder may contain plaintext Wi-Fi keys. Do not commit, email or publicly share these files.'
    }

    Write-Log "Exported $($xmlFiles.Count) Wi-Fi profile file(s) to $destination." 'SUCCESS'
}

function Invoke-ImportProfiles {
    Require-Administrator
    if ([string]::IsNullOrWhiteSpace($ImportPath)) { throw 'Specify -ImportPath containing Wi-Fi profile XML files.' }
    if (-not (Test-Path -LiteralPath $ImportPath -PathType Container)) { throw "Import folder '$ImportPath' was not found." }

    $xmlFiles = @(Get-ChildItem -LiteralPath $ImportPath -Filter '*.xml' -File -ErrorAction Stop)
    if ($xmlFiles.Count -eq 0) { throw 'No Wi-Fi profile XML files were found in the import folder.' }
    if (-not (Confirm-Action "Import $($xmlFiles.Count) Wi-Fi profile file(s) for scope $ImportScope?" -Token 'IMPORT')) { throw 'User cancelled.' }

    if ($DryRun) {
        foreach ($file in $xmlFiles) { Write-Log "Would import $($file.FullName)." 'DRYRUN' }
        return
    }

    $userValue = if ($ImportScope -eq 'All') { 'all' } else { 'current' }
    foreach ($file in $xmlFiles) {
        & netsh.exe wlan add profile "filename=$($file.FullName)" "user=$userValue" 2>&1 | Add-Content -LiteralPath $LogPath
        if ($LASTEXITCODE -ne 0) { throw "Import failed for $($file.Name) with exit code $LASTEXITCODE." }
        Write-Log "Imported Wi-Fi profile file $($file.Name)." 'SUCCESS'
    }
}

function Invoke-RestartWlanService {
    Require-Administrator
    if (-not (Confirm-Action 'Start or restart WLAN AutoConfig? Active Wi-Fi can disconnect briefly.')) { throw 'User cancelled.' }
    if ($DryRun) {
        Write-Log 'Would start or restart WLAN AutoConfig.' 'DRYRUN'
        return
    }

    $service = Get-Service -Name WlanSvc -ErrorAction Stop
    if ($service.Status -eq 'Running') {
        Restart-Service -Name WlanSvc -Force -ErrorAction Stop
    } else {
        Start-Service -Name WlanSvc -ErrorAction Stop
    }
    (Get-Service -Name WlanSvc).WaitForStatus('Running', [TimeSpan]::FromSeconds(30))
    Write-Log 'WLAN AutoConfig is running.' 'SUCCESS'
}

function Invoke-RestartAdapter {
    Require-Administrator
    if ([string]::IsNullOrWhiteSpace($AdapterName)) { throw 'Specify -AdapterName for adapter restart.' }
    $adapter = Get-NetAdapter -Name $AdapterName -ErrorAction SilentlyContinue
    if (-not $adapter) { throw "Adapter '$AdapterName' was not found." }
    if (-not (Confirm-Action "Restart wireless adapter '$AdapterName'? Connectivity will be interrupted.")) { throw 'User cancelled.' }

    if ($DryRun) {
        Write-Log "Would restart adapter '$AdapterName'." 'DRYRUN'
        return
    }

    Restart-NetAdapter -Name $AdapterName -Confirm:$false -ErrorAction Stop
    Start-Sleep -Seconds 4
    $after = Get-NetAdapter -Name $AdapterName -ErrorAction Stop
    if ($after.Status -eq 'Disabled') { throw "Adapter '$AdapterName' remained disabled." }
    Write-Log "Restarted adapter '$AdapterName'. Current status: $($after.Status)." 'SUCCESS'
}

function Invoke-FlushDns {
    if (-not (Confirm-Action 'Flush the Windows DNS resolver cache?' -Token 'YES')) { throw 'User cancelled.' }
    if ($DryRun) {
        Write-Log 'Would flush the DNS resolver cache.' 'DRYRUN'
        return
    }
    if (Get-Command Clear-DnsClientCache -ErrorAction SilentlyContinue) {
        Clear-DnsClientCache
    } else {
        & ipconfig.exe /flushdns | Out-Null
    }
    Write-Log 'DNS resolver cache flushed.' 'SUCCESS'
}

function Invoke-DeleteProfile {
    if ([string]::IsNullOrWhiteSpace($ProfileName)) { throw 'Specify -ProfileName for deletion.' }
    $backupFolder = Join-Path $BackupPath 'DeletedProfileBackup'
    New-Item -ItemType Directory -Path $backupFolder -Force | Out-Null

    if (-not (Confirm-Action "Back up and delete saved Wi-Fi profile '$ProfileName'?" -Token 'DELETE')) { throw 'User cancelled.' }
    if ($DryRun) {
        Write-Log "Would back up and delete Wi-Fi profile '$ProfileName'." 'DRYRUN'
        return
    }

    & netsh.exe wlan export profile "name=$ProfileName" "folder=$backupFolder" 2>&1 | Add-Content -LiteralPath $LogPath
    if ($LASTEXITCODE -ne 0) { throw "Could not back up profile '$ProfileName'. Deletion was not attempted." }
    & netsh.exe wlan delete profile "name=$ProfileName" 2>&1 | Add-Content -LiteralPath $LogPath
    if ($LASTEXITCODE -ne 0) { throw "Could not delete profile '$ProfileName'." }
    Write-Log "Backed up and deleted Wi-Fi profile '$ProfileName'." 'SUCCESS'
}

Write-Log "Wi-Fi Profile Backup Restore Toolkit $ScriptVersion started. Action=$Action DryRun=$DryRun"
$before = Save-State -Stage 'before'

try {
    switch ($Action) {
        'Diagnose' { }
        'ExportProfiles' { Invoke-ExportProfiles }
        'ExportProfilesWithKeys' { Invoke-ExportProfiles -IncludeKeys }
        'ImportProfiles' { Invoke-ImportProfiles }
        'RepairAllSafe' {
            Invoke-RestartWlanService
            Invoke-FlushDns
            if (-not [string]::IsNullOrWhiteSpace($AdapterName)) { Invoke-RestartAdapter }
        }
        'RestartWlanService' { Invoke-RestartWlanService }
        'RestartAdapter' { Invoke-RestartAdapter }
        'FlushDns' { Invoke-FlushDns }
        'DeleteProfile' { Invoke-DeleteProfile }
    }
} catch {
    if ($_.Exception.Message -eq 'User cancelled.') {
        $ExitCode = 10
        Write-Log 'Action cancelled by the user.' 'WARN'
    } elseif ($_.Exception.Message -match 'elevated') {
        $ExitCode = 4
        Write-Log $_.Exception.Message 'ERROR'
    } elseif ($_.Exception.Message -match 'Specify|not found|No Wi-Fi') {
        $ExitCode = 2
        Write-Log $_.Exception.Message 'ERROR'
    } else {
        $ExitCode = 20
        Write-Log $_.Exception.Message 'ERROR'
    }
} finally {
    try { [void](Save-State -Stage 'after') } catch { Write-Log "Post-action snapshot failed: $($_.Exception.Message)" 'WARN' }
}

if ($ExitCode -eq 0) {
    Write-Log "Completed successfully. Output: $OutputPath" 'SUCCESS'
} else {
    Write-Log "Completed with exit code $ExitCode. Output: $OutputPath" 'ERROR'
}
exit $ExitCode
