# Kiro IDE 代理修复脚本
# 功能: 开启系统代理 + 关闭 ProxyBridge + 用代理参数启动 Kiro
# 使用方法: 右键以管理员身份运行 PowerShell，执行: powershell -ExecutionPolicy Bypass -File kiro_proxy_fix.ps1

param(
    [int]$ProxyPort = 7897,
    [string]$ProxyHost = "127.0.0.1"
)

$ErrorActionPreference = "SilentlyContinue"

Write-Host "============================================" -ForegroundColor Cyan
Write-Host "  Kiro IDE 代理修复工具" -ForegroundColor Cyan
Write-Host "============================================" -ForegroundColor Cyan
Write-Host ""

$proxyAddr = "${ProxyHost}:${ProxyPort}"

# ===== Step 1: 检查 Clash 是否运行 =====
Write-Host "[Step 1] 检查 Clash 代理是否运行..." -ForegroundColor Yellow
$clashRunning = Get-Process -Name "*clash*", "*mihomo*", "*verge*" -ErrorAction SilentlyContinue
if (-not $clashRunning) {
    Write-Host "  [!!] Clash/Mihomo 未运行! 请先启动 Clash Verge" -ForegroundColor Red
    Write-Host "  脚本退出。" -ForegroundColor Red
    pause
    exit 1
}
Write-Host "  [OK] Clash 正在运行" -ForegroundColor Green

# 验证代理端口可用
$portTest = Test-NetConnection -ComputerName $ProxyHost -Port $ProxyPort -WarningAction SilentlyContinue
if (-not $portTest.TcpTestSucceeded) {
    Write-Host "  [!!] 代理端口 ${proxyAddr} 不可达!" -ForegroundColor Red
    Write-Host "  请确认 Clash Verge 端口设置是否为 $ProxyPort" -ForegroundColor Red
    pause
    exit 1
}
Write-Host "  [OK] 代理端口 ${proxyAddr} 可用" -ForegroundColor Green
Write-Host ""

# ===== Step 2: 关闭 ProxyBridge =====
Write-Host "[Step 2] 关闭 ProxyBridge (避免冲突)..." -ForegroundColor Yellow
$bridgeProcesses = Get-Process -Name "*proxybridge*", "*proxy*bridge*" -ErrorAction SilentlyContinue
if ($bridgeProcesses) {
    foreach ($p in $bridgeProcesses) {
        try {
            Stop-Process -Id $p.Id -Force
            Write-Host "  [OK] 已关闭: $($p.ProcessName) (PID: $($p.Id))" -ForegroundColor Green
        } catch {
            Write-Host "  [!!] 无法关闭: $($p.ProcessName) - 请手动关闭" -ForegroundColor Red
        }
    }
} else {
    Write-Host "  ProxyBridge 未运行 (或进程名不同,请手动确认已关闭)" -ForegroundColor DarkYellow
    Write-Host "  ※ 如果 ProxyBridge 还在运行,请手动关闭它!" -ForegroundColor Yellow
}
Write-Host ""

# ===== Step 3: 开启系统代理 =====
Write-Host "[Step 3] 设置系统代理为 ${proxyAddr}..." -ForegroundColor Yellow
$regPath = "HKCU:\Software\Microsoft\Windows\CurrentVersion\Internet Settings"

# 备份当前设置
$currentProxyEnable = (Get-ItemProperty -Path $regPath).ProxyEnable
$currentProxyServer = (Get-ItemProperty -Path $regPath).ProxyServer
$currentOverride = (Get-ItemProperty -Path $regPath).ProxyOverride

Write-Host "  当前设置备份:" -ForegroundColor Gray
Write-Host "    ProxyEnable: $currentProxyEnable" -ForegroundColor Gray
Write-Host "    ProxyServer: $currentProxyServer" -ForegroundColor Gray

# 设置系统代理
try {
    Set-ItemProperty -Path $regPath -Name ProxyEnable -Value 1
    Set-ItemProperty -Path $regPath -Name ProxyServer -Value "http://${proxyAddr}"
    # 设置绕过列表 (本地地址不走代理)
    $bypass = "localhost;127.*;10.*;172.16.*;172.17.*;172.18.*;172.19.*;172.20.*;172.21.*;172.22.*;172.23.*;172.24.*;172.25.*;172.26.*;172.27.*;172.28.*;172.29.*;172.30.*;172.31.*;192.168.*;<local>"
    Set-ItemProperty -Path $regPath -Name ProxyOverride -Value $bypass
    Write-Host "  [OK] 系统代理已开启: http://${proxyAddr}" -ForegroundColor Green
} catch {
    Write-Host "  [!!] 设置系统代理失败: $_" -ForegroundColor Red
}

# 通知系统代理已更改
$signature = @'
[DllImport("wininet.dll", SetLastError=true)]
public static extern bool InternetSetOption(IntPtr hInternet, int dwOption, IntPtr lpBuffer, int lpdwBufferLength);
'@
$type = Add-Type -MemberDefinition $signature -Name WinInet -Namespace PInvoke -PassThru
$INTERNET_OPTION_SETTINGS_CHANGED = 39
$INTERNET_OPTION_REFRESH = 37
$type::InternetSetOption([IntPtr]::Zero, $INTERNET_OPTION_SETTINGS_CHANGED, [IntPtr]::Zero, 0) | Out-Null
$type::InternetSetOption([IntPtr]::Zero, $INTERNET_OPTION_REFRESH, [IntPtr]::Zero, 0) | Out-Null
Write-Host "  [OK] 系统代理设置已刷新" -ForegroundColor Green
Write-Host ""

# ===== Step 4: 设置环境变量 =====
Write-Host "[Step 4] 设置代理环境变量..." -ForegroundColor Yellow
$proxyUrl = "http://${proxyAddr}"
[System.Environment]::SetEnvironmentVariable("HTTP_PROXY", $proxyUrl, "User")
[System.Environment]::SetEnvironmentVariable("HTTPS_PROXY", $proxyUrl, "User")
[System.Environment]::SetEnvironmentVariable("ALL_PROXY", $proxyUrl, "User")
$noProxy = "localhost,127.0.0.1,::1,10.*,172.16.*,192.168.*"
[System.Environment]::SetEnvironmentVariable("NO_PROXY", $noProxy, "User")

# 也设置当前进程的环境变量
$env:HTTP_PROXY = $proxyUrl
$env:HTTPS_PROXY = $proxyUrl
$env:ALL_PROXY = $proxyUrl
$env:NO_PROXY = $noProxy

Write-Host "  [OK] HTTP_PROXY  = $proxyUrl" -ForegroundColor Green
Write-Host "  [OK] HTTPS_PROXY = $proxyUrl" -ForegroundColor Green
Write-Host "  [OK] ALL_PROXY   = $proxyUrl" -ForegroundColor Green
Write-Host "  [OK] NO_PROXY    = $noProxy" -ForegroundColor Green
Write-Host ""

# ===== Step 5: 关闭现有 Kiro 进程 =====
Write-Host "[Step 5] 关闭现有 Kiro 进程..." -ForegroundColor Yellow
$kiroProcesses = Get-Process -Name "*kiro*" -ErrorAction SilentlyContinue
if ($kiroProcesses) {
    Write-Host "  发现 $($kiroProcesses.Count) 个 Kiro 进程,正在关闭..." -ForegroundColor Cyan
    foreach ($p in $kiroProcesses) {
        try {
            Stop-Process -Id $p.Id -Force
        } catch {}
    }
    Start-Sleep -Seconds 3
    # 确认已关闭
    $remaining = Get-Process -Name "*kiro*" -ErrorAction SilentlyContinue
    if ($remaining) {
        Write-Host "  [!!] 部分 Kiro 进程未能关闭,请手动关闭后继续" -ForegroundColor Red
        pause
    } else {
        Write-Host "  [OK] 所有 Kiro 进程已关闭" -ForegroundColor Green
    }
} else {
    Write-Host "  Kiro 未运行" -ForegroundColor Green
}
Write-Host ""

# ===== Step 6: 找到并启动 Kiro =====
Write-Host "[Step 6] 启动 Kiro (带代理参数)..." -ForegroundColor Yellow

# 查找 Kiro 安装路径
$kiroPath = $null
$searchPaths = @(
    "$env:LOCALAPPDATA\Programs\Kiro\Kiro.exe",
    "$env:LOCALAPPDATA\Kiro\Kiro.exe",
    "$env:ProgramFiles\Kiro\Kiro.exe",
    "${env:ProgramFiles(x86)}\Kiro\Kiro.exe",
    "$env:APPDATA\Local\Programs\Kiro\Kiro.exe"
)

foreach ($path in $searchPaths) {
    if (Test-Path $path) {
        $kiroPath = $path
        break
    }
}

# 如果标准路径没找到,搜索注册表
if (-not $kiroPath) {
    $regKeys = @(
        "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*",
        "HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*",
        "HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\*"
    )
    foreach ($key in $regKeys) {
        $found = Get-ItemProperty -Path $key -ErrorAction SilentlyContinue | Where-Object { $_.DisplayName -match "Kiro" }
        if ($found) {
            $installDir = $found.InstallLocation
            if ($installDir -and (Test-Path "$installDir\Kiro.exe")) {
                $kiroPath = "$installDir\Kiro.exe"
                break
            }
        }
    }
}

# 最后尝试 where 命令
if (-not $kiroPath) {
    $kiroPath = (Get-Command "Kiro.exe" -ErrorAction SilentlyContinue).Source
}

if ($kiroPath) {
    Write-Host "  找到 Kiro: $kiroPath" -ForegroundColor Green
    
    # 使用代理参数启动 Kiro
    $arguments = "--proxy-server=http://${proxyAddr}"
    Write-Host "  启动参数: $arguments" -ForegroundColor Cyan
    
    try {
        Start-Process -FilePath $kiroPath -ArgumentList $arguments
        Write-Host "  [OK] Kiro 已启动 (带代理参数)" -ForegroundColor Green
    } catch {
        Write-Host "  [!!] 启动失败: $_" -ForegroundColor Red
        Write-Host "  请手动启动 Kiro,添加参数: $arguments" -ForegroundColor Yellow
    }
} else {
    Write-Host "  [!!] 未找到 Kiro 安装路径!" -ForegroundColor Red
    Write-Host "  请手动启动 Kiro,在快捷方式目标后添加:" -ForegroundColor Yellow
    Write-Host "  --proxy-server=http://${proxyAddr}" -ForegroundColor Cyan
    Write-Host ""
    Write-Host "  或者设置以下环境变量后启动 Kiro:" -ForegroundColor Yellow
    Write-Host "  HTTP_PROXY=http://${proxyAddr}" -ForegroundColor Cyan
    Write-Host "  HTTPS_PROXY=http://${proxyAddr}" -ForegroundColor Cyan
}
Write-Host ""

# ===== 完成 =====
Write-Host "============================================" -ForegroundColor Cyan
Write-Host "  完成!" -ForegroundColor Cyan
Write-Host "============================================" -ForegroundColor Cyan
Write-Host ""
Write-Host "  已执行的操作:" -ForegroundColor Green
Write-Host "    1. 验证 Clash 代理运行正常" -ForegroundColor White
Write-Host "    2. 提示关闭 ProxyBridge" -ForegroundColor White
Write-Host "    3. 开启系统代理 (http://${proxyAddr})" -ForegroundColor White
Write-Host "    4. 设置环境变量 (HTTP_PROXY/HTTPS_PROXY)" -ForegroundColor White
Write-Host "    5. 关闭已有 Kiro 进程" -ForegroundColor White
Write-Host "    6. 用 --proxy-server 参数重新启动 Kiro" -ForegroundColor White
Write-Host ""
Write-Host "  如果仍有问题,尝试:" -ForegroundColor Yellow
Write-Host "    - 在 Clash Verge 中开启 TUN 模式" -ForegroundColor Gray
Write-Host "    - 切换一个更稳定的代理节点" -ForegroundColor Gray
Write-Host "    - 检查 Clash 规则确保 *.kiro.dev *.amazonaws.com 走代理" -ForegroundColor Gray
Write-Host ""
Write-Host "  恢复原设置请运行: kiro_proxy_restore.ps1" -ForegroundColor DarkYellow
Write-Host ""
pause
