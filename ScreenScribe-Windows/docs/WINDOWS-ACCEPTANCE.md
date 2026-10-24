# 普通 Windows 电脑验收

安装 `dist/ScreenScribe-Windows-0.1.0-x64-Setup.exe`。选择当前用户目录，应用不请求管理员提权。首次未保存凭据会显示同一面板，之后可从任务栏通知区域或再次启动程序打开。

可选离线自检（在 Windows PowerShell 中执行已知安装路径的应用，不需要下载测试工具）：

```powershell
& "$env:LOCALAPPDATA\Programs\ScreenScribe\ScreenScribe.exe" --platform-self-test
Get-Content "$env:TEMP\ScreenScribe-Windows-self-test.json"
```

若自行选择了安装目录，请替换路径。源码用户可运行 `scripts/Test-Windows.ps1 -Exe '完整路径\ScreenScribe.exe'`。这一步只使用合成凭据、公开公式和彩色定位窗，无识别 API 请求；报告不含真实密钥或桌面图片。

人工检查：

- 填写自己的 API，保存后退出重启，凭据仍标记已保存，Key 不显示在普通设置、历史或日志里。
- 打开公开公式，Ctrl+Shift+L 直接拖选；Original 与选区一致。Esc 取消不产生识别请求。
- 本机若多屏，请分别测试每块屏及不同缩放。每次只框一块屏幕；跨屏拖动在边界截断。
- 粘贴 Win+Shift+S 图片、导入 PNG/JPEG；核对 LaTeX、编辑保存、四种复制、原图复制和历史删除。
- 填写 Billing 余额、待结算、单价和时间；连续五次明确识别，逐张扣减，第五次更新官方用量；重启保留。
- 切换视觉 API 后单独保存该端点 Key，其他端点不共用；费曼图须人工核对原图，软件不执行生成 TeX。
- 关闭原图持久化后，新历史只保存文本。清理/卸载个人数据须由用户自己决定，卸载器默认保留配置。

有失败时说明发生在哪一步；不需要公开 API Key、完整私人桌面或账单卡片信息。
