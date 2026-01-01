# Nanomouse 拼音输入法 - Windows 安装脚本
# 适用于小狼毫 (Weasel)
# 使用方法：右键以管理员身份运行 PowerShell，然后执行此脚本

$ErrorActionPreference = "Stop"

Write-Host "🐭 Nanomouse 拼音输入法安装脚本" -ForegroundColor Cyan
Write-Host "================================" -ForegroundColor Cyan

$RimeDir = "$env:APPDATA\Rime"
$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$SharedDir = Join-Path (Split-Path -Parent $ScriptDir) "shared"

# 检查小狼毫是否安装
$WeaselPath = "C:\Program Files (x86)\Rime\weasel-*"
$WeaselInstalled = Test-Path $WeaselPath

if (-not $WeaselInstalled) {
    # 尝试其他可能的安装路径
    $WeaselPath = "C:\Program Files\Rime\weasel-*"
    $WeaselInstalled = Test-Path $WeaselPath
}

if (-not $WeaselInstalled) {
    Write-Host "未检测到小狼毫输入法" -ForegroundColor Red
    Write-Host "请先从 https://rime.im/download/ 下载安装小狼毫"
    exit 1
}

# 检查 Rime 配置目录
if (-not (Test-Path $RimeDir)) {
    Write-Host "创建 Rime 配置目录: $RimeDir" -ForegroundColor Yellow
    New-Item -ItemType Directory -Path $RimeDir -Force | Out-Null
}

# 复制配置文件
Write-Host "复制配置文件..." -ForegroundColor Green
Copy-Item "$SharedDir\default.custom.yaml" -Destination $RimeDir -Force
Copy-Item "$SharedDir\luna_pinyin_simp.custom.yaml" -Destination $RimeDir -Force

Write-Host ""
Write-Host "配置文件已复制到 $RimeDir" -ForegroundColor Green
Write-Host ""

# 查找 WeaselDeployer
$DeployerPath = Get-ChildItem "C:\Program Files (x86)\Rime" -Recurse -Filter "WeaselDeployer.exe" -ErrorAction SilentlyContinue | Select-Object -First 1

if ($DeployerPath) {
    Write-Host "正在重新部署 Rime..." -ForegroundColor Yellow
    Start-Process -FilePath $DeployerPath.FullName -ArgumentList "/deploy" -Wait
} else {
    Write-Host "请手动右键任务栏输入法图标 -> 重新部署" -ForegroundColor Yellow
}

Write-Host ""
Write-Host "安装完成！" -ForegroundColor Green
Write-Host ""
Write-Host "功能说明："
Write-Host "  - 用 nn 代替 ng（后鼻音）"
Write-Host "  - 用 vn 代替 uan"
Write-Host "  - 用 vnn 代替 uang"
Write-Host ""
Write-Host "测试方法："
Write-Host "  输入 'dann' 应该能看到 '当' 等候选词"
Write-Host "  输入 'gvn' 应该能看到 '关' 等候选词"
Write-Host ""
Write-Host "按任意键退出..."
$null = $Host.UI.RawUI.ReadKey("NoEcho,IncludeKeyDown")
