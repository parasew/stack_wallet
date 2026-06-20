# Stack Wallet Windows Host Bootstrap
# Run from an elevated PowerShell (aka as Administrator) in the project root:
#   Set-ExecutionPolicy -ExecutionPolicy Bypass -Scope Process -Force
#   .\scripts\install_windows_build_tools.ps1
# Reboot after completion.

$ErrorActionPreference = "Stop"

Write-Host "=== Stack Wallet Windows Host Bootstrap ===" -ForegroundColor Cyan

# --- 1. Developer Mode ---
Write-Host "[1/9] Enabling Developer Mode (symlink support)..." -ForegroundColor Yellow
try {
    $RegistryKeyPath = "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\AppModelUnlock"
    if (-not (Test-Path $RegistryKeyPath)) {
        New-Item -Path $RegistryKeyPath -Force | Out-Null
    }
    Set-ItemProperty -Path $RegistryKeyPath -Name "AllowDevelopmentWithoutDevLicense" -Value 1 -Type DWord
    Write-Host "  Developer Mode enabled." -ForegroundColor Green
} catch {
    Write-Host "  [WARN] Could not enable Developer Mode via registry. Enable manually via Settings > Developer." -ForegroundColor Yellow
}

# --- 2. WSL2 + Ubuntu 24.04 ---
# TODO @parasew: check for Ubuntu 26 compat later
Write-Host "[2/9] Installing WSL2 with Ubuntu 24.04..." -ForegroundColor Yellow
$wslInstalled = $false
try { $null = wsl --status 2>$null; $wslInstalled = $true } catch { }

if (-not $wslInstalled) {
    wsl --install -d Ubuntu-24.04 --no-launch
    Write-Host "  WSL2 + Ubuntu 24.04 installation started. A reboot is required after this script finishes." -ForegroundColor Green
} else {
    Write-Host "  WSL2 already installed." -ForegroundColor Green
    $distros = wsl -l -q | Where-Object { $_ -match "Ubuntu-24.04" }
    if (-not $distros) {
        Write-Host "  [WARN] Ubuntu 24.04 not found in WSL. Install with: wsl --install -d Ubuntu-24.04" -ForegroundColor Yellow
    }
}

# --- 3. Visual Studio 2022 Community version ---
Write-Host "[3/9] Installing Visual Studio 2022 Community + C++ workloads..." -ForegroundColor Yellow
$vsInstalled = Test-Path "C:\Program Files\Microsoft Visual Studio\2022\Community\VC\Auxiliary\Build\vcvars64.bat"
if (-not $vsInstalled) {
    Write-Host "  Installing VS 2022 Community (this may take 20-40 minutes)..." -ForegroundColor Yellow
    winget install Microsoft.VisualStudio.2022.Community `
        --override "--quiet --wait --add Microsoft.VisualStudio.Workload.NativeDesktop --add Microsoft.VisualStudio.Component.VC.Tools.x86.x64 --add Microsoft.VisualStudio.Component.Windows10SDK.20348 --add Microsoft.VisualStudio.Workload.NativeCross" `
        --accept-source-agreements --accept-package-agreements
    Write-Host "  Visual Studio 2022 installed." -ForegroundColor Green
} else {
    Write-Host "  Visual Studio 2022 already installed." -ForegroundColor Green
}

# --- 4. NuGet + CppWinRT ---
Write-Host "[4/9] Installing NuGet and CppWinRT 2.0.210806.1..." -ForegroundColor Yellow
winget install 9WZDNCRDMDM3 --accept-source-agreements --accept-package-agreements 2>$null
if ($LASTEXITCODE -ne 0) { Write-Host "  NuGet already installed or install skipped." -ForegroundColor Yellow }
winget install Microsoft.Windows.CppWinRT --version 2.0.210806.1 --accept-source-agreements --accept-package-agreements 2>$null
if ($LASTEXITCODE -ne 0) { Write-Host "  CppWinRT already installed or install skipped." -ForegroundColor Yellow }

# --- 5. Flutter ---
Write-Host "[5/9] Installing Flutter 3.38.5..." -ForegroundColor Yellow
$flutterInstalled = Get-Command flutter -ErrorAction SilentlyContinue
if (-not $flutterInstalled) {
    winget install Google.Flutter --accept-source-agreements --accept-package-agreements 2>$null
    if ($LASTEXITCODE -ne 0) {
        Write-Host "  [WARN] winget install failed. Install Flutter manually: https://docs.flutter.dev/get-started/install/windows" -ForegroundColor Yellow
    } else {
        Write-Host "  Flutter installed." -ForegroundColor Green
    }
} else {
    Write-Host "  Flutter already installed: $(flutter --version 2>$null | Select-Object -First 1)" -ForegroundColor Green
}

# --- 6. Rust (single toolchain: 1.85.1) ---
Write-Host "[6/9] Installing Rust 1.85.1 + MSVC target..." -ForegroundColor Yellow
$rustupInstalled = Get-Command rustup -ErrorAction SilentlyContinue
if (-not $rustupInstalled) {
    Write-Host "  Installing rustup-init..."
    Invoke-WebRequest -Uri "https://static.rust-lang.org/rustup/dist/x86_64-pc-windows-msvc/rustup-init.exe" -OutFile "$env:TEMP\rustup-init.exe"
    & "$env:TEMP\rustup-init.exe" -y --default-toolchain 1.85.1
    Remove-Item "$env:TEMP\rustup-init.exe"
    $env:PATH = "$env:USERPROFILE\.cargo\bin;$env:PATH"
    Write-Host "  Rust 1.85.1 installed." -ForegroundColor Green
} else {
    Write-Host "  Rustup found. Installing/ensuring 1.85.1 toolchain..."
    rustup toolchain install 1.85.1
    rustup default 1.85.1
    Write-Host "  Rust 1.85.1 set as default." -ForegroundColor Green
}

Write-Host "  Adding x86_64-pc-windows-msvc target..."
rustup target add x86_64-pc-windows-msvc --toolchain 1.85.1

# --- 7. Go ---
Write-Host "[7/9] Installing Go..." -ForegroundColor Yellow
$goInstalled = Get-Command go -ErrorAction SilentlyContinue
if (-not $goInstalled) {
    winget install GoLang.Go --accept-source-agreements --accept-package-agreements 2>$null
    if ($LASTEXITCODE -ne 0) {
        Write-Host "  [WARN] winget install failed. Install Go manually: https://go.dev/doc/install" -ForegroundColor Yellow
    } else {
        Write-Host "  Go installed." -ForegroundColor Green
    }
} else {
    Write-Host "  Go already installed: $(go version)" -ForegroundColor Green
}

# --- 8. CMake, Ninja ---
Write-Host "[8/9] Installing CMake and Ninja..." -ForegroundColor Yellow
winget install Kitware.CMake --accept-source-agreements --accept-package-agreements 2>$null
if ($LASTEXITCODE -ne 0) { Write-Host "  CMake already installed or install skipped." -ForegroundColor Yellow }
winget install NinjaBuild.Ninja --accept-source-agreements --accept-package-agreements 2>$null
if ($LASTEXITCODE -ne 0) { Write-Host "  Ninja already installed or install skipped." -ForegroundColor Yellow }

# --- 9. Meson ---
Write-Host "[9/9] Installing Meson..." -ForegroundColor Yellow
$mesonInstalled = Get-Command meson -ErrorAction SilentlyContinue
if (-not $mesonInstalled) {
    pip install meson
    Write-Host "  Meson installed." -ForegroundColor Green
} else {
    Write-Host "  Meson already installed." -ForegroundColor Green
}

# --- Verification ---
Write-Host "" -ForegroundColor Cyan
Write-Host "=== Verification ===" -ForegroundColor Cyan

$allOk = $true

Write-Host "  Developer Mode: $(if ((Get-ItemProperty "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\AppModelUnlock" -Name "AllowDevelopmentWithoutDevLicense" -ErrorAction SilentlyContinue).AllowDevelopmentWithoutDevLicense -eq 1) { "ON" } else { "CHECK" })"
Write-Host "  WSL2: $(try { wsl --version 2>$null; "OK" } catch { "NOT FOUND" })"

function Test-Tool {
    param([string]$name, [string]$cmd)
    $found = Get-Command $cmd -ErrorAction SilentlyContinue
    if ($found) {
        Write-Host "  $($name): OK" -ForegroundColor Green
    } else {
        Write-Host "  $($name): NOT FOUND (may need PATH refresh or reboot)" -ForegroundColor Red
        $script:allOk = $false
    }
}

Test-Tool "Flutter" "flutter"
Test-Tool "Dart" "dart"
Test-Tool "Rust" "rustc"
Test-Tool "Cargo" "cargo"
Test-Tool "Go" "go"
Test-Tool "CMake" "cmake"
Test-Tool "Ninja" "ninja"
Test-Tool "Meson" "meson"

if ($allOk) {
    Write-Host "`n=== All tools verified! REBOOT YOUR MACHINE before building. ===" -ForegroundColor Green
} else {
    Write-Host "`n=== Some tools missing. Run again after reboot, or install missing tools manually. ===" -ForegroundColor Yellow
}

Write-Host ""
Write-Host "After reboot, run the WSL setup from inside WSL:" -ForegroundColor Cyan
Write-Host "  wsl -d Ubuntu-24.04"
Write-Host "  cd /mnt/c/path/to/stack_wallet/scripts/windows"
Write-Host "  chmod +x setup_wsl.sh && ./setup_wsl.sh"
