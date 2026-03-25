@echo off
REM ===================================================
REM  WACK Test Script for Latera
REM  Builds release MSIX and runs Windows App Cert Kit
REM ===================================================

set PROJECT_ROOT=%~dp0..
set FLUTTER_DIR=%PROJECT_ROOT%\flutter
set MSIX_OUTPUT=%FLUTTER_DIR%\build\windows\x64\runner\Release\latera.msix
set WACK_EXE=C:\Program Files (x86)\Windows Kits\10\App Certification Kit\appcert.exe
set WACK_REPORT=%PROJECT_ROOT%\wack_report.xml

echo === Latera WACK Test ===

REM Check WACK
if not exist "%WACK_EXE%" (
    echo ERROR: Windows App Certification Kit not found.
    echo Install Windows SDK from https://developer.microsoft.com/windows/downloads/windows-sdk/
    exit /b 1
)

REM Check MSIX exists
if not exist "%MSIX_OUTPUT%" (
    echo ERROR: MSIX package not found at %MSIX_OUTPUT%
    echo Build the release MSIX first:
    echo   cd flutter ^&^& flutter build windows --release
    echo   flutter pub run msix:create
    exit /b 1
)

echo MSIX found: %MSIX_OUTPUT%
echo Running WACK test...
echo Report will be saved to: %WACK_REPORT%

"%WACK_EXE%" test -appxpackagepath "%MSIX_OUTPUT%" -reportoutputpath "%WACK_REPORT%"

if %ERRORLEVEL% EQU 0 (
    echo.
    echo === WACK TEST PASSED ===
) else (
    echo.
    echo === WACK TEST FAILED ===
    echo Check %WACK_REPORT% for details.
)

exit /b %ERRORLEVEL%
