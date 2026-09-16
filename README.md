# New-PC Bootstrap Script 

An idempotent PowerShell script for setting up a fresh Windows machine: it
installs a defined list of applications via `winget`, applies Windows
settings/registry tweaks, and configures power and privacy defaults — all
driven by a JSON config file instead of hardcoded values.

## Why config-as-code

Everything the script *changes* lives in `config.json`. `Bootstrap-NewPC.ps1`
contains no app names, registry paths, or setting values — it only knows how
to read a config and apply it. That means:

- A new machine profile (work laptop vs. personal desktop) is a new JSON
  file, not a new script.
- Anyone can audit or change *what* gets installed/configured without
  touching PowerShell logic.
- The script is re-runnable: it checks current state before changing
  anything, so running it twice (or on a machine that's already partially
  set up) is safe.

## Files

| File | Purpose |
|---|---|
| `Bootstrap-NewPC.ps1` | The script. Reads a config file and applies it. |
| `config.json` | Default config: apps, registry tweaks, power settings, privacy tweaks. |

## Requirements

- Windows 10/11
- PowerShell 5.1+ (works in PowerShell 7 too)
- [`winget`](https://learn.microsoft.com/windows/package-manager/winget/) —
  ships with modern Windows; if missing, install "App Installer" from the
  Microsoft Store
- Administrator privileges (the script declares `#Requires -RunAsAdministrator`
  and will refuse to run without them, since registry and power changes need
  elevation)

## Usage

```powershell
# Unblock if downloaded from the internet (removes the "blocked" flag)
Unblock-File .\Bootstrap-NewPC.ps1

# Run with the default config.json in the same folder
.\Bootstrap-NewPC.ps1

# Preview every change without applying anything
.\Bootstrap-NewPC.ps1 -WhatIf

# Use a different config file (e.g. a per-machine profile)
.\Bootstrap-NewPC.ps1 -ConfigPath .\profiles\work-laptop.json
```

If script execution is disabled, run PowerShell as Administrator and either
run once with a bypass:

```powershell
powershell -ExecutionPolicy Bypass -File .\Bootstrap-NewPC.ps1
```

or set a policy that allows locally-authored scripts:

```powershell
Set-ExecutionPolicy -Scope CurrentUser RemoteSigned
```

A timestamped log file (`bootstrap-log-YYYYMMDD-HHMMSS.txt`) is written next
to the script on every run.

## Config file format

### `Applications`

An array of winget package IDs. Find a package's exact ID with:

```powershell
winget search "visual studio code"
```

```json
{ "Id": "Microsoft.VisualStudioCode", "Name": "Visual Studio Code" }
```

The script checks `winget list --id <id>` before installing, so already-
installed apps are skipped.

### `RegistryTweaks` and `PrivacyTweaks`

Both use the same shape and are processed by the same function — they're
split into two arrays purely for readability in the config file.

```json
{
  "Description": "Show known file extensions in Explorer",
  "Path": "HKCU:\\Software\\Microsoft\\Windows\\CurrentVersion\\Explorer\\Advanced",
  "Name": "HideFileExt",
  "Value": 0,
  "Type": "DWord"
}
```

- `Path` — full PowerShell registry path (`HKCU:\...` or `HKLM:\...`)
- `Type` — any value accepted by `New-ItemProperty -PropertyType`
  (`DWord`, `String`, `Binary`, etc.)

The script reads the current value first and only writes if it differs, so
a value already set to the target is left alone and reported as
"already set" rather than rewritten.

### `PowerSettings`

```json
{
  "PowerPlan": "High performance",
  "MonitorTimeoutACMinutes": 15,
  "MonitorTimeoutDCMinutes": 5,
  "SleepTimeoutACMinutes": 30,
  "SleepTimeoutDCMinutes": 15,
  "DisableHibernate": true
}
```

- `PowerPlan` must match a plan name visible in `powercfg /list` on the
  target machine (e.g. "Balanced", "High performance", "Power saver", or a
  custom plan name). If it isn't found, the script logs a warning and
  continues rather than failing the whole run.
- AC = plugged in, DC = on battery. Set a timeout to `0` to disable it.
- `powercfg` calls are naturally idempotent — setting the same timeout or
  active plan twice is harmless, so these don't need a separate
  before/after check.

## Adding your own settings

1. Open `config.json`.
2. Add an entry to the relevant array using the shapes above.
3. Run with `-WhatIf` first to confirm what would change.
4. Run for real.

No PowerShell knowledge is needed to customize a machine profile — only to
change what the script itself does.

## Notes and caveats

- Some Explorer/theme changes (file extensions, dark mode) apply immediately
  in the registry but aren't visually reflected until Explorer restarts or
  you sign out. The script tells you this at the end of a run.
- `AllowTelemetry = 1` in the default config maps to Windows' "Required
  diagnostic data" (the lowest level Windows allows on most editions, not
  "off"). Adjust per your organization's policy.
- Test against a VM or spare machine before pointing this at a production
  fleet, especially if you add your own registry tweaks.
- The script uses `SupportsShouldProcess`, so `-WhatIf` and `-Confirm` work
  out of the box for every registry, power, and app-install action.