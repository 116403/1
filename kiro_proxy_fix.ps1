# Kiro IDE Proxy Fix Script
# Usage: powershell -ExecutionPolicy Bypass -File kiro_proxy_fix.ps1

param(
    [int]$ProxyPort = 7897,
    [string]$ProxyHost = "127.0.0.1"
)

$ErrorActionPreference = "SilentlyContinue"

Write-Host "============================================" -ForegroundColor Cyan
Write-Host "  Kiro IDE Proxy Fix Tool" -ForegroundColor Cyan
Write-Host "============================================" -ForegroundColor Cyan
Write-Host ""

$proxyAddr = "${ProxyHost}:${ProxyPort}"

# ===== Step 1: Check Clash =====
Write-Host "[Step 1] Checking Clash proxy..." -ForegroundColor Yellow
$clashRunning = Get-Process -Name "*clash*", "*mihomo*", "*verge*" -ErrorAction SilentlyContinue
if (-not $clashRunning) {
    Write-Host "  [FAIL] Clash/Mihomo not running! Start Clash Verge first." -ForegroundColor Red
    pause
    exit 1
}
Write-Host "  [OK] Clash is running" -ForegroundColor Green

$portTest = Test-NetConnection -ComputerName $ProxyHost -Port $ProxyPort -WarningAction SilentlyContinue
if (-not $portTest.TcpTestSucceeded) {
    Write-Host "  [FAIL] Proxy port ${proxyAddr} not reachable!" -ForegroundColor Red
    pause
    exit 1
}
Write-Host "  [OK] Proxy port ${proxyAddr} is open" -ForegroundColor Green
Write-Host ""

# ===== Step 2: Stop ProxyBridge =====
Write-Host "[Step 2] Stopping ProxyBridge..." -ForegroundColor Yellow
$bridgeProcesses = Get-Process -Name "*proxybridge*", "*proxy*bridge*" -ErrorAction SilentlyContinue
if ($bridgeProcesses) {
    foreach ($p in $bridgeProcesses) {
        Stop-Process -Id $p.Id -Force -ErrorAction SilentlyContinue
        Write-Host "  [OK] Stopped: $($p.ProcessName)" -ForegroundColor Green
    }
} else {
    Write-Host "  ProxyBridge not detected. Please close it manually if running." -ForegroundColor DarkYellow
}
Write-Host ""

# ===== Step 3: Enable System Proxy =====
Write-Host "[Step 3] Setting system proxy to ${proxyAddr}..." -ForegroundColor Yellow
$regPath = "HKCU:\Software\Microsoft\Windows\CurrentVersion\Internet Settings"

try {
    Set-ItemProperty -Path $regPath -Name ProxyEnable -Value 1
    Set-ItemProperty -Path $regPath -Name ProxyServer -Value $proxyAddr
    $bypass = "localhost;127.*;10.*;192.168.*;<local>"
    Set-ItemProperty -Path $regPath -Name ProxyOverride -Value $bypass
    Write-Host "  [OK] System proxy enabled: $proxyAddr" -ForegroundColor Green
} catch {
    Write-Host "  [FAIL] Could not set system proxy" -ForegroundColor Red
}

# Notify system of proxy change
try {
    $source = @"
using System;
using System.Runtime.InteropServices;
public class WinInet {
    [DllImport("wininet.dll", SetLastError=true)]
    public static extern bool InternetSetOption(IntPtr hInternet, int dwOption, IntPtr lpBuffer, int lpdwBufferLength);
}
"@
    Add-Type -TypeDefinition $source -ErrorAction SilentlyContinue
    [WinInet]::InternetSetOption([IntPtr]::Zero, 39, [IntPtr]::Zero, 0) | Out-Null
    [WinInet]::InternetSetOption([IntPtr]::Zero, 37, [IntPtr]::Zero, 0) | Out-Null
    Write-Host "  [OK] System notified of proxy change" -ForegroundColor Green
} catch {
    Write-Host "  [WARN] Could not notify system" -ForegroundColor DarkYellow
}
Write-Host ""

# ===== Step 4: Set Environment Variables =====
Write-Host "[Step 4] Setting proxy environment variables..." -ForegroundColor Yellow
$proxyUrl = "http://${proxyAddr}"
[System.Environment]::SetEnvironmentVariable("HTTP_PROXY", $proxyUrl, "User")
[System.Environment]::SetEnvironmentVariable("HTTPS_PROXY", $proxyUrl, "User")
[System.Environment]::SetEnvironmentVariable("ALL_PROXY", $proxyUrl, "User")
[System.Environment]::SetEnvironmentVariable("NO_PROXY", "localhost,127.0.0.1,::1", "User")
$env:HTTP_PROXY = $proxyUrl
$env:HTTPS_PROXY = $proxyUrl
$env:ALL_PROXY = $proxyUrl
$env:NO_PROXY = "localhost,127.0.0.1,::1"
Write-Host "  [OK] HTTP_PROXY  = $proxyUrl" -ForegroundColor Green
Write-Host "  [OK] HTTPS_PROXY = $proxyUrl" -ForegroundColor Green
Write-Host ""

# ===== Step 5: Kill existing Kiro =====
Write-Host "[Step 5] Closing Kiro..." -ForegroundColor Yellow
$kiroProcesses = Get-Process -Name "*kiro*" -ErrorAction SilentlyContinue
if ($kiroProcesses) {
    Write-Host "  Found $($kiroProcesses.Count) Kiro processes, closing..." -ForegroundColor Cyan
    $kiroProcesses | Stop-Process -Force -ErrorAction SilentlyContinue
    Start-Sleep -Seconds 3
    Write-Host "  [OK] Kiro closed" -ForegroundColor Green
} else {
    Write-Host "  Kiro not running" -ForegroundColor Green
}
Write-Host ""

# ===== Step 6: Launch Kiro with proxy =====
Write-Host "[Step 6] Launching Kiro with proxy..." -ForegroundColor Yellow

$kiroPath = $null
$searchPaths = @(
    "$env:LOCALAPPDATA\Programs\Kiro\Kiro.exe",
    "$env:LOCALAPPDATA\Kiro\Kiro.exe",
    "$env:ProgramFiles\Kiro\Kiro.exe",
    "${env:ProgramFiles(x86)}\Kiro\Kiro.exe"
)

foreach ($path in $searchPaths) {
    if (Test-Path $path) {
        $kiroPath = $path
        break
    }
}

if (-not $kiroPath) {
    $regKeys = @(
        "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*",
        "HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*"
    )
    foreach ($key in $regKeys) {
        $found = Get-ItemProperty -Path $key -ErrorAction SilentlyContinue | Where-Object { $_.DisplayName -match "Kiro" }
        if ($found -and $found.InstallLocation) {
            $testPath = Join-Path $found.InstallLocation "Kiro.exe"
            if (Test-Path $testPath) {
                $kiroPath = $testPath
                break
            }
        }
    }
}

if (-not $kiroPath) {
    $kiroPath = (Get-Command "Kiro.exe" -ErrorAction SilentlyContinue).Source
}

if ($kiroPath) {
    Write-Host "  Found Kiro: $kiroPath" -ForegroundColor Green
    $args = "--proxy-server=http://${proxyAddr}"
    Write-Host "  Args: $args" -ForegroundColor Cyan
    Start-Process -FilePath $kiroPath -ArgumentList $args
    Write-Host "  [OK] Kiro launched with proxy" -ForegroundColor Green
} else {
    Write-Host "  [FAIL] Cannot find Kiro.exe!" -ForegroundColor Red
    Write-Host "  Please launch Kiro manually with this argument:" -ForegroundColor Yellow
    Write-Host "    --proxy-server=http://${proxyAddr}" -ForegroundColor Cyan
}
Write-Host ""

# ===== Done =====
Write-Host "============================================" -ForegroundColor Cyan
Write-Host "  Done! Summary:" -ForegroundColor Cyan
Write-Host "============================================" -ForegroundColor Cyan
Write-Host "  1. Clash proxy verified OK" -ForegroundColor White
Write-Host "  2. ProxyBridge stopped (close manually if needed)" -ForegroundColor White
Write-Host "  3. System proxy set to $proxyAddr" -ForegroundColor White
Write-Host "  4. Environment variables set" -ForegroundColor White
Write-Host "  5. Kiro restarted with --proxy-server" -ForegroundColor White
Write-Host ""
Write-Host "  If still not working:" -ForegroundColor Yellow
Write-Host "    - Enable TUN mode in Clash Verge" -ForegroundColor Gray
Write-Host "    - Switch to a more stable proxy node" -ForegroundColor Gray
Write-Host "    - Make sure *.kiro.dev and *.amazonaws.com go through proxy" -ForegroundColor Gray
Write-Host ""
Write-Host "  To restore: run kiro_proxy_restore.ps1" -ForegroundColor DarkYellow
Write-Host ""
pause
