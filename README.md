New-PC Bootstrap Script

A PowerShell script that sets up a fresh Windows machine from one JSON config file. It installs apps with winget, applies registry tweaks, and sets power and privacy defaults.

How it works
main.ps1 reads config.json and applies each section in order.
Each action checks the current state before changing anything. Installed apps are skipped and registry values that already match are left alone, so the script can be re-run safely.
The script has no hardcoded apps or settings. Everything it changes lives in config.json, so a new machine profile only needs a new JSON file.
Every run writes a timestamped log file next to the script.
Requirements
Windows 10 or 11
PowerShell 5.1+ (also works in PowerShell 7)
winget (install "App Installer" from the Microsoft Store if it's missing)
Administrator privileges
Usage
powershell
# Preview changes without applying anything
.\main.ps1 -WhatIf

# Run with the default config.json
.\main.ps1

# Run with a different config
.\main.ps1 -ConfigPath .\profiles\work-laptop.json

If script execution is blocked, run once with:

powershell
powershell -ExecutionPolicy Bypass -File .\main.ps1
Default apps

General and dev

Git: version control
Visual Studio Code: code editor
7-Zip: file archiver
Firefox: web browser
Notepad++: text editor
PowerToys: Windows utilities

IT tools

Sysinternals Suite: Process Explorer, Autoruns, etc.
Wireshark: packet capture
Everything: instant file search
WinDirStat: disk usage viewer
Rufus: bootable USB creator

Everyday

VLC: media player

Bitwarden: password manager

ShareX: screenshots and screen recording

Default settings


Explorer: shows file extensions and hidden files, opens to This PC

Theme: dark mode for apps

Search: Bing/web results disabled in Start

Power: High performance plan, custom screen and sleep timeouts, hibernate off

Privacy: advertising ID, Cortana, activity history, and tailored experiences disabled; diagnostic data set to Required

Successful run
<img width="1917" height="1079" alt="Screenshot 2026-09-26 125207" src="https://github.com/user-attachments/assets/5b2e8165-1618-4332-80dc-d681de0d0c9f" />

