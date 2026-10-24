# ScreenScribe for Windows V0.1

这是在独立目录中实现的 Windows 移植版，面向普通 Intel / AMD 电脑上的 **Windows 10 / 11 x64**。沿用 Mac 版的单面板交互：框选公式，识别为可编辑的 LaTeX，原图、预览和复制格式放在一起。父目录中的 Mac 源码、固定签名、凭据与构建保持原样。

已生成约 108 MB 的安装包：[`ScreenScribe-Windows-0.1.0-x64-Setup.exe`](dist/ScreenScribe-Windows-0.1.0-x64-Setup.exe)。目前已完成自动测试、Mac 上的隔离界面桥接检查和 Windows 包静态检查，**Windows 实机安装、DPAPI、截图和界面验收尚未完成**。当前产物保存在本机，尚未推送远端或发布 Windows Release。

## 使用

1. 在 Windows 上运行安装包，按向导安装。默认按当前用户安装，不要求管理员权限；不会要求关闭防病毒或其他系统保护。
2. 从桌面或开始菜单启动，在任务栏通知区域点击 ScreenScribe 图标。默认驻留托盘，收起面板不会退出程序。
3. 在面板内的设置中填写**你自己的** Mathpix App ID 和 API Key，保存后测试连接。测试使用内置公开公式图，会发送一次识别请求，可能计费。
4. 按 **Ctrl+Shift+L** 直接框选公式；松开鼠标开始识别，Esc 或鼠标右键取消。也可导入本地图片，或先按 Win+Shift+S 截图，再按 **Ctrl+Shift+V** 粘贴识别。

安装器尚未使用付费代码签名证书，Windows 可能显示发布者未验证。请仅使用来源可信且校验一致的安装包。

## 功能

- **OCR / Data / Original**：离线公式排版预览、源码编辑与原图对照。四行紧凑复制区支持纯 LaTeX、`$…$`、`$$…$$` 和 `equation` 环境。
- **Mathpix 与视觉模型**：Mathpix 用于公式；也可自行配置兼容 OpenAI 接口、支持图片输入的模型及 HTTPS 地址。API 费用由对应服务收取。
- **实验性费曼图**：视觉模型可返回图结构及 TikZ 源码，结果需要人工核查；程序不会自动执行或编译生成的 TeX。
- **同一面板中的设置与历史**：无需额外设置窗口；可固定面板、更改快捷键、编辑源码和导航、删除历史。最多保留 50 条，默认不把原图写入历史文件。
- **额度显示**：展示 Mathpix 本月图片用量、手工月上限和账单快照推算的总剩余次数。每次发送前本地先扣 1 次，每完成 5 次请求查询官方用量校准，重启保留计数。

## 额度怎样计算

Mathpix 的官方 usage 查询提供图片用量，不能直接给出账户实时余额。设置里的“总剩余”因此是**保守估算**：自行填写 Billing 余额、待结算用量、每张单价与快照时间。余额和待结算金额按美元分输入，单价最多支持 6 位小数。

计算以整数微美元进行，额外预留 $0.01，将基础可覆盖次数向下取整；初次官方用量校准还会核查金额精度差额。随后每次实际发送前扣 1 次，失败和手动重试也保守计入；第五次完成后查询官方用量，以累计扣减的较大值校准，避免重复扣除和剩余回涨。跨月或记录异常时，需更新 Billing 快照才能继续显示总剩余。

其他设备的图片消费依赖官方用量延迟校准，PDF、其他接口和不同单价的消费需要重新更新快照。此数字不是服务端承诺的可用次数，也不会替代 Mathpix 控制台账单。

## 开发与构建

需要 Node.js 22 或更新版本及 npm。正式程序仅允许在 Windows 运行；Mac 上可使用隔离演示或 smoke 模式。进入此独立目录后执行：

```powershell
npm ci
npm test
npm run smoke
npm run dist:win
```

- `npm ci`：按锁文件安装固定依赖，首次需要下载 Electron 和构建工具。
- `npm test`：运行服务、存储、额度、截图坐标与控制器测试，不使用真实 API 凭据。
- `npm run smoke`：启动 Electron 并检查本地渲染器桥接；使用内存存储，不截图、不联网、不读取真实凭据。运行宿主是 Mac 时，只能证明 Mac Electron 的桥接可用。
- `npm run dist:win`：生成 x64 NSIS 安装包，输出到 `dist/ScreenScribe-Windows-0.1.0-x64-Setup.exe`，不会自动发布。
- `npm run demo`：打开隔离演示界面；示例源码不是一次真实识别结果。
- `node scripts/verify-package.cjs`：静态检查 `dist/win-unpacked` 的 PE 架构、ASAR 资源、隔离设置与私有文件排除情况；不能替代 Windows 实机验证。

本次验证记录为：63 项测试通过；Mac Electron 的 `--smoke-test` 桥接通过；x64 NSIS 安装包构建成功；145 项包静态检查通过，报告仍明确标记 `windowsRuntimeVerified=false`。这些结果不证明 Windows GUI、DPAPI、混合 DPI 多屏截图或安装/卸载已实机通过。

## 数据与安全边界

正式版数据位于当前用户的 `%APPDATA%\ScreenScribe-Windows`。凭据通过 Electron `safeStorage` 调用 Windows DPAPI 加密后写盘；加密不可用时拒绝保存，普通设置、历史和日志不保存 API Key。保存成功后界面的密钥输入框清空，状态快照只返回“已保存/未保存”。

DPAPI 主要保护当前 Windows 登录用户的数据，**不能阻止同一用户权限下所有其他进程获取凭据**，也不是对已受控账户的隔离边界。源码、历史、设置和账单估算数据本身不是加密保险箱；不要把敏感截图保存在不可信账户或共享目录中。

渲染器启用 sandbox 与 context isolation，关闭 Node 集成；只加载本地资源，通过受限桥接调用主进程。KaTeX 与字体全部随包携带，预览无需 CDN。只有你主动框选、导入、粘贴、重新识别或测试连接时才发送图片；无后台截图、剪贴板监听或计费请求自动重试。框选时完整屏幕画面只在本机用于选区交互，发送给识别服务的是所选裁剪图。

架构详见 [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md)，桥接字段详见 [docs/CONTRACT.md](docs/CONTRACT.md)。项目采用 MIT 许可，第三方组件见 [THIRD-PARTY-NOTICES.md](THIRD-PARTY-NOTICES.md)。
