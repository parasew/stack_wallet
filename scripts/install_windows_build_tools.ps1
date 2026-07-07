# Stack Wallet Windows Host Bootstrap
# Run from an elevated PowerShell (aka as Administrator), either from the project
# root or standalone on a fresh machine (this script installs Git itself, so it
# can be downloaded and run before the repository is cloned):
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
    Write-Host "    - Virtual machine on Apple Silicon (UTM, Parallels Desktop, VMware Fusion):" -ForegroundColor Yellow
    Write-Host "      Windows 11 ARM can run, but WSL2 is NOT SUPPORTED. These hypervisors do not expose" -ForegroundColor Yellow
    Write-Host "      nested virtualization to a Windows 11 ARM guest on Apple Silicon, so Hyper-V /" -ForegroundColor Yellow
    Write-Host "      Virtual Machine Platform / WSL2 cannot run. This is not a Windows config issue." -ForegroundColor Yellow
    Write-Host "    - Intel Mac running a Windows VM: enable nested virtualization in your hypervisor:" -ForegroundColor Yellow
    Write-Host "        VirtualBox: VM Settings > System > Acceleration > 'Nested VT-x/AMD-V'" -ForegroundColor Yellow
    Write-Host "        VMware Fusion: VM Settings > Processors & Memory > Advanced > 'Virtualize Intel VT-x/EPT or AMD-V/RVI'" -ForegroundColor Yellow
    Write-Host "        Hyper-V host: Set-VMProcessor -VMName 'YourVM' -ExposeVirtualizationExtensions `$true" -ForegroundColor Yellow
    Write-Host "    - Physical Windows PC: reboot into UEFI/BIOS and enable virtualization" -ForegroundColor Yellow
    Write-Host "      (Intel VT-x / AMD-V / SVM)." -ForegroundColor Yellow
    Write-Host ""
    Write-Host "  If you are on an Apple Silicon Mac, the Windows build cannot be done in a VM." -ForegroundColor Red
    Write-Host "  Instead, build the native macOS version of Stack Wallet:" -ForegroundColor Yellow
    Write-Host "    cd /path/to/stack_wallet" -ForegroundColor Yellow
    Write-Host "    make build-macos" -ForegroundColor Yellow
    Write-Host "  Or use a physical Windows PC / Intel Mac for the Windows build." -ForegroundColor Yellow
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

Write-Host "[0/9] Installing base prerequisites (Git, Python, GNU Make)..." -ForegroundColor Yellow
if (-not (Get-Command git -ErrorAction SilentlyContinue)) {
    winget install Git.Git --accept-source-agreements --accept-package-agreements
    Write-Host "  Git installed (includes Git Bash, required to run make targets)." -ForegroundColor Green
} else {
    Write-Host "  Git already installed." -ForegroundColor Green
}
# Fresh Windows 11 ships a Microsoft Store alias stub named python.exe in WindowsApps
# which is not a real interpreter; ignore it when checking.
$pythonReal = Get-Command python -ErrorAction SilentlyContinue | Where-Object { $_.Source -notmatch "WindowsApps" }
if (-not $pythonReal) {
    winget install Python.Python.3.12 --accept-source-agreements --accept-package-agreements
    Write-Host "  Python 3.12 installed (provides pip for the Meson step)." -ForegroundColor Green
} else {
    Write-Host "  Python already installed: $($pythonReal.Source)" -ForegroundColor Green
}
if (-not (Get-Command make -ErrorAction SilentlyContinue)) {
    winget install ezwinports.make --accept-source-agreements --accept-package-agreements
    Write-Host "  GNU Make installed (run 'make build-windows' from Git Bash)." -ForegroundColor Green
} else {
    Write-Host "  Make already installed." -ForegroundColor Green
}
Refresh-Path

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

# WSL_UTF8=1 makes wsl.exe emit UTF-8 instead of UTF-16LE, so -match works on
# redirected output.
$env:WSL_UTF8 = "1"

# Probe wsl.exe via cmd so its stderr never reaches the PowerShell error stream:
# under Windows PowerShell 5.1 with $ErrorActionPreference = "Stop", redirected
# native stderr (2>$null) is converted into a terminating NativeCommandError,
# which aborted this script on machines where WSL was never installed.
$wslListOutput = cmd /c "wsl.exe -l -q 2>nul"
$wslFunctional = ($LASTEXITCODE -eq 0)

if ($wslFunctional -and ($wslListOutput -match "Ubuntu-24.04")) {
    Write-Host "  Ubuntu 24.04 already registered in WSL." -ForegroundColor Green
} else {
    if (-not $wslFunctional) {
        Write-Host "  WSL not yet installed; enabling WSL2 features first..." -ForegroundColor Yellow
        Enable-WslFeature
    }
    Write-Host "  Installing Ubuntu 24.04 in WSL2..." -ForegroundColor Yellow
    # This command actually starts a lightweight VM, so it also validates nested virtualization.
    $installOutput = cmd /c "wsl.exe --install -d Ubuntu-24.04 --no-launch 2>&1"
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

# Verify the C++ workload actually landed, regardless of which branch ran above.
# winget reports success based on the VS bootstrapper's exit, not the component
# installer's, so a bare VS without the NativeDesktop workload can pass silently
# (observed on a fresh Windows 11 machine). vcvars64.bat presence is also not a
# reliable proxy for the workload.
$vswhereExe = "${env:ProgramFiles(x86)}\Microsoft Visual Studio\Installer\vswhere.exe"
$vsSetupExe = "${env:ProgramFiles(x86)}\Microsoft Visual Studio\Installer\setup.exe"
$vsCommunityPath = "C:\Program Files\Microsoft Visual Studio\2022\Community"

function Test-VsCppWorkload {
    if (-not (Test-Path $vswhereExe)) { return $false }
    $out = & $vswhereExe -latest -products * -requires Microsoft.VisualStudio.Workload.NativeDesktop -property installationPath
    return -not [string]::IsNullOrWhiteSpace("$out")
}

if (-not (Test-VsCppWorkload)) {
    Write-Host "  C++ workload (NativeDesktop) missing; adding via VS Installer (10-30 min, no UI)..." -ForegroundColor Yellow
    # NOTE 1: '--wait' is a VS *bootstrapper* flag; the installed setup.exe
    # rejects it with exit code 87 ("Option 'wait' is unknown").
    # NOTE 2: setup.exe is a GUI-subsystem binary, so a bare call returns the
    # prompt immediately. Piping to Out-Null holds the pipeline open until the
    # process exits, giving a deterministic wait: the PowerShell equivalent of
    # 'start /wait', which is Microsoft's documented pattern for automating
    # setup.exe. Exit codes: 0 = success, 3010 = success but reboot required.
    # https://learn.microsoft.com/visualstudio/install/use-command-line-parameters-to-install-visual-studio
    $vsModifyArgs = @(
        'modify',
        '--installPath', $vsCommunityPath,
        '--add', 'Microsoft.VisualStudio.Workload.NativeDesktop',
        '--includeRecommended',
        '--quiet',
        '--norestart'
    )
    & $vsSetupExe @vsModifyArgs | Out-Null
    switch ($LASTEXITCODE) {
        0       { Write-Host "  VS Installer finished (exit 0)." -ForegroundColor Green }
        3010    { Write-Host "  VS Installer finished; reboot required (exit 3010)." -ForegroundColor Yellow }
        default { Write-Host "  [WARN] VS Installer exit code $($LASTEXITCODE); see the error-codes table in the Microsoft docs linked above." -ForegroundColor Red }
    }
}
if (Test-VsCppWorkload) {
    Write-Host "  C++ workload (NativeDesktop) verified via vswhere." -ForegroundColor Green
} else {
    Write-Host "  [WARN] NativeDesktop workload still not detected. Open the Visual Studio Installer GUI, add 'Desktop development with C++', then re-run this script." -ForegroundColor Red
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
        # curl.exe ships with Windows 11 and handles a ~1 GB download far more
        # reliably than Invoke-WebRequest (retries, resume of partial files).
        & "$env:SystemRoot\System32\curl.exe" -L --fail --retry 5 --retry-delay 5 -C - -o $flutterZip $flutterUrl
        if ($LASTEXITCODE -ne 0) { throw "curl exited with code $LASTEXITCODE after retries" }

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

# --- 5b. Flutter warm-up ---
# The first flutter invocation downloads the matching Dart SDK into
# bin/cache and builds the flutter_tools snapshot. Do it here, visibly,
# instead of letting it surprise the first 'make build-windows'. Also
# pre-download the Windows desktop build artifacts.
if (Get-Command flutter -ErrorAction SilentlyContinue) {
    Write-Host "  Warming up Flutter (first run downloads the Dart SDK and builds the tool)..." -ForegroundColor Yellow
    $prevEAP = $ErrorActionPreference; $ErrorActionPreference = "Continue"
    flutter --version
    flutter precache --windows
    $ErrorActionPreference = $prevEAP
    Write-Host "  Flutter warm-up done." -ForegroundColor Green
}

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
winget install -e --id Ninja-build.Ninja --accept-source-agreements --accept-package-agreements 2>$null
if ($LASTEXITCODE -ne 0) { Write-Host "  Ninja already installed or install skipped." -ForegroundColor Yellow }
Refresh-Path

# --- 9. Meson ---
Write-Host "[9/9] Installing Meson..." -ForegroundColor Yellow
$mesonInstalled = Get-Command meson -ErrorAction SilentlyContinue
if (-not $mesonInstalled) {
    python -m pip install --upgrade pip
    python -m pip install meson
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

Test-Tool "Git" "git"
Test-Tool "Python" "python"
Test-Tool "Make" "make"
Test-Tool "Flutter" "flutter"
Test-Tool "Dart" "dart"
Test-Tool "Rust" "rustc"
Test-Tool "Cargo" "cargo"
Test-Tool "Go" "go"
Test-Tool "CMake" "cmake"
Test-Tool "Ninja" "ninja"
Test-Tool "Meson" "meson"

# Execution check: actually run the tools, not just resolve them on PATH.
# EAP is relaxed because under PowerShell 5.1 + ErrorActionPreference=Stop,
# a 2>&1 redirect turns any native stderr output into a terminating error.
$prevEAP = $ErrorActionPreference; $ErrorActionPreference = "Continue"
Write-Host ""
Write-Host "  Tool versions (execution check):" -ForegroundColor Cyan
foreach ($probe in @(
    @{ n = "flutter"; a = "--version" },
    @{ n = "dart";    a = "--version" },
    @{ n = "ninja";   a = "--version" },
    @{ n = "make";    a = "--version" },
    @{ n = "go";      a = "version" }
)) {
    if (Get-Command $probe.n -ErrorAction SilentlyContinue) {
        $v = (& $probe.n $probe.a 2>&1 | Select-Object -First 1)
        Write-Host "    $($probe.n): $v"
    } else {
        Write-Host "    $($probe.n): not on PATH in this session"
    }
}
$ErrorActionPreference = $prevEAP

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
Write-Host ""
Write-Host "Then build from Git Bash (not PowerShell/cmd; make targets need a POSIX shell):" -ForegroundColor Cyan
Write-Host "  cd /c/path/to/stack_wallet"
Write-Host "  make build-windows VERSION=x.y.z BUILD_NUM=nnn"
