# FRB Codegen Script for Windows
# Usage: .\scripts\codegen.ps1 [-Watch]

param(
    [switch]$Watch
)

$ErrorActionPreference = "Stop"
$ProjectRoot = Split-Path -Parent $PSScriptRoot
$RustDir = Join-Path $ProjectRoot "rust"
$FlutterDir = Join-Path $ProjectRoot "flutter"

Write-Host "=== Latera FRB Codegen ===" -ForegroundColor Cyan
Write-Host "Project root: $ProjectRoot" -ForegroundColor Gray

# Check if flutter_rust_bridge_codegen is installed
Write-Host "`nChecking flutter_rust_bridge_codegen..." -ForegroundColor Yellow
$cargoBin = cargo install --list 2>$null | Select-String "flutter_rust_bridge_codegen"
if (-not $cargoBin) {
    Write-Host "ERROR: flutter_rust_bridge_codegen not found!" -ForegroundColor Red
    Write-Host "Install with: cargo install flutter_rust_bridge_codegen" -ForegroundColor Yellow
    exit 1
}
Write-Host "Found: $cargoBin" -ForegroundColor Green

# Check if Flutter dependencies are installed
Write-Host "`nChecking Flutter dependencies..." -ForegroundColor Yellow
Push-Location $FlutterDir
if (-not (Test-Path "pubspec.lock")) {
    Write-Host "Running flutter pub get..." -ForegroundColor Yellow
    flutter pub get
    if ($LASTEXITCODE -ne 0) {
        Write-Host "ERROR: flutter pub get failed!" -ForegroundColor Red
        Pop-Location
        exit 1
    }
}
Pop-Location

# Run codegen
Write-Host "`nRunning FRB codegen..." -ForegroundColor Yellow

# NOTE: FRB codegen has a known issue on Windows with path canonicalization.
# The error "prefix not found" occurs due to Windows path prefix handling.
# Workaround: Run from rust directory with relative paths.
Push-Location $RustDir

$codegenArgs = @(
    "generate",
    "--rust-input", "crate::api",
    "--rust-root", ".",
    "--dart-output", "../flutter/lib/infrastructure/rust/generated",
    "--rust-output", "src/frb_generated.rs",
    "--no-add-mod-to-lib"
)

if ($Watch) {
    $codegenArgs += "--watch"
    Write-Host "Watch mode enabled - will regenerate on changes..." -ForegroundColor Cyan
}

& flutter_rust_bridge_codegen $codegenArgs

if ($LASTEXITCODE -ne 0) {
    Write-Host "`nERROR: Codegen failed!" -ForegroundColor Red
    Write-Host "NOTE: If you see 'prefix not found' error, this is a known FRB issue on Windows." -ForegroundColor Yellow
    Write-Host "Workarounds:" -ForegroundColor Yellow
    Write-Host "  1. Run from WSL2 (Windows Subsystem for Linux)" -ForegroundColor Gray
    Write-Host "  2. Use macOS/Linux for codegen" -ForegroundColor Gray
    Write-Host "  3. Manually edit generated files if only minor changes needed" -ForegroundColor Gray
    Pop-Location
    exit 1
}

Pop-Location

Write-Host "`n=== Codegen completed successfully! ===" -ForegroundColor Green
Write-Host "Generated files:" -ForegroundColor Cyan
Write-Host "  - Rust:  $RustDir\src\frb_generated.rs" -ForegroundColor Gray
Write-Host "  - Dart:  $FlutterDir\lib\infrastructure\rust\generated\" -ForegroundColor Gray
