#Requires -RunAsAdministrator
<#
.SYNOPSIS
    Idempotent new-PC bootstrap script: installs apps via winget, applies
    registry tweaks, and sets power/privacy defaults from a config file.

.DESCRIPTION
    Reads a JSON config file describing:
      - Applications to install (winget package IDs)
      - Registry tweaks to apply
      - Power plan/timeout settings
      - Privacy-related registry tweaks

    Every action checks current state first, so re-running the script is
    safe: already-installed apps are skipped, registry values already at
    the target are left alone, and only what's missing or different gets
    changed.

.PARAMETER ConfigPath
    Path to the JSON config file. Defaults to config.json next to this script.

.PARAMETER LogPath
    Path to the log file. Defaults to a timestamped file next to this script.

.EXAMPLE
    .\Bootstrap-NewPC.ps1
    Runs with the default config.json in the same folder.

.EXAMPLE
    .\Bootstrap-NewPC.ps1 -ConfigPath C:\Setup\work-laptop.json -WhatIf
    Previews every change that would be made using a custom config, without
    applying anything.
#>

[CmdletBinding(SupportsShouldProcess)]
param(
    [string]$ConfigPath = (Join-Path $PSScriptRoot 'config.json'),
    [string]$LogPath = (Join-Path $PSScriptRoot "bootstrap-log-$(Get-Date -Format 'yyyyMMdd-HHmmss').txt")
)

$ErrorActionPreference = 'Stop'

# ------------------------------------------------------------------------
# Logging
# ------------------------------------------------------------------------
function Write-Log {
    param(
        [Parameter(Mandatory)][string]$Message,
        [ValidateSet('INFO', 'SUCCESS', 'WARN', 'ERROR')][string]$Level = 'INFO'
    )
    $timestamp = Get-Date -Format 'yyyy-MM-dd HH:mm:ss'
    $line = "[$timestamp] [$Level] $Message"

    $color = switch ($Level) {
        'SUCCESS' { 'Green' }
        'WARN'    { 'Yellow' }
        'ERROR'   { 'Red' }
        default   { 'Gray' }
    }
    Write-Host $line -ForegroundColor $color
    Add-Content -Path $script:LogPath -Value $line
}


# Applications (winget)

function Test-AppInstalled {
    param([string]$Id)
    $output = winget list --id $Id -e --accept-source-agreements 2>&1 | Out-String
    return ($output -notmatch 'No installed package found')
}

function Install-Applications {
    param([array]$Apps)
    $results = [System.Collections.Generic.List[object]]::new()

    if (-not (Get-Command winget -ErrorAction SilentlyContinue)) {
        Write-Log 'winget not found. Install "App Installer" from the Microsoft Store and re-run.' 'ERROR'
        return $results
    }

    foreach ($app in $Apps) {
        $id = $app.Id
        $name = $app.Name

        if (Test-AppInstalled -Id $id) {
            Write-Log "Already installed: $name ($id)" 'INFO'
            $results.Add([pscustomobject]@{ Name = $name; Id = $id; Status = 'AlreadyInstalled' })
            continue
        }

        if ($PSCmdlet.ShouldProcess($name, 'Install via winget')) {
            try {
                Write-Log "Installing $name ($id)..." 'INFO'
                winget install --id $id -e --silent `
                    --accept-package-agreements --accept-source-agreements | Out-Null

                if ($LASTEXITCODE -eq 0) {
                    Write-Log "Installed: $name" 'SUCCESS'
                    $results.Add([pscustomobject]@{ Name = $name; Id = $id; Status = 'Installed' })
                }
                else {
                    Write-Log "winget exited $LASTEXITCODE installing $name" 'ERROR'
                    $results.Add([pscustomobject]@{ Name = $name; Id = $id; Status = 'Failed' })
                }
            }
            catch {
                Write-Log "Exception installing $name : $_" 'ERROR'
                $results.Add([pscustomobject]@{ Name = $name; Id = $id; Status = 'Failed' })
            }
        }
    }
    return $results
}


# Registry tweaks (shared by RegistryTweaks and PrivacyTweaks)

function Set-RegistryTweak {
    param([pscustomobject]$Tweak)

    $path = $Tweak.Path
    $name = $Tweak.Name
    $value = $Tweak.Value
    $type = $Tweak.Type
    $desc = $Tweak.Description

    if (-not (Test-Path $path)) {
        if ($PSCmdlet.ShouldProcess($path, 'Create registry key')) {
            New-Item -Path $path -Force | Out-Null
        }
    }

    $existing = Get-ItemProperty -Path $path -Name $name -ErrorAction SilentlyContinue
    $current = if ($existing) { $existing.$name } else { $null }

    if ($null -ne $current -and "$current" -eq "$value") {
        Write-Log "Already set: $desc" 'INFO'
        return [pscustomobject]@{ Description = $desc; Status = 'AlreadySet' }
    }

    if ($PSCmdlet.ShouldProcess("$path\$name", "Set to $value")) {
        try {
            New-ItemProperty -Path $path -Name $name -Value $value -PropertyType $type -Force | Out-Null
            Write-Log "Applied: $desc" 'SUCCESS'
            return [pscustomobject]@{ Description = $desc; Status = 'Applied' }
        }
        catch {
            Write-Log "Failed: $desc : $_" 'ERROR'
            return [pscustomobject]@{ Description = $desc; Status = 'Failed' }
        }
    }
}

function Set-RegistryTweaks {
    param([array]$Tweaks)
    $results = [System.Collections.Generic.List[object]]::new()
    foreach ($tweak in $Tweaks) {
        $results.Add((Set-RegistryTweak -Tweak $tweak))
    }
    return $results
}


# Power settings

function Set-PowerConfiguration {
    param([pscustomobject]$Settings)

    if ($Settings.PowerPlan) {
        $planLine = powercfg /list | Select-String -SimpleMatch $Settings.PowerPlan
        if ($planLine) {
            if ($planLine.ToString() -match '([0-9a-fA-F-]{36})') {
                $guid = $Matches[1]
                if ($PSCmdlet.ShouldProcess($Settings.PowerPlan, 'Set as active power plan')) {
                    powercfg /setactive $guid
                    Write-Log "Active power plan set to '$($Settings.PowerPlan)'" 'SUCCESS'
                }
            }
        }
        else {
            Write-Log "Power plan '$($Settings.PowerPlan)' not found on this system; skipping" 'WARN'
        }
    }

    if ($PSCmdlet.ShouldProcess('Screen and sleep timeouts', 'Configure')) {
        powercfg /change monitor-timeout-ac $Settings.MonitorTimeoutACMinutes
        powercfg /change monitor-timeout-dc $Settings.MonitorTimeoutDCMinutes
        powercfg /change standby-timeout-ac $Settings.SleepTimeoutACMinutes
        powercfg /change standby-timeout-dc $Settings.SleepTimeoutDCMinutes
        Write-Log 'Screen and sleep timeouts configured' 'SUCCESS'
    }

    if ($Settings.DisableHibernate -and $PSCmdlet.ShouldProcess('Hibernate', 'Disable')) {
        powercfg /hibernate off
        Write-Log 'Hibernate disabled' 'SUCCESS'
    }
}


# Main
# ------------------------------------------------------------------------
$script:LogPath = $LogPath
Write-Log "Bootstrap started. Config: $ConfigPath" 'INFO'

if (-not (Test-Path $ConfigPath)) {
    Write-Log "Config file not found at $ConfigPath" 'ERROR'
    exit 1
}

try {
    $config = Get-Content -Path $ConfigPath -Raw | ConvertFrom-Json
}
catch {
    Write-Log "Failed to parse config file: $_" 'ERROR'
    exit 1
}

$appResults = @()
$regResults = @()
$privacyResults = @()

if ($config.Applications) {
    Write-Log '--- Installing applications ---' 'INFO'
    $appResults = Install-Applications -Apps $config.Applications
}

if ($config.RegistryTweaks) {
    Write-Log '--- Applying registry tweaks ---' 'INFO'
    $regResults = Set-RegistryTweaks -Tweaks $config.RegistryTweaks
}

if ($config.PowerSettings) {
    Write-Log '--- Configuring power settings ---' 'INFO'
    Set-PowerConfiguration -Settings $config.PowerSettings
}

if ($config.PrivacyTweaks) {
    Write-Log '--- Applying privacy tweaks ---' 'INFO'
    $privacyResults = Set-RegistryTweaks -Tweaks $config.PrivacyTweaks
}


# Summary
# ------------------------------------------------------------------------
Write-Log '--- Summary ---' 'INFO'
Write-Log ("Apps: {0} installed, {1} already present, {2} failed" -f `
    ($appResults | Where-Object Status -eq 'Installed').Count,
    ($appResults | Where-Object Status -eq 'AlreadyInstalled').Count,
    ($appResults | Where-Object Status -eq 'Failed').Count) 'INFO'

Write-Log ("Registry tweaks: {0} applied, {1} already set, {2} failed" -f `
    ($regResults | Where-Object Status -eq 'Applied').Count,
    ($regResults | Where-Object Status -eq 'AlreadySet').Count,
    ($regResults | Where-Object Status -eq 'Failed').Count) 'INFO'

Write-Log ("Privacy tweaks: {0} applied, {1} already set, {2} failed" -f `
    ($privacyResults | Where-Object Status -eq 'Applied').Count,
    ($privacyResults | Where-Object Status -eq 'AlreadySet').Count,
    ($privacyResults | Where-Object Status -eq 'Failed').Count) 'INFO'

Write-Log "Bootstrap complete. Full log: $script:LogPath" 'SUCCESS'
Write-Log 'Some changes (theme, Explorer settings) may need a sign-out or Explorer restart to take visible effect.' 'INFO'