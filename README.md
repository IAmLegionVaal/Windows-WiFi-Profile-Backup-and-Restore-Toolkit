# Windows Wi-Fi Profile Backup and Restore Toolkit

A secure PowerShell toolkit for Windows Wi-Fi profile inventory, backup, restoration and local WLAN repair, created by **Dewald Pretorius**.

## Files

- `Windows_WiFi_Profile_Backup_Restore_Toolkit.ps1` — diagnostics, export, import and WLAN repair actions.
- `Launch_WiFi_Profile_Toolkit.bat` — interactive technician menu.

## Actual backup, restore and repair actions

- Inventory saved WLAN profiles without revealing keys.
- Export one or all profiles without requesting plaintext keys.
- Export profiles with plaintext keys only through an explicit `SENSITIVE` confirmation.
- Restrict sensitive export folders to the current user and SYSTEM.
- Import selected Wi-Fi profile XML files.
- Restart WLAN AutoConfig.
- Restart a selected wireless adapter.
- Flush DNS.
- Back up and delete one corrupt saved profile.
- Run WLAN service and DNS repair as a combined workflow.

## Usage

Diagnose only:

```powershell
.\Windows_WiFi_Profile_Backup_Restore_Toolkit.ps1 -Action Diagnose
```

Export profiles without plaintext keys:

```powershell
.\Windows_WiFi_Profile_Backup_Restore_Toolkit.ps1 -Action ExportProfiles
```

Export a selected profile with its key:

```powershell
.\Windows_WiFi_Profile_Backup_Restore_Toolkit.ps1 `
  -Action ExportProfilesWithKeys -ProfileName "Example WiFi"
```

Import profiles:

```powershell
.\Windows_WiFi_Profile_Backup_Restore_Toolkit.ps1 `
  -Action ImportProfiles -ImportPath "C:\Secure\WiFiProfiles"
```

Repair WLAN service, DNS and an adapter:

```powershell
.\Windows_WiFi_Profile_Backup_Restore_Toolkit.ps1 `
  -Action RepairAllSafe -AdapterName "Wi-Fi"
```

## Sensitive-data protection

- Plaintext keys are never displayed in console output or diagnostic reports.
- Standard exports do not request `key=clear`.
- Key-containing exports require typing `SENSITIVE`.
- Sensitive folders receive restricted NTFS permissions.
- A warning file and sensitive manifest are created beside key-containing exports.
- Exported XML and ZIP files are excluded by `.gitignore`.
- No real Wi-Fi profile or password from the uploaded ZIP has been committed.

## Safety

- Diagnostics are the default.
- Import and WLAN service or adapter repair require administrator rights where needed.
- Repairs use explicit confirmation and support `-DryRun`.
- Deleting a profile requires typing `DELETE` and the profile is exported first.
- Restarting WLAN services or adapters can interrupt remote support sessions.
- Profile XML behaviour can vary between Windows builds and wireless security types.

## Validation status

The original Wi-Fi export and import workflows were tested successfully by the author on his own Windows machines. This repository preserves those working `netsh wlan` operations while adding sensitive-data controls, repair actions, backups, logs and verification. Results vary with Windows version, adapter drivers, WLAN service state, profile format and wireless security configuration.

## Output

Each run creates a timestamped desktop folder containing:

- `before.json` and `after.json`
- Saved-profile and WLAN-interface text reports
- Wireless-adapter CSV files
- Optional profile export folders
- Deleted-profile backups
- `toolkit.log`

## Exit codes

| Code | Meaning |
|---:|---|
| 0 | Completed successfully |
| 2 | Invalid target or missing profile files |
| 4 | Elevation required |
| 10 | User cancelled |
| 20 | Export, import, repair or verification failure |
