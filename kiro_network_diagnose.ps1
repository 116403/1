# Kiro IDE Network Diagnostic Script
# Usage: powershell -ExecutionPolicy Bypass -File kiro_network_diagnose.ps1
# Note: All output is in English to avoid PowerShell 5.1 GBK/UTF-8 encoding issues.

param(
    [int]$ProxyPort = 7897,
    [string]$ProxyHost = "127.0.0.1"
)

$ErrorActionPreference = "SilentlyContinue"
$results = @()
$proxyAddr = "${ProxyHost}:${ProxyPort}"
$proxyUrl  = "http://${proxyAddr}"

Write-Host ""
Write-Host "============================================" -ForegroundColor Cyan
Write-Host "  Kiro IDE Network Diagnostics" -ForegroundColor Cyan
Write-Host "  Target proxy: $proxyAddr" -ForegroundColor Cyan
Write-Host "============================================" -ForegroundColor Cyan
Write-Host ""

# ========== [1/9] Clash / Mihomo / Verge process ==========
Write-Host "[1/9] Checking Clash / Mihomo / Verge process..." -ForegroundColor Yellow
$clash = Get-Process -Name "*clash*","*mihomo*","*verge*" -ErrorAction SilentlyContinue
if ($clash) {
    foreach ($p in $clash) {
        Write-Host "  [OK] Running: $($p.ProcessName) (PID=$($p.Id))" -ForegroundColor Green
    }
} else {
    Write-Host "  [FAIL] No Clash/Mihomo/Verge process found" -ForegroundColor Red
    $results += "Clash not running"
}
Write-Host ""

# ========== [2/9] ProxyBridge process ==========
Write-Host "[2/9] Checking ProxyBridge..." -ForegroundColor Yellow
$bridge = Get-Process -Name "*proxybridge*" -ErrorAction SilentlyContinue
if ($bridge) {
    foreach ($p in $bridge) {
        Write-Host "  [WARN] ProxyBridge running: $($p.ProcessName) (PID=$($p.Id))" -ForegroundColor DarkYellow
    }
    Write-Host "  Note: ProxyBridge intercept rules may be incomplete." -ForegroundColor DarkYellow
} else {
    Write-Host "  [INFO] ProxyBridge not running" -ForegroundColor Gray
}
Write-Host ""

# ========== [3/9] Clash port reachable ==========
Write-Host "[3/9] Testing proxy port ${proxyAddr}..." -ForegroundColor Yellow
try {
    $tcp = Test-NetConnection -ComputerName $ProxyHost -Port $ProxyPort -WarningAction SilentlyContinue
    if ($tcp.TcpTestSucceeded) {
        Write-Host "  [OK] Port ${proxyAddr} is open" -ForegroundColor Green
    } else {
        Write-Host "  [FAIL] Port ${proxyAddr} is NOT reachable" -ForegroundColor Red
        $results += "Proxy port unreachable"
    }
} catch {
    Write-Host "  [FAIL] Port test error: $($_.Exception.Message)" -ForegroundColor Red
}
Write-Host ""

# ========== [4/9] System proxy registry ==========
Write-Host "[4/9] Checking Windows system proxy..." -ForegroundColor Yellow
$regPath = "HKCU:\Software\Microsoft\Windows\CurrentVersion\Internet Settings"
$proxyReg = Get-ItemProperty -Path $regPath -ErrorAction SilentlyContinue
if ($proxyReg.ProxyEnable -eq 1) {
    Write-Host "  [OK] System proxy enabled: $($proxyReg.ProxyServer)" -ForegroundColor Green
    Write-Host "       Bypass: $($proxyReg.ProxyOverride)" -ForegroundColor Gray
} else {
    Write-Host "  [INFO] System proxy is disabled" -ForegroundColor Gray
}
Write-Host ""

# ========== [5/9] Environment variables ==========
Write-Host "[5/9] Checking proxy environment variables..." -ForegroundColor Yellow
$envVars = @("HTTP_PROXY","HTTPS_PROXY","ALL_PROXY","NO_PROXY")
foreach ($v in $envVars) {
    $val = [System.Environment]::GetEnvironmentVariable($v, "User")
    if ($val) {
        Write-Host "  [SET] $v = $val" -ForegroundColor Green
    } else {
        Write-Host "  [---] $v not set" -ForegroundColor Gray
    }
}
Write-Host ""

# ========== [6/9] DNS resolution for Kiro endpoints ==========
Write-Host "[6/9] DNS resolution for Kiro endpoints..." -ForegroundColor Yellow
$hosts = @(
    "ide.kiro.dev",
    "cognito-idp.us-east-1.amazonaws.com",
    "execute-api.us-east-1.amazonaws.com",
    "codewhisperer.us-east-1.amazonaws.com"
)
foreach ($h in $hosts) {
    try {
        $dns = Resolve-DnsName -Name $h -Type A -DnsOnly -QuickTimeout -ErrorAction Stop | Select-Object -First 1
        Write-Host "  [OK] $h -> $($dns.IPAddress)" -ForegroundColor Green
    } catch {
        Write-Host "  [FAIL] $h cannot be resolved" -ForegroundColor Red
        $results += "DNS fail: $h"
    }
}
Write-Host ""

# ========== [7/9] Long-lived connection test (the critical one) ==========
Write-Host "[7/9] Long-lived connection test (90 seconds)..." -ForegroundColor Yellow
Write-Host "      Simulates the streaming response that breaks Kiro IDE." -ForegroundColor Gray
$webProxy = New-Object System.Net.WebProxy($proxyUrl, $true)
try {
    $req = [System.Net.HttpWebRequest]::Create("https://ide.kiro.dev/")
    $req.Proxy = $webProxy
    $req.Timeout = 100000
    $req.ReadWriteTimeout = 100000
    $req.KeepAlive = $true
    $sw = [System.Diagnostics.Stopwatch]::StartNew()
    $resp = $req.GetResponse()
    $sw.Stop()
    Write-Host "  [OK] Initial request succeeded via proxy in $($sw.ElapsedMilliseconds) ms" -ForegroundColor Green
    Write-Host "       Status: $($resp.StatusCode)" -ForegroundColor Gray
    $resp.Close()
} catch {
    Write-Host "  [FAIL] Long connection test failed: $($_.Exception.Message)" -ForegroundColor Red
    $results += "Long connection failed: $($_.Exception.Message)"
}
Write-Host ""

# ========== [8/9] HTTPS GET via proxy ==========
Write-Host "[8/9] HTTPS GET test via proxy..." -ForegroundColor Yellow
$testUrls = @(
    @{ name = "ide.kiro.dev";       url = "https://ide.kiro.dev/" },
    @{ name = "cognito-idp aws";    url = "https://cognito-idp.us-east-1.amazonaws.com/" },
    @{ name = "execute-api aws";    url = "https://execute-api.us-east-1.amazonaws.com/" }
)
foreach ($item in $testUrls) {
    try {
        $req = [System.Net.HttpWebRequest]::Create($item.url)
        $req.Proxy = $webProxy
        $req.Timeout = 15000
        $req.Method = "GET"
        $resp = $req.GetResponse()
        Write-Host "  [OK] $($item.name) - $($resp.StatusCode)" -ForegroundColor Green
        $resp.Close()
    } catch {
        $errMsg = $_.Exception.Message
        # 401/403 from AWS endpoints means we reached them, just unauthenticated -> still OK
        if ($errMsg -match "401|403") {
            Write-Host "  [OK] $($item.name) - reached (auth required, expected)" -ForegroundColor Green
        } else {
            Write-Host "  [FAIL] $($item.name) - $errMsg" -ForegroundColor Red
            $results += "$($item.name) failed: $errMsg"
        }
    }
}
Write-Host ""

# ========== [9/9] Active TCP connections from Kiro ==========
Write-Host "[9/9] Active TCP connections from Kiro processes..." -ForegroundColor Yellow
$kiroProcs = Get-Process -Name "*kiro*" -ErrorAction SilentlyContinue
if (-not $kiroProcs) {
    Write-Host "  [INFO] Kiro is not currently running" -ForegroundColor Gray
} else {
    $pids = $kiroProcs | Select-Object -ExpandProperty Id
    Write-Host "  Found $($pids.Count) Kiro process(es)" -ForegroundColor Gray
    $conns = Get-NetTCPConnection -State Established -ErrorAction SilentlyContinue |
             Where-Object { $pids -contains $_.OwningProcess }
    if ($conns) {
        $proxyConns = $conns | Where-Object { $_.RemotePort -eq $ProxyPort -and $_.RemoteAddress -eq $ProxyHost }
        $directConns = $conns | Where-Object { -not ($_.RemotePort -eq $ProxyPort -and $_.RemoteAddress -eq $ProxyHost) -and $_.RemoteAddress -ne "127.0.0.1" -and $_.RemoteAddress -ne "::1" }
        Write-Host "  Connections via proxy ($proxyAddr): $($proxyConns.Count)" -ForegroundColor Green
        Write-Host "  Direct external connections: $($directConns.Count)" -ForegroundColor $(if ($directConns.Count -gt 0) { "Red" } else { "Green" })
        if ($directConns.Count -gt 0) {
            Write-Host "  --- WARNING: Kiro is making DIRECT connections (bypassing proxy) ---" -ForegroundColor Red
            $directConns | Select-Object -First 10 | ForEach-Object {
                Write-Host "    $($_.RemoteAddress):$($_.RemotePort)" -ForegroundColor DarkRed
            }
            $results += "Kiro has $($directConns.Count) direct connections bypassing proxy"
        }
    } else {
        Write-Host "  [INFO] No established connections from Kiro right now" -ForegroundColor Gray
    }
}
Write-Host ""

# ========== Summary ==========
Write-Host "============================================" -ForegroundColor Cyan
Write-Host "  Diagnostic Summary" -ForegroundColor Cyan
Write-Host "============================================" -ForegroundColor Cyan
if ($results.Count -eq 0) {
    Write-Host "  [PASS] No issues detected" -ForegroundColor Green
} else {
    Write-Host "  [FOUND $($results.Count) ISSUE(S)]" -ForegroundColor Red
    foreach ($r in $results) {
        Write-Host "    - $r" -ForegroundColor Red
    }
}
Write-Host ""
Write-Host "Recommended next steps:" -ForegroundColor Yellow
Write-Host "  1. If [7/9] long connection FAILED -> root cause confirmed" -ForegroundColor White
Write-Host "  2. If [9/9] shows DIRECT connections -> ProxyBridge rule is wrong" -ForegroundColor White
Write-Host "  3. Run kiro_proxy_fix.ps1 to apply the fix" -ForegroundColor White
Write-Host "  4. Or enable TUN mode in Clash Verge for the cleanest fix" -ForegroundColor White
Write-Host ""
pause
