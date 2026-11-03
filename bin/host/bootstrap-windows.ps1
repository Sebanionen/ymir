# bootstrap-windows.ps1 — give a Windows operator the Ubuntu host Ymir needs.
#
# Ymir's core is portable, but what it installs is a Linux runtime. On Windows
# the host is Ubuntu inside WSL2. This enables WSL, installs Ubuntu, and then
# hands the install to bin/engine/ymir-install.sh *inside* that distro.
#
# Run elevated (WSL needs it). Expect ONE reboot on a machine that has never had
# WSL — the script says so plainly and tells you the single command to run after.
#
#   powershell -ExecutionPolicy Bypass -File bin\host\bootstrap-windows.ps1
#   powershell -ExecutionPolicy Bypass -File bin\host\bootstrap-windows.ps1 -Check
#
# Gated on its host (Rule 05): off Windows it skips cleanly.

[CmdletBinding()]
param(
  [switch]$Check,
  [string]$Repo = "",
  [string]$Distro = "Ubuntu"
)

$ErrorActionPreference = "Stop"
$VERSION = "1.0.0"

function Row($step, $status, $detail) { Write-Host ("  `"{0}`",`"{1}`",`"{2}`"" -f $step, $status, $detail) }

if (-not ($env:OS -eq "Windows_NT")) {
  Write-Host 'windows-bootstrap[1]{step,status,detail}:'
  Row "layer" "SKIP" "not Windows - this layer applies on Windows; run bin/host/host-sense.sh for THIS machine"
  exit 0
}

# --- 1. administrator -------------------------------------------------------
$admin = ([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole(
  [Security.Principal.WindowsBuiltInRole]::Administrator)

# --- 2. is the Linux host already here? -------------------------------------
$wsl = $null
try { $wsl = & wsl.exe --status 2>$null } catch { }
$hasWsl = $LASTEXITCODE -eq 0
$hasDistro = $false
if ($hasWsl) {
  try {
    $list = & wsl.exe -l -q 2>$null
    $hasDistro = ($list | ForEach-Object { $_.Trim() }) -contains $Distro
  } catch { }
}

if ($Check) {
  Write-Host 'windows-bootstrap[4]{step,status,detail}:'
  Row "host"      "OK"      ("Windows " + [System.Environment]::OSVersion.Version)
  Row "admin"     $(if ($admin) { "OK" } else { "MISSING" })  "WSL setup needs an elevated shell"
  Row "wsl"       $(if ($hasWsl) { "OK" } else { "MISSING" }) "the Windows Subsystem for Linux"
  Row "distro"    $(if ($hasDistro) { "OK" } else { "MISSING" }) "$Distro - the Linux host Ymir installs into"
  exit 0
}

if (-not $admin) {
  Write-Error "an elevated PowerShell is required to enable WSL"
  Write-Host "help: re-open PowerShell as Administrator, then run this script again"
  exit 1
}

# --- 3. enable WSL + install Ubuntu -----------------------------------------
if (-not ($hasWsl -and $hasDistro)) {
  Write-Host "enabling WSL and installing $Distro (this may take a while)..." -ForegroundColor Cyan
  & wsl.exe --install -d $Distro
  if ($LASTEXITCODE -ne 0) {
    Write-Host "wsl --install did not complete."
    Write-Host "help: run 'wsl --install -d $Distro' by hand to see the error."
    Write-Host "      If the machine has never had WSL, a REBOOT is required first:"
    Write-Host "      reboot, then run this script again."
    exit 1
  }
  Write-Host ""
  Write-Host "WSL + $Distro are being installed. A REBOOT may be required." -ForegroundColor Yellow
  Write-Host "After the reboot, finish with:" -ForegroundColor Yellow
  Write-Host "  powershell -ExecutionPolicy Bypass -File bin\host\bootstrap-windows.ps1"
  exit 0
}

# --- 4. Ymir inside the distro ----------------------------------------------
Write-Host "installing Ymir inside $Distro..." -ForegroundColor Cyan
if (-not $Repo) {
  try { $Repo = (git remote get-url origin) } catch { $Repo = "" }
}
$inner = @'
set -e
command -v git >/dev/null 2>&1 || { sudo apt-get update -qq && sudo apt-get install -y -qq git; }
if [ -n "%REPO%" ]; then
  [ -d "$HOME/Ymir/.git" ] || git clone "%REPO%" "$HOME/Ymir"
  cd "$HOME/Ymir" && { git pull --ff-only || true; }
fi
cd "$HOME/Ymir" && bin/engine/ymir-install.sh --yes
'@
$inner = $inner.Replace("%REPO%", $Repo)

& wsl.exe -d $Distro -- bash -lc $inner
if ($LASTEXITCODE -ne 0) {
  Write-Host "the in-distro install failed." -ForegroundColor Red
  Write-Host "help: wsl -d $Distro -- bash -lc 'cd ~/Ymir && bin/engine/ymir-install.sh'"
  exit 1
}

Write-Host ''
Write-Host 'windows-bootstrap[3]{step,status,detail}:'
Row "wsl"    "OK"   "Windows Subsystem for Linux"
Row "distro" "OK"   $Distro
Row "ymir"   $(if ($Repo) { "OK" } else { "SKIP" }) $(if ($Repo) { "installed inside the distro" } else { "no repo to clone" })
Write-Host ''
Write-Host ("next: wsl -d {0}                      # the Linux host" -f $Distro)
Write-Host "      open http://127.0.0.1:3888/     # Hlidskjalf (WSL forwards localhost)"
