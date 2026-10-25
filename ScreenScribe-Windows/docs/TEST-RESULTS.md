# Windows V0.1 验证结果

目标：普通 Intel / AMD x64 的 Windows 10/11。当前软件是独立 Windows 实现，Mac 版源代码、签名、凭据和应用均不变。

## 最终构建与安装器

成功运行：[CI run 40109506792](https://github.com/pionplusminus/screen-scribe/actions/runs/40109506792)，job `120918094190`。安装器对应源码提交 `ee903fb0d781bc5d7a3bf47a589e9c98b6cb9c0f`；运行环境为 **Windows Server 2025（10.0.26100）x64**。没有据此声称 Windows 10 与 11 客户端均已人工实测。

| 项目 | 实际结果 |
|---|---|
| 语法与构建输入检查 | 通过 |
| 自动回归 | 本机 68 项通过；Windows CI 67 项通过、1 项符号链接测试跳过 |
| Windows sandbox 渲染器与 IPC smoke | 通过，必须收到版本匹配的桥接报告 |
| Windows 原生自检 | 14 项通过 |
| x64 NSIS 构建 | 通过 |
| 包静态检查 | 151 项通过 |
| 静默安装 | 当前用户安装成功 |
| 已安装副本原生自检 | 14 项通过 |
| 卸载隔离验收副本 | 成功 |

最终交付文件直接取自该轮 CI artifact `12566605133`，下载的 ZIP 已核对 GitHub 提供的 SHA-256。未交付修复前的本地旧包。

- 安装器：[ScreenScribe-Windows-0.1.0-x64-Setup.exe](../dist/ScreenScribe-Windows-0.1.0-x64-Setup.exe)
- 文件大小：113,582,952 字节（约 108 MiB）。
- [SHA-256 校验文件](../dist/ScreenScribe-Windows-0.1.0-x64-Setup.exe.sha256)：`dcabd3a36982763e306857146c585c1ccbf516b6796c187790aaf64eebc86ab9`
- [交付清单](../artifacts/delivery-manifest.json)
- CI 报告：[渲染器桥接](../artifacts/ci-run-40109506792/renderer-smoke.json)、[源码原生自检](../artifacts/ci-run-40109506792/native-windows-self-test.json)、[已安装副本自检](../artifacts/ci-run-40109506792/installed-windows-self-test.json)、[包静态检查](../artifacts/ci-run-40109506792/package-verification.json)。

安装器按当前用户/asInvoker 安装，不请求管理员权限，尚未使用代码签名证书。源码在独立分支 `codex/windows-v0.1`，未合并 Mac `main`。截至 2026-10-25，Windows 内测版安装器及专用源码 ZIP 已由用户上传到与 Mac 共用的 [V0.1 Release（标签 `math`）](https://github.com/pionplusminus/screen-scribe/releases/tag/math)，公开 EXE 的 SHA-256 与本报告一致。本机交付目录保留安装器和上述报告；它们不随源码提交到 Git。

## 原生验收覆盖

`--platform-self-test` 只使用合成 DPAPI 凭据、内置公开图和唯一彩色测试窗，不连接真实识别账户，不上传桌面内容，不保存桌面缩略图。源码运行和安装后副本分别通过以下 14 项检查：

- 原生 Windows 进程、DPAPI 可用、凭据文件无明文、保存后从新凭据库重新读取、删除凭据。
- 无管理员权限注册全局快捷键、公开内置图片解码、sandbox 渲染器与 IPC、自有测试窗渲染与绘制准备。
- Windows 显示器枚举、桌面源 `display_id` 与物理显示器匹配、正式 `cropRect` 裁剪，以及结果与唯一彩色测试窗采样一致（平均色差小于 4）。

此自检独立于正式启动流程，未操作正式选区覆盖层、拖动指针、托盘或真实 OCR。它证明上述原生能力与裁剪原语，不等于完整人工框选流程验收。CI 在临时目录安装并卸载隔离副本，工作流仅有 `contents:read` 权限。

首轮原生测试发现 Electron 45 异步解密返回对象而非字符串；已通过共享 `os-crypto.cjs` 适配器提取 `result`，并新增 5 项回归测试。包校验器的 ASAR 路径读取已按 Windows 分隔符修复；完整检查保留，最终通过 151 项。失败历史与修复记录保存在本机操作日志和 `artifacts/native-ci-history.json`，未把失败轮次当作成功结果。

## 其他验证

- 自动回归使用合成账户、临时存储与 Mock HTTP，涵盖 Mathpix/视觉 API 协议与解析、失败/取消、凭据加密适配器、历史恢复、2,232 组金额组合、逐张扣减与五次校准、异步凭据/用量竞态、混合 DPI/负坐标裁剪和快捷键冲突。
- 在 Mac 的自有 Electron 演示窗口检查了 KaTeX 预览、Original、Data 编辑、保存后的历史以及同面板设置/视觉服务切换。演示仅用内存，不读 Mac 凭据、不申请录屏权限、不注册真实全局快捷键、不调用 API；这些是界面验证，不冒称 Windows 人工验收。
- 包静态检查覆盖 PE64 架构、ASAR 程序/资源/字体/许可、版本、隔离设置及私有文件排除情况。其 `windowsRuntimeVerified=false` 仅表示静态报告本身不证明运行，原生运行证据见独立报告。
- npm 官方依赖审计返回 0 个已知漏洞（当次查询）；依赖版本和完整性保存在 `package-lock.json`。

## 已知验证边界

尚未用真实 Windows 账户发送 Mathpix 或视觉服务请求，没有把 Mac 版真实 API 证据归入 Windows 结果。真实 API 需使用者自行填写密钥并主动触发；没有把 Mac 凭据迁入 Windows 项目。

正式框选界面鼠标拖动、托盘交互、Windows 10/11 客户端、多显示器混合缩放、跨屏边界、远程桌面和受保护内容仍需目标电脑人工验证。每次框选仅覆盖起始屏幕，跨屏拖动在该屏边缘截断。TikZ 为实验性重建，只做格式校验，不自动执行 TeX。总剩余为账单快照保守估算，usage 不提供实时 Billing 金额。
