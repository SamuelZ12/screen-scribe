# ScreenScribe Windows

使用中文沟通。独立 Windows 项目，保留父目录 macOS 源码、签名、凭据和构建不动。

- Electron 主进程负责所有文件、凭据、截图、剪贴板、快捷键和识别网络请求。
- 渲染器 sandbox/contextIsolation 开启、nodeIntegration 关闭，严格本地 CSP，无远程资源。
- 不读取或迁移本机 Mac 版 Keychain、偏好、历史或真实账单。不把任何 API Key 写源码、普通设置、日志或测试。
- 只有明确框选/导入/粘贴/连接测试触发图片请求；无后台截图、剪贴板监听或计费请求重试。
- 官方 usage 查询仅返回图片用量；总剩余为用户填写账单快照的保守估算，每次发送前扣一、每五次完成后校准，不回涨、不重复扣。
- 不自动执行生成 TeX、下载运行模型代码或随意打开外部 URL。
- 所有 Windows 结果按真实证据描述，不能把 Mac 演示/Mock 识别说成 Windows 实机通过。
- 测试 `npm test`；打包 `npm run dist:win`。依赖版本固定，包含 lockfile。
