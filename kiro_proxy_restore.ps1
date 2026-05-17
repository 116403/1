# Kiro IDE Proxy Restore Script
# Usage: powershell -ExecutionPolicy Bypass -File kiro_proxy_restore.ps1

Write-Host "============================================" -ForegroundColor Cyan
Write-Host "  Kiro IDE Proxy Restore Tool" -ForegroundColor Cyan
Write-Host "============================================" -ForegroundColor Cyan
Write-Host ""

# ===== 1. Disable System Proxy =====
Write-Host "[1/2] Disabling system proxy..." -ForegroundColor Yellow
$regPath = "HKCU:\Software\Microsoft\Windows\CurrentVersion\Internet Settings"
try {
    Set-ItemProperty -Path $regPath -Name ProxyEnable -Value 0
    Write-Host "  [OK] System proxy disabled" -ForegroundColor Green
} catch {
    Write-Host "  [FAIL] Could not disable system proxy" -ForegroundColor Red
}

try {
    $source = @"
using System;
using System.Runtime.InteropServices;
public class WinInet2 {
    [DllImport("wininet.dll", SetLastError=true)]
    public static extern bool InternetSetOption(IntPtr hInternet, int dwOption, IntPtr lpBuffer, int lpdwBufferLength);
}
"@
    Add-Type -TypeDefinition $source -ErrorAction SilentlyContinue
    [WinInet2]::InternetSetOption([IntPtr]::Zero, 39, [IntPtr]::Zero, 0) | Out-Null
    [WinInet2]::InternetSetOption([IntPtr]::Zero, 37, [IntPtr]::Zero, 0) | Out-Null
} catch {}
Write-Host ""

# ===== 2. Clear Environment Variables =====
Write-Host "[2/2] Clearing proxy environment variables..." -ForegroundColor Yellow
[System.Environment]::SetEnvironmentVariable("HTTP_PROXY", $null, "User")
[System.Environment]::SetEnvironmentVariable("HTTPS_PROXY", $null, "User")
[System.Environment]::SetEnvironmentVariable("ALL_PROXY", $null, "User")
[System.Environment]::SetEnvironmentVariable("NO_PROXY", $null, "User")
Write-Host "  [OK] Cleared HTTP_PROXY, HTTPS_PROXY, ALL_PROXY, NO_PROXY" -ForegroundColor Green
Write-Host ""

# ===== Done =====
Write-Host "  Restore complete." -ForegroundColor Green
Write-Host "  You can now restart ProxyBridge and launch Kiro normally." -ForegroundColor White
Write-Host ""
pause
