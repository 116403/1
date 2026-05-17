# Kiro IDE 代理恢复脚本
# 功能: 撤销 kiro_proxy_fix.ps1 的所有修改,恢复到使用 ProxyBridge 的状态
# 使用方法: powershell -ExecutionPolicy Bypass -File kiro_proxy_restore.ps1

Write-Host "============================================" -ForegroundColor Cyan
Write-Host "  Kiro IDE 代理设置恢复工具" -ForegroundColor Cyan
Write-Host "============================================" -ForegroundColor Cyan
Write-Host ""

# ===== 1. 关闭系统代理 =====
Write-Host "[1/3] 关闭系统代理..." -ForegroundColor Yellow
$regPath = "HKCU:\Software\Microsoft\Windows\CurrentVersion\Internet Settings"
try {
    Set-ItemProperty -Path $regPath -Name ProxyEnable -Value 0
    Write-Host "  [OK] 系统代理已关闭" -ForegroundColor Green
} catch {
    Write-Host "  [!!] 关闭系统代理失败: $_" -ForegroundColor Red
}

# 通知系统
$signature = @'
[DllImport("wininet.dll", SetLastError=true)]
public static extern bool InternetSetOption(IntPtr hInternet, int dwOption, IntPtr lpBuffer, int lpdwBufferLength);
'@
$type = Add-Type -MemberDefinition $signature -Name WinInet -Namespace PInvoke -PassThru -ErrorAction SilentlyContinue
if ($type) {
    $type::InternetSetOption([IntPtr]::Zero, 39, [IntPtr]::Zero, 0) | Out-Null
    $type::InternetSetOption([IntPtr]::Zero, 37, [IntPtr]::Zero, 0) | Out-Null
}
Write-Host ""

# ===== 2. 清除代理环境变量 =====
Write-Host "[2/3] 清除代理环境变量..." -ForegroundColor Yellow
[System.Environment]::SetEnvironmentVariable("HTTP_PROXY", $null, "User")
[System.Environment]::SetEnvironmentVariable("HTTPS_PROXY", $null, "User")
[System.Environment]::SetEnvironmentVariable("ALL_PROXY", $null, "User")
[System.Environment]::SetEnvironmentVariable("NO_PROXY", $null, "User")
Write-Host "  [OK] 已清除 HTTP_PROXY, HTTPS_PROXY, ALL_PROXY, NO_PROXY" -ForegroundColor Green
Write-Host ""

# ===== 3. 提示 =====
Write-Host "[3/3] 恢复完成" -ForegroundColor Yellow
Write-Host ""
Write-Host "  已恢复的设置:" -ForegroundColor Green
Write-Host "    - 系统代理: 已关闭" -ForegroundColor White
Write-Host "    - 环境变量: 已清除" -ForegroundColor White
Write-Host ""
Write-Host "  接下来请:" -ForegroundColor Yellow
Write-Host "    1. 重新启动 ProxyBridge (如需要)" -ForegroundColor White
Write-Host "    2. 正常启动 Kiro (不带额外参数)" -ForegroundColor White
Write-Host ""
pause
