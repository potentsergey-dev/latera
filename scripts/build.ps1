# Full Build Script for Windows
# Usage: .\scripts\build.ps1 [-Release] [-SkipCodegen] [-SkipRust] [-SkipFlutter]

param(
    [switch]$Release,
    [switch]$SkipCodegen,
    [switch]$SkipRust,
    [switch]$SkipFlutter
)

$ErrorActionPreference = "Stop"
$ProjectRoot = Split-Path -Parent $PSScriptRoot
$RustDir = Join-Path $ProjectRoot "rust"
$FlutterDir = Join-Path $ProjectRoot "flutter"

$BuildType = if ($Release) { "release" } else { "debug" }

Write-Host "=== Latera Full Build ===" -ForegroundColor Cyan
Write-Host "Build type: $BuildType" -ForegroundColor Gray
Write-Host "Project root: $ProjectRoot" -ForegroundColor Gray

# Step 1: Codegen
if (-not $SkipCodegen) {
    Write-Host "`n[1/3] Running FRB codegen..." -ForegroundColor Yellow
    & "$PSScriptRoot\codegen.ps1"
    if ($LASTEXITCODE -ne 0) {
        Write-Host "ERROR: Codegen failed!" -ForegroundColor Red
        exit 1
    }
} else {
    Write-Host "`n[1/3] Skipping codegen..." -ForegroundColor Gray
}

# Step 2: Build Rust
if (-not $SkipRust) {
    Write-Host "`n[2/3] Building Rust library..." -ForegroundColor Yellow
    Push-Location $RustDir
    
    $cargoArgs = @("build")
    if ($Release) {
        $cargoArgs += "--release"
    }
    
    & cargo $cargoArgs
    if ($LASTEXITCODE -ne 0) {
        Write-Host "ERROR: Rust build failed!" -ForegroundColor Red
        Pop-Location
        exit 1
    }
    Pop-Location
} else {
    Write-Host "`n[2/3] Skipping Rust build..." -ForegroundColor Gray
}

# Step 3: Build Flutter
if (-not $SkipFlutter) {
    Write-Host "`n[3/3] Building Flutter app..." -ForegroundColor Yellow
    Push-Location $FlutterDir
    
    $flutterArgs = @("build", "windows")
    if ($Release) {
        $flutterArgs += "--release"
    } else {
        $flutterArgs += "--debug"
    }
    
    & flutter $flutterArgs
    if ($LASTEXITCODE -ne 0) {
        Write-Host "ERROR: Flutter build failed!" -ForegroundColor Red
        Pop-Location
        exit 1
    }
    Pop-Location
} else {
    Write-Host "`n[3/3] Skipping Flutter build..." -ForegroundColor Gray
}

Write-Host "`n=== Build completed successfully! ===" -ForegroundColor Green

if (-not $SkipFlutter) {
    $OutputPath = Join-Path $FlutterDir "build\windows\x64\runner\$BuildType"
    Write-Host "Output: $OutputPath" -ForegroundColor Cyan
}
