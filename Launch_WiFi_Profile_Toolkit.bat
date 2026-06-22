@echo off
setlocal
cd /d "%~dp0"

:menu
set "CHOICE="
cls
echo ============================================================
echo   WI-FI PROFILE BACKUP RESTORE AND REPAIR TOOLKIT
echo ============================================================
echo   1. Diagnose Wi-Fi profiles and adapters
echo   2. Export profiles without plaintext keys
echo   3. Export profiles with plaintext keys
echo   4. Import profiles from a folder
echo   5. Repair WLAN service and DNS
echo   6. Restart a wireless adapter
echo   7. Delete one saved Wi-Fi profile
echo   0. Exit
echo ============================================================
set /p CHOICE=Select an option: 

if "%CHOICE%"=="1" goto diagnose
if "%CHOICE%"=="2" goto exportclean
if "%CHOICE%"=="3" goto exportsensitive
if "%CHOICE%"=="4" goto importprofiles
if "%CHOICE%"=="5" goto repair
if "%CHOICE%"=="6" goto adapter
if "%CHOICE%"=="7" goto deleteprofile
if "%CHOICE%"=="0" goto end
goto menu

:diagnose
powershell.exe -NoLogo -NoProfile -ExecutionPolicy Bypass -File "%~dp0Windows_WiFi_Profile_Backup_Restore_Toolkit.ps1" -Action Diagnose
goto complete

:exportclean
set "PROFILE="
set /p PROFILE=Profile name (leave blank for all profiles): 
if "%PROFILE%"=="" powershell.exe -NoLogo -NoProfile -ExecutionPolicy Bypass -File "%~dp0Windows_WiFi_Profile_Backup_Restore_Toolkit.ps1" -Action ExportProfiles
if not "%PROFILE%"=="" powershell.exe -NoLogo -NoProfile -ExecutionPolicy Bypass -File "%~dp0Windows_WiFi_Profile_Backup_Restore_Toolkit.ps1" -Action ExportProfiles -ProfileName "%PROFILE%"
goto complete

:exportsensitive
set "PROFILE="
set /p PROFILE=Profile name (leave blank for all profiles): 
if "%PROFILE%"=="" powershell.exe -NoLogo -NoProfile -ExecutionPolicy Bypass -File "%~dp0Windows_WiFi_Profile_Backup_Restore_Toolkit.ps1" -Action ExportProfilesWithKeys
if not "%PROFILE%"=="" powershell.exe -NoLogo -NoProfile -ExecutionPolicy Bypass -File "%~dp0Windows_WiFi_Profile_Backup_Restore_Toolkit.ps1" -Action ExportProfilesWithKeys -ProfileName "%PROFILE%"
goto complete

:importprofiles
set "IMPORTFOLDER="
set /p IMPORTFOLDER=Folder containing Wi-Fi XML profiles: 
powershell.exe -NoLogo -NoProfile -ExecutionPolicy Bypass -File "%~dp0Windows_WiFi_Profile_Backup_Restore_Toolkit.ps1" -Action ImportProfiles -ImportPath "%IMPORTFOLDER%"
goto complete

:repair
set "ADAPTER="
set /p ADAPTER=Wireless adapter name (leave blank to skip adapter restart): 
if "%ADAPTER%"=="" powershell.exe -NoLogo -NoProfile -ExecutionPolicy Bypass -File "%~dp0Windows_WiFi_Profile_Backup_Restore_Toolkit.ps1" -Action RepairAllSafe
if not "%ADAPTER%"=="" powershell.exe -NoLogo -NoProfile -ExecutionPolicy Bypass -File "%~dp0Windows_WiFi_Profile_Backup_Restore_Toolkit.ps1" -Action RepairAllSafe -AdapterName "%ADAPTER%"
goto complete

:adapter
set "ADAPTER="
set /p ADAPTER=Wireless adapter name: 
powershell.exe -NoLogo -NoProfile -ExecutionPolicy Bypass -File "%~dp0Windows_WiFi_Profile_Backup_Restore_Toolkit.ps1" -Action RestartAdapter -AdapterName "%ADAPTER%"
goto complete

:deleteprofile
set "PROFILE="
set /p PROFILE=Profile name to back up and delete: 
powershell.exe -NoLogo -NoProfile -ExecutionPolicy Bypass -File "%~dp0Windows_WiFi_Profile_Backup_Restore_Toolkit.ps1" -Action DeleteProfile -ProfileName "%PROFILE%"
goto complete

:complete
echo.
pause
goto menu

:end
endlocal
