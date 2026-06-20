# Stack Wallet Windows Host Bootstrap
# Run from an elevated PowerShell (aka as Administrator) in the project root:
#   Set-ExecutionPolicy -ExecutionPolicy Bypass -Scope Process -Force
#   .\scripts\install_windows_build_tools.ps1
# Reboot after completion.

$ErrorActionPreference = "Stop"

function Refresh-Path {
    # Reload Machine + User PATH into current session so newly-installed tools are discoverable.
    $env:Path = [System.Environment]::GetEnvironmentVariable("Path", "Machine") + ";" + [System.Environment]::GetEnvironmentVariable("Path", "User")
}

Write-Host "=== Stack Wallet Windows Host Bootstrap ===" -ForegroundColor Cyan

function Show-NestedVirtualizationHelp {
    Write-Host ""
    Write-Host "  [ERROR] WSL2 cannot start because virtualization / nested virtualization is not enabled." -ForegroundColor Red
    Write-Host ""
    Write-Host "  If you are running Windows in a virtual machine (Parallels, VMware, VirtualBox, UTM, Hyper-V, etc.)," -ForegroundColor Yellow
    Write-Host "  you must enable NESTED VIRTUALIZATION in your hypervisor settings, then re-run this script:" -ForegroundColor Yellow
    Write-Host "    - UTM (Apple Silicon Mac): VM Settings > System > Use 'Apple Virtualization' engine (not QEMU)." -ForegroundColor Yellow
    Write-Host "      Apple Virtualization provides the nested virtualization WSL2 needs." -ForegroundColor Yellow
    Write-Host "    - Parallels Desktop: VM Configure > Hardware > CPU & Memory > Advanced > 'Nested Virtualization'" -ForegroundColor Yellow
    Write-Host "    - VMware Fusion: VM Settings > Processors & Memory > Advanced > 'Virtualize Intel VT-x/EPT or AMD-V/RVI'" -ForegroundColor Yellow
    Write-Host "    - VirtualBox: VM Settings > System > Acceleration > 'Nested VT-x/AMD-V'" -ForegroundColor Yellow
    Write-Host "    - Hyper-V host: Set-VMProcessor -VMName 'YourVM' -ExposeVirtualizationExtensions `$true" -ForegroundColor Yellow
    Write-Host ""
    Write-Host "  If this is physical hardware:" -ForegroundColor Yellow
    Write-Host "    1. Reboot into UEFI/BIOS and enable virtualization (Intel VT-x / AMD-V / SVM)." -ForegroundColor Yellow
    Write-Host "    2. In Windows run: dism.exe /online /enable-feature /featurename:VirtualMachinePlatform /all /norestart" -ForegroundColor Yellow
    Write-Host "    3. Reboot Windows and re-run this script." -ForegroundColor Yellow
}

function Enable-WslFeature {
    # Make sure the WSL2 kernel / Virtual Machine Platform feature is enabled.
    Write-Host "  Enabling WSL2 kernel features (Virtual Machine Platform, WSL)..." -ForegroundColor Yellow
    try {
        wsl --install --no-distribution 2>$null | Out-Null
    } catch { }
    $vmPlatform = Get-WindowsOptionalFeature -Online -FeatureName VirtualMachinePlatform -ErrorAction SilentlyContinue
    if ($vmPlatform -and $vmPlatform.State -ne "Enabled") {
        Enable-WindowsOptionalFeature -Online -FeatureName VirtualMachinePlatform -All -NoRestart | Out-Null
    }
    $wslFeature = Get-WindowsOptionalFeature -Online -FeatureName Microsoft-Windows-Subsystem-Linux -ErrorAction SilentlyContinue
    if ($wslFeature -and $wslFeature.State -ne "Enabled") {
        Enable-WindowsOptionalFeature -Online -FeatureName Microsoft-Windows-Subsystem-Linux -All -NoRestart | Out-Null
    }
}

function Test-Wsl2VmCanStart {
    # wsl --status may pass even when the VM platform cannot start a WSL2 VM.
    # Setting default version to 2 forces WSL2 to actually try using virtualization.
    $output = & wsl --set-default-version 2 2>&1
    $outputString = $output | Out-String
    if ($outputString -match "HCS_E_HYPERV_NOT_INSTALLED|virtualization.*not enabled|Virtual Machine Platform|Please enable the Virtual Machine Platform Windows feature") {
        return $false
    }
    return $true
}

# --- Preflight: verify WSL2 can actually start before spending time on large downloads ---
Write-Host "[Preflight] Verifying WSL2 / nested virtualization is functional..." -ForegroundColor Yellow
$wsl2Ok = Test-Wsl2VmCanStart
if (-not $wsl2Ok) {
    Enable-WslFeature
    $wsl2Ok = Test-Wsl2VmCanStart
}
if (-not $wsl2Ok) {
    Show-NestedVirtualizationHelp
    throw "WSL2 virtualization prerequisite missing."
}
Write-Host "  WSL2 virtualization is functional." -ForegroundColor Green

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

$distros = (wsl -l -q 2>$null) | Where-Object { $_ -match "Ubuntu-24.04" }
if ($distros) {
    Write-Host "  Ubuntu 24.04 already registered in WSL." -ForegroundColor Green
} else {
    Write-Host "  Installing Ubuntu 24.04 in WSL2..." -ForegroundColor Yellow
    $installOutput = wsl --install -d Ubuntu-24.04 --no-launch 2>&1
    if ($LASTEXITCODE -ne 0 -or $installOutput -match "HCS_E_HYPERV_NOT_INSTALLED|virtualization.*not enabled|Virtual Machine Platform") {
        Show-NestedVirtualizationHelp
        throw "WSL2 virtualization prerequisite missing."
    }
    Write-Host "  Ubuntu 24.04 installation started. A reboot is required after this script finishes." -ForegroundColor Green
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

# Ensure NuGet CLI is available (winget package may not place it on PATH immediately).
function Ensure-NuGet {
    $nuget = Get-Command nuget -ErrorAction SilentlyContinue
    if (-not $nuget) {
        winget install Microsoft.NuGet --accept-source-agreements --accept-package-agreements 2>$null | Out-Null
        # Refresh PATH for this session.
        $env:Path = [System.Environment]::GetEnvironmentVariable("Path", "Machine") + ";" + [System.Environment]::GetEnvironmentVariable("Path", "User")
        $nuget = Get-Command nuget -ErrorAction SilentlyContinue
    }
    if (-not $nuget) {
        Write-Host "  NuGet not on PATH; downloading nuget.exe locally..." -ForegroundColor Yellow
        $localNugetDir = "$env:USERPROFILE\.nuget"
        if (-not (Test-Path $localNugetDir)) { New-Item -ItemType Directory -Path $localNugetDir -Force | Out-Null }
        Invoke-WebRequest -Uri "https://dist.nuget.org/win-x86-commandline/latest/nuget.exe" -OutFile "$localNugetDir\nuget.exe"
        $env:Path = "$localNugetDir;$env:Path"
        $nuget = "$localNugetDir\nuget.exe"
    }
    return $nuget.Source
}

$nugetPath = Ensure-NuGet
Write-Host "  NuGet available at: $nugetPath" -ForegroundColor Green

# CppWinRT is only distributed via NuGet, not winget.
Write-Host "  Installing CppWinRT 2.0.210806.1 via NuGet..." -ForegroundColor Yellow
$projectRoot = Split-Path -Parent $PSScriptRoot

# Ensure nuget.org source exists without erroring if already present.
$sourcesList = & $nugetPath sources list 2>$null | Out-String
if ($sourcesList -notmatch "nuget\.org") {
    & $nugetPath sources add -Name "nuget.org" -Source "https://api.nuget.org/v3/index.json" 2>$null | Out-Null
}

Push-Location $projectRoot
try {
    & $nugetPath install Microsoft.Windows.CppWinRT -Version 2.0.210806.1 -OutputDirectory "$env:USERPROFILE\.nuget\packages" 2>$null | Out-Null
    if ($LASTEXITCODE -ne 0) { throw "nuget install Microsoft.Windows.CppWinRT failed with exit code $LASTEXITCODE." }
    Write-Host "  CppWinRT installed." -ForegroundColor Green
} finally {
    Pop-Location
}

# --- 5. Flutter ---
Write-Host "[5/9] Installing Flutter 3.38.5..." -ForegroundColor Yellow
$flutterInstalled = Get-Command flutter -ErrorAction SilentlyContinue
if (-not $flutterInstalled) {
    $flutterDir = "C:\flutter"
    $flutterZip = "$env:TEMP\flutter_windows_3.38.5-stable.zip"
    $flutterUrl = "https://storage.googleapis.com/flutter_infra_release/releases/stable/windows/flutter_windows_3.38.5-stable.zip"

    Write-Host "  Flutter not found. Downloading from $flutterUrl ..." -ForegroundColor Yellow
    try {
        if (Test-Path $flutterZip) { Remove-Item $flutterZip -Force }
        Invoke-WebRequest -Uri $flutterUrl -OutFile $flutterZip -ErrorAction Stop

        if (Test-Path $flutterDir) { Remove-Item $flutterDir -Recurse -Force }
        Expand-Archive -Path $flutterZip -DestinationPath "C:\" -Force
        Remove-Item $flutterZip -Force

        # Add to user PATH permanently and current session.
        [Environment]::SetEnvironmentVariable("Path", $env:Path + ";$flutterDir\bin", "User")
        $env:Path = $env:Path + ";$flutterDir\bin"

        Write-Host "  Flutter 3.38.5 installed at $flutterDir." -ForegroundColor Green
    } catch {
        Write-Host "  [WARN] Automatic Flutter download failed: $_" -ForegroundColor Yellow
        Write-Host "  Install Flutter manually from https://docs.flutter.dev/get-started/install/windows" -ForegroundColor Yellow
    }
} else {
    Write-Host "  Flutter already installed: $(flutter --version 2>$null | Select-Object -First 1)" -ForegroundColor Green
}
Refresh-Path

# --- 6. Rust (single toolchain: 1.85.1) ---
Write-Host "[6/9] Installing Rust 1.85.1 + MSVC target..." -ForegroundColor Yellow
$rustupInstalled = Get-Command rustup -ErrorAction SilentlyContinue
if (-not $rustupInstalled) {
    Write-Host "  Installing rustup-init..."
    Invoke-WebRequest -Uri "https://static.rust-lang.org/rustup/dist/x86_64-pc-windows-msvc/rustup-init.exe" -OutFile "$env:TEMP\rustup-init.exe"
    $rustupProc = Start-Process -FilePath "$env:TEMP\rustup-init.exe" -ArgumentList "-y", "--default-toolchain", "1.85.1" -Wait -PassThru
    if ($rustupProc.ExitCode -ne 0) {
        throw "rustup-init exited with code $($rustupProc.ExitCode)."
    }
    # Give Windows a moment to release the installer handle before cleanup.
    Start-Sleep -Seconds 2
    try {
        Remove-Item "$env:TEMP\rustup-init.exe" -Force -ErrorAction Stop
    } catch {
        Write-Host "  [WARN] Could not remove temp rustup-init.exe (in use or locked). It is safe to ignore." -ForegroundColor Yellow
    }
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
Refresh-Path

# --- 8. CMake, Ninja ---
Write-Host "[8/9] Installing CMake and Ninja..." -ForegroundColor Yellow
winget install Kitware.CMake --accept-source-agreements --accept-package-agreements 2>$null
if ($LASTEXITCODE -ne 0) { Write-Host "  CMake already installed or install skipped." -ForegroundColor Yellow }
winget install NinjaBuild.Ninja --accept-source-agreements --accept-package-agreements 2>$null
if ($LASTEXITCODE -ne 0) { Write-Host "  Ninja already installed or install skipped." -ForegroundColor Yellow }
Refresh-Path

# --- 9. Meson ---
Write-Host "[9/9] Installing Meson..." -ForegroundColor Yellow
$mesonInstalled = Get-Command meson -ErrorAction SilentlyContinue
if (-not $mesonInstalled) {
    pip install meson
    Write-Host "  Meson installed." -ForegroundColor Green
} else {
    Write-Host "  Meson already installed." -ForegroundColor Green
}
Refresh-Path

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
