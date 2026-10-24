# ScreenScribe V0.1

原生 macOS 菜单栏科研截图工具：直接框选公式，通过自己的识别 API 转成可编辑、可复制的 LaTeX，并在同一面板查看原图和排版预览。

## 主要功能

- **直接框选识别**：支持全局快捷键、图片导入和粘贴截图；启动后常驻菜单栏，结果、历史和设置集中在一个气泡面板。
- **公式与源码精修**：Mathpix 公式识别，紧凑 LaTeX 输出，离线 KaTeX 预览，原图对照；支持纯公式、行内公式、独立公式及 equation 环境复制。
- **额度估算**：显示本月图片用量和账单快照可覆盖的总剩余估算；每次有效请求先扣一次，每完成五次查询官方用量校准，重启保留计数。按保守费用预留计算，统计延迟不会让已扣额度回涨。
- **本地历史**：编辑保存、复制、删除和清空；最多 50 条、约 25 MB，原图持久化可选。
- **可选视觉后端**：支持用户配置 OpenAI 兼容视觉 API，提供公式识别和实验性费曼图 → TikZ；保留 Apple Vision 离线文字 OCR 与原有 Gemini 工具。

## 架构简述

采用 **Swift / SwiftUI / AppKit**：AppKit 管理菜单栏、单个 NSPopover 和框选层；ScreenCaptureKit 负责现代 macOS 截图，Carbon 注册全局快捷键。统一识别协议连接 Mathpix 与 OpenAI 兼容视觉后端，工作区负责原图、源码编辑和历史，内置 KaTeX 通过 WKWebView 离线排版。

API 凭据存入 macOS Keychain。本地固定签名构建通过不可变嵌入式 XPC 组件保存凭据，并双向校验代码签名；设置和额度计数在本机保存。网络只发送用户选中的图片或明确触发的测试图，无自动重试；模型返回的 TeX 不会自动执行。

## 安装与使用

1. 下载本 Release 的 **macOS Apple Silicon / arm64** 应用包，解压后将 ScreenScribe 放入 Applications。
2. 打开应用，点击菜单栏图标，在设置中填写并保存自己的 Mathpix App ID / App Key，或兼容视觉 API 配置。应用不包含共享密钥。
3. 首次直接框选需按 macOS 提示授予 Screen Recording 权限。默认公式识别快捷键为 **⌘⇧L**。
4. 若需总剩余估算，在额度设置中保存 Billing 余额、待结算金额、单价和观察时间；之后可更新快照。

最低要求 **macOS 14**；本次实际验收为 Apple Silicon / macOS 26。应用使用固定本地开发证书签名，**未使用 Apple Developer ID 分发签名，未公证**，首次启动可能需要系统确认。无需安装或信任开发者的签名私钥。

## 已验证与限制

15 组自动回归通过；已实测直接框选、真实 Mathpix 公式识别、更新和重启后读取配置、逐次扣减及第五次用量校准。详细范围见 [测试说明](https://github.com/pionplusminus/screen-scribe/blob/v0.1/docs/TESTING.md)。

总剩余是账单快照估算，公开 OCR Key 用量接口不能自动读取实时 Billing 金额；其他消费或跨月需要更新快照。多屏、混合缩放和全屏 Space 尚未完成实测；视觉后端与费曼图语义仍需人工核查，本版不编译 TikZ，也不提供 PDF 批处理。

基于 ScreenScribe / TextGrabber2 扩展，采用 MIT 许可证；保留原作者声明，离线 KaTeX 的许可见 `THIRD-PARTY-NOTICES.md`。
