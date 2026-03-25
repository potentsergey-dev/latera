@echo off
if exist "C:\Program Files (x86)\Windows Kits\10\App Certification Kit\appcert.exe" (
    echo WACK_FOUND=true
    "C:\Program Files (x86)\Windows Kits\10\App Certification Kit\appcert.exe" help > nul 2>&1
    echo WACK_AVAILABLE=true
) else (
    echo WACK_FOUND=false
)
