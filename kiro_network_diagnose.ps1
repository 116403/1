# Kiro IDE 网络诊断脚本 (Clash Verge + ProxyBridge 环境)
# 在 PowerShell 中以管理员权限运行: powershell -ExecutionPolicy Bypass -File kiro_network_diagnose.ps1

$ErrorActionPreference = "SilentlyContinue"

Write-Host "============================================" -ForegroundColor Cyan
Write-Host "  Kiro IDE 网络诊断工具" -ForegroundColor Cyan
Write-Host "  (Clash Verge + ProxyBridge 环境)" -ForegroundColor Cyan
Write-Host "============================================" -ForegroundColor Cyan
Write-Host "  诊断时间: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')" -ForegroundColor Gray
Write-Host ""

$results = @()

# ===== 1. 检查进程状态 =====
Write-Host "[1/9] 检查相关进程状态..." -ForegroundColor Yellow

# Kiro
$kiroProcess = Get-Process -Name "*kiro*" -ErrorAction SilentlyContinue
if ($kiroProcess) {
    foreach ($p in $kiroProcess) {
        Write-Host "  [OK] Kiro 运行中: $($p.ProcessName) (PID: $($p.Id))" -ForegroundColor Green
    }
} else {
    Write-Host "  [!!] Kiro 未运行" -ForegroundColor Red
    $results += "Kiro 未运行"
}

# Clash/Mihomo
$clashProcess = Get-Process -Name "*clash*", "*mihomo*", "*verge*" -ErrorAction SilentlyContinue
if ($clashProcess) {
    foreach ($p in $clashProcess) {
        Write-Host "  [OK] 代理核心运行中: $($p.ProcessName) (PID: $($p.Id))" -ForegroundColor Green
    }
} else {
    Write-Host "  [!!] 未检测到 Clash/Mihomo/Verge 进程" -ForegroundColor Red
    $results += "代理核心未运行"
}

# ProxyBridge
$bridgeProcess = Get-Process -Name "*proxybridge*", "*proxy*bridge*" -ErrorAction SilentlyContinue
if ($bridgeProcess) {
    foreach ($p in $bridgeProcess) {
        Write-Host "  [OK] ProxyBridge 运行中: $($p.ProcessName) (PID: $($p.Id))" -ForegroundColor Green
    }
} else {
    Write-Host "  [??] 未检测到 ProxyBridge 进程 (可能进程名不同)" -ForegroundColor DarkYellow
    # 尝试更广泛搜索
    $allProxy = Get-Process | Where-Object { $_.ProcessName -match "bridge|proxy|redirect|netch|proxifier" }
    if ($allProxy) {
        Write-Host "  检测到可能的代理转发工具:" -ForegroundColor Gray
        foreach ($p in $allProxy) {
            Write-Host "    - $($p.ProcessName) (PID: $($p.Id))" -ForegroundColor Gray
        }
    }
}
Write-Host ""

# ===== 2. 检查端口状态 =====
Write-Host "[2/9] 检查 Clash 代理端口 (7897)..." -ForegroundColor Yellow
try {
    $tcpTest = Test-NetConnection -ComputerName 127.0.0.1 -Port 7897 -WarningAction SilentlyContinue
    if ($tcpTest.TcpTestSucceeded) {
        Write-Host "  [OK] 127.0.0.1:7897 端口可达" -ForegroundColor Green
    } else {
        Write-Host "  [!!] 127.0.0.1:7897 端口不可达!" -ForegroundColor Red
        $results += "Clash 端口 7897 不可达"
    }
} catch {
    # 备用方法
    $portCheck = netstat -ano | Select-String ":7897.*LISTENING"
    if ($portCheck) {
        Write-Host "  [OK] 端口 7897 正在监听" -ForegroundColor Green
    } else {
        Write-Host "  [!!] 端口 7897 未监听!" -ForegroundColor Red
        $results += "Clash 端口 7897 未监听"
    }
}
Write-Host ""

# ===== 3. 系统代理设置 =====
Write-Host "[3/9] 检查系统代理设置..." -ForegroundColor Yellow
$proxy = Get-ItemProperty -Path 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Internet Settings' -ErrorAction SilentlyContinue
if ($proxy.ProxyEnable -eq 1) {
    Write-Host "  系统代理: 已启用" -ForegroundColor Cyan
    Write-Host "  代理地址: $($proxy.ProxyServer)" -ForegroundColor Cyan
    Write-Host "  绕过列表: $($proxy.ProxyOverride)" -ForegroundColor Gray
} else {
    Write-Host "  系统代理: 未启用 (ProxyBridge 模式下正常)" -ForegroundColor Green
}

# 环境变量
$httpProxy = $env:HTTP_PROXY
$httpsProxy = $env:HTTPS_PROXY
if ($httpProxy -or $httpsProxy) {
    Write-Host "  HTTP_PROXY: $httpProxy" -ForegroundColor Cyan
    Write-Host "  HTTPS_PROXY: $httpsProxy" -ForegroundColor Cyan
} else {
    Write-Host "  环境变量代理: 未设置 (ProxyBridge 模式下正常)" -ForegroundColor Green
}
Write-Host ""

# ===== 4. DNS 解析测试 =====
Write-Host "[4/9] DNS 解析测试..." -ForegroundColor Yellow
$domains = @(
    "ide.kiro.dev",
    "kiro.dev",
    "api.github.com",
    "cognito-idp.us-east-1.amazonaws.com",
    "execute-api.us-east-1.amazonaws.com"
)
$dnsOk = $true
foreach ($domain in $domains) {
    try {
        $dns = Resolve-DnsName -Name $domain -Type A -ErrorAction Stop -DnsOnly
        $ips = ($dns | Where-Object { $_.QueryType -eq 'A' } | Select-Object -First 2).IPAddress -join ", "
        if ($ips) {
            Write-Host "  [OK] $domain -> $ips" -ForegroundColor Green
        } else {
            $cname = ($dns | Where-Object { $_.QueryType -eq 'CNAME' } | Select-Object -First 1).NameHost
            Write-Host "  [OK] $domain -> CNAME: $cname" -ForegroundColor Green
        }
    } catch {
        Write-Host "  [!!] $domain -> 解析失败!" -ForegroundColor Red
        $dnsOk = $false
        $results += "DNS 解析失败: $domain"
    }
}
Write-Host ""

# ===== 5. 直连测试 (不走代理) =====
Write-Host "[5/9] 直连测试 (绕过代理)..." -ForegroundColor Yellow
Write-Host "  注意: ProxyBridge 环境下此测试在 PowerShell 中不受 ProxyBridge 影响" -ForegroundColor Gray

$testUrls = @(
    @{ url = "https://ide.kiro.dev"; name = "Kiro IDE 主站" },
    @{ url = "https://api.github.com"; name = "GitHub API" },
    @{ url = "https://cognito-idp.us-east-1.amazonaws.com"; name = "AWS Cognito (认证)" }
)

foreach ($item in $testUrls) {
    try {
        $sw = [System.Diagnostics.Stopwatch]::StartNew()
        $response = Invoke-WebRequest -Uri $item.url -Method Head -TimeoutSec 15 -UseBasicParsing -NoProxy -ErrorAction Stop
        $sw.Stop()
        Write-Host "  [OK] $($item.name) - 成功 ($($sw.ElapsedMilliseconds)ms)" -ForegroundColor Green
    } catch {
        $errMsg = $_.Exception.Message
        if ($errMsg -match "timed out|超时") {
            Write-Host "  [!!] $($item.name) - 超时! (可能需要代理)" -ForegroundColor Red
        } elseif ($errMsg -match "403|401|400") {
            Write-Host "  [OK] $($item.name) - 可达 (返回鉴权错误,连接正常)" -ForegroundColor Green
        } else {
            Write-Host "  [!!] $($item.name) - 失败: $($errMsg.Substring(0, [Math]::Min(80, $errMsg.Length)))" -ForegroundColor Red
        }
    }
}
Write-Host ""

# ===== 6. 代理连接测试 =====
Write-Host "[6/9] 通过 Clash 代理测试 (127.0.0.1:7897)..." -ForegroundColor Yellow
$proxyAddr = "http://127.0.0.1:7897"

foreach ($item in $testUrls) {
    try {
        $sw = [System.Diagnostics.Stopwatch]::StartNew()
        $response = Invoke-WebRequest -Uri $item.url -Method Head -TimeoutSec 15 -Proxy $proxyAddr -UseBasicParsing -ErrorAction Stop
        $sw.Stop()
        Write-Host "  [OK] $($item.name) (via proxy) - 成功 ($($sw.ElapsedMilliseconds)ms)" -ForegroundColor Green
    } catch {
        $errMsg = $_.Exception.Message
        if ($errMsg -match "timed out|超时") {
            Write-Host "  [!!] $($item.name) (via proxy) - 超时!" -ForegroundColor Red
            $results += "代理连接超时: $($item.name)"
        } elseif ($errMsg -match "Unable to connect|无法连接") {
            Write-Host "  [!!] $($item.name) (via proxy) - 代理不可达!" -ForegroundColor Red
            $results += "代理端口不可达"
        } elseif ($errMsg -match "403|401|400") {
            Write-Host "  [OK] $($item.name) (via proxy) - 可达 (鉴权错误,连接正常)" -ForegroundColor Green
        } else {
            Write-Host "  [!!] $($item.name) (via proxy) - 失败: $($errMsg.Substring(0, [Math]::Min(80, $errMsg.Length)))" -ForegroundColor Red
            $results += "代理连接失败: $($item.name)"
        }
    }
}
Write-Host ""

# ===== 7. WebSocket/长连接测试 =====
Write-Host "[7/9] 测试长连接/流式连接 (模拟执行操作)..." -ForegroundColor Yellow
Write-Host "  Kiro 执行操作可能使用 SSE/WebSocket 长连接" -ForegroundColor Gray

# 测试一个较大的下载来模拟长连接
$longTestUrl = "https://api.github.com/repos/aws/aws-cli/releases/latest"
try {
    $sw = [System.Diagnostics.Stopwatch]::StartNew()
    $response = Invoke-WebRequest -Uri $longTestUrl -TimeoutSec 30 -Proxy $proxyAddr -UseBasicParsing -ErrorAction Stop
    $sw.Stop()
    $size = $response.Content.Length
    Write-Host "  [OK] 较大响应测试 - 成功 (大小: ${size}B, 耗时: $($sw.ElapsedMilliseconds)ms)" -ForegroundColor Green
} catch {
    $errMsg = $_.Exception.Message
    if ($errMsg -match "403") {
        Write-Host "  [OK] 较大响应测试 - 可达 (GitHub 限流,连接本身正常)" -ForegroundColor Green
    } else {
        Write-Host "  [!!] 较大响应测试 - 失败: 可能长连接被中断" -ForegroundColor Red
        $results += "长连接测试失败"
    }
}

# 测试直连长连接
try {
    $sw = [System.Diagnostics.Stopwatch]::StartNew()
    $response = Invoke-WebRequest -Uri $longTestUrl -TimeoutSec 30 -NoProxy -UseBasicParsing -ErrorAction Stop
    $sw.Stop()
    Write-Host "  [OK] 直连长连接测试 - 成功 (耗时: $($sw.ElapsedMilliseconds)ms)" -ForegroundColor Green
} catch {
    $errMsg = $_.Exception.Message
    if ($errMsg -match "403") {
        Write-Host "  [OK] 直连长连接测试 - 可达" -ForegroundColor Green
    } else {
        Write-Host "  [!!] 直连长连接测试 - 失败" -ForegroundColor Red
    }
}
Write-Host ""

# ===== 8. 检查防火墙规则 =====
Write-Host "[8/9] 检查 Windows 防火墙 Kiro 相关规则..." -ForegroundColor Yellow
try {
    $fwRules = Get-NetFirewallRule -ErrorAction Stop | Where-Object {
        $_.DisplayName -match "kiro" -or $_.DisplayName -match "Kiro"
    }
    if ($fwRules) {
        foreach ($rule in $fwRules) {
            $action = if ($rule.Action -eq "Allow") { "允许" } else { "阻止" }
            $direction = if ($rule.Direction -eq "Inbound") { "入站" } else { "出站" }
            $enabled = if ($rule.Enabled -eq "True") { "启用" } else { "禁用" }
            Write-Host "  规则: $($rule.DisplayName) | $direction | $action | $enabled" -ForegroundColor Cyan
            if ($rule.Action -eq "Block" -and $rule.Enabled -eq "True") {
                Write-Host "  [!!] 发现阻止 Kiro 的防火墙规则!" -ForegroundColor Red
                $results += "防火墙阻止了 Kiro"
            }
        }
    } else {
        Write-Host "  未找到 Kiro 相关的防火墙规则 (正常)" -ForegroundColor Green
    }
} catch {
    Write-Host "  无法读取防火墙规则 (需要管理员权限)" -ForegroundColor DarkYellow
}
Write-Host ""

# ===== 9. Clash 连接日志检查 =====
Write-Host "[9/9] 尝试查询 Clash API 最近连接..." -ForegroundColor Yellow
try {
    # Clash 默认 API 端口通常是 9090
    $clashApi = "http://127.0.0.1:9090/connections"
    $connections = Invoke-RestMethod -Uri $clashApi -TimeoutSec 5 -ErrorAction Stop
    $kiroConns = $connections.connections | Where-Object {
        $_.metadata.process -match "kiro" -or $_.metadata.processPath -match "kiro"
    }
    if ($kiroConns) {
        Write-Host "  发现 Kiro 的活跃连接:" -ForegroundColor Cyan
        foreach ($conn in $kiroConns | Select-Object -First 5) {
            $host_ = $conn.metadata.host
            $chain = $conn.chains -join " -> "
            Write-Host "    目标: $host_ | 链路: $chain" -ForegroundColor Gray
        }
    } else {
        Write-Host "  Clash API 可访问,但无 Kiro 活跃连接" -ForegroundColor DarkYellow
    }
} catch {
    # 尝试其他端口
    try {
        $clashApi = "http://127.0.0.1:9097/connections"
        $null = Invoke-RestMethod -Uri $clashApi -TimeoutSec 3 -ErrorAction Stop
        Write-Host "  Clash API 在端口 9097" -ForegroundColor Gray
    } catch {
        Write-Host "  无法连接 Clash API (端口可能不是默认的 9090)" -ForegroundColor DarkYellow
        Write-Host "  建议手动查看 Clash Verge 的日志/连接页面" -ForegroundColor Gray
    }
}
Write-Host ""

# ===== 总结 =====
Write-Host "============================================" -ForegroundColor Cyan
Write-Host "  诊断总结" -ForegroundColor Cyan
Write-Host "============================================" -ForegroundColor Cyan
Write-Host ""

if ($results.Count -eq 0) {
    Write-Host "  基础网络检查均通过!" -ForegroundColor Green
    Write-Host ""
    Write-Host "  问题可能在于:" -ForegroundColor Yellow
    Write-Host "  1. ProxyBridge 对 Kiro 的长连接/流式请求处理有问题" -ForegroundColor White
    Write-Host "  2. Clash 规则中某些 Kiro 需要的域名走了不稳定的节点" -ForegroundColor White
    Write-Host "  3. 代理节点本身不稳定,导致执行操作超时" -ForegroundColor White
    Write-Host ""
    Write-Host "  建议操作:" -ForegroundColor Yellow
    Write-Host "  A. 在 Clash Verge 日志页面观察 Kiro 执行操作时的请求" -ForegroundColor Gray
    Write-Host "  B. 尝试切换 Clash 节点后重试" -ForegroundColor Gray
    Write-Host "  C. 尝试将 Kiro 从 ProxyBridge 移除,改用系统代理模式测试" -ForegroundColor Gray
    Write-Host "  D. 在 ProxyBridge 中将 Kiro 规则的动作改为直连,测试是否直连可用" -ForegroundColor Gray
} else {
    Write-Host "  发现以下问题:" -ForegroundColor Red
    foreach ($r in $results) {
        Write-Host "  - $r" -ForegroundColor Red
    }
    Write-Host ""
    Write-Host "  建议修复步骤:" -ForegroundColor Yellow
    if ($results -match "端口") {
        Write-Host "  -> 重启 Clash Verge,确保代理核心正常启动" -ForegroundColor Gray
    }
    if ($results -match "DNS") {
        Write-Host "  -> 在 Clash 中启用 DNS 覆写,或手动设置 DNS 为 8.8.8.8" -ForegroundColor Gray
    }
    if ($results -match "超时|失败") {
        Write-Host "  -> 切换 Clash 代理节点,选择延迟低的节点" -ForegroundColor Gray
        Write-Host "  -> 或尝试让 Kiro 直连 (从 ProxyBridge 中移除 Kiro.exe)" -ForegroundColor Gray
    }
    if ($results -match "防火墙") {
        Write-Host "  -> 在 Windows 防火墙中允许 Kiro.exe 的出站连接" -ForegroundColor Gray
    }
}

Write-Host ""
Write-Host "============================================" -ForegroundColor Cyan
Write-Host "  额外建议 (ProxyBridge 特有)" -ForegroundColor Cyan
Write-Host "============================================" -ForegroundColor Cyan
Write-Host ""
Write-Host "  ProxyBridge 的进程规则设置建议:" -ForegroundColor Yellow
Write-Host "  - 应用程序: Kiro.exe" -ForegroundColor White
Write-Host "  - 目标主机: * (所有)" -ForegroundColor White
Write-Host "  - 目标端口: * (所有)" -ForegroundColor White  
Write-Host "  - 动作: 代理" -ForegroundColor White
Write-Host ""
Write-Host "  当前你的配置是目标主机 *127.0.0.1, 端口 7897*" -ForegroundColor Red
Write-Host "  这意味着只有 Kiro 到 127.0.0.1:7897 的流量才走代理" -ForegroundColor Red
Write-Host "  而 Kiro 到外部服务器的实际请求可能没被 ProxyBridge 拦截!" -ForegroundColor Red
Write-Host ""
Write-Host "  修改建议:" -ForegroundColor Green
Write-Host "  把目标主机改为 * ,目标端口改为 * 或留空" -ForegroundColor Green
Write-Host "  这样 Kiro 的所有出站流量都会通过 Clash 代理" -ForegroundColor Green
Write-Host ""
Write-Host "按任意键退出..." -ForegroundColor Gray
$null = $Host.UI.RawUI.ReadKey("NoEcho,IncludeKeyDown")
