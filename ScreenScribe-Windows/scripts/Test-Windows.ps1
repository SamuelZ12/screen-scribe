[CmdletBinding()]
param([string]$Exe = "$env:LOCALAPPDATA\Programs\ScreenScribe\ScreenScribe.exe")
$ErrorActionPreference = 'Stop'
if (-not (Test-Path -LiteralPath $Exe)) { throw '未找到应用，请通过 -Exe 指定已安装的 ScreenScribe.exe 完整路径。' }
Write-Host '开始离线 Windows 自检：只使用合成凭据和内置公开公式，不发送 API 请求。'
$process = Start-Process -FilePath $Exe -ArgumentList '--platform-self-test' -Wait -PassThru
$result = Join-Path $env:TEMP 'ScreenScribe-Windows-self-test.json'
if (-not (Test-Path -LiteralPath $result)) { throw '未生成自检报告，请核对应用版本。' }
Get-Content -LiteralPath $result
if ($process.ExitCode -ne 0) { throw '自检有未通过项，报告不包含你的 API Key 或桌面图片，可供定位。' }
Write-Host '离线原生自检通过。请继续完成首次配置、实际公式框选和重启后的人工验收。'
