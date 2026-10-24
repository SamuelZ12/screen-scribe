# ScreenScribe V0.1 · 理论物理截图识别

原生 macOS 菜单栏工具：**框选截图 → Mathpix / 用户指定视觉 API → 编辑 LaTeX 或 TikZ → 复制**。macOS 14+，Swift、SwiftUI、AppKit；保留原版 Apple Vision 离线文字 OCR、Gemini 自定义提示词工具。

本项目 V0.1 发布说明见 [Release 说明](docs/RELEASE-v0.1.md)。

本目录已从 [pionplusminus/screen-scribe](https://github.com/pionplusminus/screen-scribe) 克隆，`origin` 保留该远端。V0.1 在该仓库发布；保留上游历史与 MIT 声明。原版主要做屏幕截图、离线文字提取、Gemini 的 LaTeX/Markdown/自定义提示词提取，历史只在内存。本次在原项目上扩展，保留 Carbon 全局快捷键基础，并完善截图和识别链路。

## 直接框选与固定签名状态（2026-10-24）

已加入固定本地签名工具，并在用户明确同意后为当前机器配置用途受限的本地代码签名身份。构建脚本会复用 `.local-signing/` 的同一证书；此目录不可当作 build 缓存删除，也不会提交 Git。详情见 [固定本地签名](scripts/local-signing/README.md)。

本机已完成固定版录屏授权。最新实际应用在保存配置、重新编译且 CDHash 变化后，完整退出重启仍自动读回 App ID 和掩码密钥；直接框选、Original 对照及真实 Mathpix 识别全部成功，返回完整 `I(U)=1-[1/U]_+ + C\delta(U)?`，服务置信度为 100%。本次未重新输入凭据、未重新授权，也未出现录屏或钥匙串弹窗。此前 Escape 取消及凭据组件跨编译读写、错误签名拒绝测试均已通过。详见 [实际测试结果](docs/TESTING.md)。

已删除 4 个旧测试应用，当前仅保留 `build/Local/Build/Products/Release/ScreenScribe.app`。源码和固定签名状态未删除。本机操作审计与清理清单仅保留在开发机器，公开验证范围见 [测试说明](docs/TESTING.md)。

## 界面与权限行为

界面已按参考截图重做为 **716×524 的菜单栏气泡面板**。普通启动只常驻图标，点击显示面板；没有独立结果/设置/历史窗口。顶部工具栏提供截图、导入图片、任务/服务、快捷键、历史、记录前后翻页、删除、固定和设置。OCR / Data / Original 分别用于离线数学预览、源码编辑和原图对照；四行输出各自支持复制、编辑和放大。Copy LaTeX 的右键菜单另提供 `\[…\]` 复制。

公式预览使用随应用打包的 KaTeX，不访问 CDN，不将源码插入可执行脚本。置信条只显示服务实际提供的 confidence，没有分数时明确显示“未提供”。不支持的 TeX 命令保留源码并提示预览失败。TikZ 仍以源码和图结构说明展示，不在本版中编译。

此前 ad-hoc 构建不断改变应用身份，旧授权未能匹配新版本，曾出现录屏提示和只截到壁纸的问题。现已配置固定证书，并为固定版重新确认授权；原生框选层使用 nonactivating NSPanel，避免主动切换 Space。应用启动和后台不会申请录屏权限；系统未确认当前应用时，在调用截图 API 前停止，由用户通过设置中的“启用直接框选（系统授权）”入口处理。

还支持导入图片，以及 **⌃⌘⇧4 → 粘贴截图**（叠放图片图标 / **⌘⇧V**）。只在用户点击时读取剪贴板图片，不监视剪贴板；这些入口使用同一 PNG 编码、识别、编辑、预览和历史链路。

钥匙串所有读写先执行进程级禁止交互策略（legacy macOS Keychain ACL 需要 `SecKeychainSetUserInteractionAllowed(false)`，仅使用 SecItem 的认证选项并不能覆盖它）。本机自签程序即使 DR 固定，默认 Keychain partition 仍随 CDHash 改变，因此本地构建额外使用固定不变的嵌入式 XPC 凭据组件。双方检查消息发送者的代码签名要求，客户端先验证组件的固定 CDHash，再完成无密钥握手，随后才传递凭据。组件仅操作本应用的新专用条目，不改旧 ACL、不开放给其他程序；详情见 [固定本地签名](scripts/local-signing/README.md)。组件缺失或身份校验失败时停止，不自动回退旧条目。其他未配置此组件的构建保留原来的 DR 分组存储。

## 构建与运行

需要 Xcode 26+ SDK，最低运行系统仍为 macOS 14；本次实际构建环境为 Xcode 26.6 / Swift 6.3.3 / Apple Silicon。

```sh
./scripts/build-local.sh
open build/Local/Build/Products/Release/ScreenScribe.app
```

该脚本构建 Release 并执行签名校验；本机默认复用已配置的 `.local-signing/` 固定证书。已有本地签名配置失效时会报错，不静默回退 ad-hoc。也可设置 `SCREENSCRIBE_SIGNING_IDENTITY` 为已安装的固定签名证书；全新检出且没有签名配置时才使用 ad-hoc。构建脚本不会创建证书、修改信任或自动授权。产物是个人本地应用，未公证，未用于 App Store；现代 macOS 使用原生框选与 ScreenCaptureKit，旧系统使用 `screencapture` 子进程。目标不启用 App Sandbox，保留 hardened runtime。仓库不再要求 `Secrets.plist`。

也可打开 `ScreenScribe.xcodeproj`，选择 `ScreenScribe` scheme；Signing 中选择自己的开发团队。稳定的 Apple Development 签名更适合长期使用屏幕录制权限与 Keychain；重新编译 ad-hoc 应用可能改变系统对应用身份的判断。不要同时运行多个构建版本。

仅验证编译、不签名：

```sh
xcodebuild -project ScreenScribe.xcodeproj -scheme ScreenScribe \
  -configuration Debug -derivedDataPath build/Debug CODE_SIGNING_ALLOWED=NO build
```

## 使用

1. 启动后在菜单栏找取景框图标；不需保持任何窗口打开。
2. 点击面板右上角齿轮 → 科研识别，选择提供商，填写并**保存凭据**。
3. 从面板顶部的任务/服务菜单选择公式或费曼图。点“截图识别”，或按默认 **⌘⇧L**；离线文字 OCR 是 **⌘⇧T**。可在设置“快捷键与原有工具”中录制新组合；Escape 取消录制，注册冲突会显示错误。已安装旧版的用户保留已有快捷键。
4. 拖动框选公式，松开鼠标开始识别；Escape 取消。本机固定版已完成授权，可直接框选。现代 macOS 使用原生框选和 ScreenCaptureKit，旧系统使用系统选择器；只把选中区域的 PNG 交给识别服务。截图期间收起菜单栏面板，隐藏框选覆盖层后再取图；完成或取消后返回同一面板。
5. 在面板 OCR / Data / Original 标签间切换，编辑并复制纯公式、行内、独立公式或 equation 环境。多行环境与内部换行不会被替换。费曼图另显示结构说明、待确认项及完整独立文档源码。编辑后点“保存修改”更新历史。
6. “历史记录”可查看、复制、删除、清空、移除全部已存原图。默认仅保存文本；可在设置开启原图保存，最多 50 条、约 25 MB 图文数据，超出时淘汰最旧记录。普通文件不包含 API Key。

**首次在其他机器启用直接框选**：在设置中点击“启用直接框选（系统授权）”，并用“在 Finder 中定位此应用”确认授权对象，再按系统提示重启。本机已完成此步骤。macOS 用签名身份判断是否为同一个应用，旧 ad-hoc 的 cdhash 授权不能自动转移到固定身份；应用不会在后台反复申请权限。

## API 配置

### Mathpix（公式）

本轮已用真实账户确认并修复 `opts_conflict`：服务不允许同时请求 line_data 与 word_data，现仅请求 line_data。内置连接测试图和三种公式样例均取得 LaTeX；复杂样例服务置信度约 42.8%，仍须人工核对。连接测试使用当前输入，点击“保存凭据”才负责持久化；已验证凭据仅在进程内缓存，不反复读取钥匙串。详见 [实际测试结果](docs/TESTING.md)。

输入个人 Mathpix App ID 和 App Key，保存到 macOS Keychain。固定调用 `https://api.mathpix.com/v3/text`，认证在 HTTP headers。只解析 `latex_styled` 或 `data[type=latex].value`，不把普通 Markdown 文本冒充公式。多个数学片段用 gathered 排列并提示核查；无法可靠推断原对齐时不猜测。低置信字符/行会列为待确认，但置信度无法发现全部歧义。

截图 base64 超过保守的 2 MB 限制时要求缩小选区，不静默缩图。Mathpix 费曼图模式会明确报错，请切换视觉服务。

新增识别采用官方 `rm_spaces=true`、`idiomatic_braces=true` 选项，减少 LaTeX token 间冗余空白与不必要的指标括号。保留字体、显式间距、多行环境和文本内有意义的空格，不以全局替换改写公式。旧历史及手工编辑的源码保持原样。四行复制区也已收紧；预览行只为显示压平换行，实际复制仍保留完整源码和环境。

Mathpix 面板显示**总剩余约 N 次 · 本月已用 M 次**。总剩余基于设置中的 Billing 余额快照和普通图片单价，标注快照时间；费用向上预留、基础次数向下取整。每次有效请求发出前先本地扣 1 次（失败与重试也保守计入），每完成 5 次查询官方 `GET v3/ocr-usage` 校准；服务统计延迟时保留本地扣减，不让剩余回涨。重启保留计数及距下一次查询的余数。启动和手动刷新也可查询用量。

初始待结算费用额外预留 $0.01；若已知本月图片数对应的费用更高，先按单价算出最低图片费用并向上取整到分，再补足预留差额。之后始终逐张扣 1，不逐张按美分跳扣。官方用量不会和本地请求重复扣除，但可追加校准其他设备的同 Key 图片消费。跨月显示“总剩余待更新账单”，避免用不完整的月末数据报出精确剩余。

用量查询范围采用 UTC 自然月；统计可能延迟。设置中的图片月上限仍可选，只用于本月剩余显示，不改变服务限额。普通 OCR Key 不能自动读取 Billing 金额；总剩余使用已保存的账单快照，长文本差价、其他 Key 或其他端点消费需要更新快照。页面中“保存账单快照”会重设本地扣减基准。

控制台的 **200/min 是同步图片请求速率，20,000 pages/month 是 PDF 与 Files 共用的文档页上限**，不能当作截图次数余额。图片默认按量计费、没有月次数上限；公开用量接口没有总余额或总剩余字段，实际套餐与金额需查看 Mathpix Console 的组织 Billing。软件明确显示这项限制，不预设 2,000 或 20,000 次图片额度。依据与官方链接见 [能力与额度核实](docs/API-VERIFICATION.md)。

### OpenAI 兼容视觉 API（公式 / 实验性费曼图）

- Base URL：例如 `https://api.openai.com/v1`，填写 API 根地址，**不含** `/chat/completions`，只接受 HTTPS。
- 模型：填写账户实际可用、支持图像输入的模型名称；不预设所有模型都支持视觉。
- API Key：为这个端点保存专用密钥。更换 URL 会清空输入框，需重新读取或保存；不同端点不会自动共用密钥。
- 协议：Chat Completions，`image_url` base64 PNG、`detail=high`、`max_completion_tokens=8192`；未实现 Responses 专用端点。服务若不接受这些参数，需要适配相应协议，不能保证任意“兼容”服务可用。
- 本地 PNG 上限 10 MB；具体服务还可能有更严格限制。

费曼图使用独立提示词和 JSON 解析器，要求完整 TikZ / TikZ-Feynman 文档、结构说明、歧义清单。检查基本环境、括号和返回结构，拒绝截断、拒答和明显文件访问命令。**不自动运行模型生成的 TeX**。线型不能证明粒子身份，模型仍可能误读箭头、标签和拓扑，必须人工核查。

“测试连接”会发送内置 `x²+1` 图片并显示返回结果，可能计费；它不上传屏幕，也不能证明复杂公式或费曼图识别准确率。OpenAI API 与 ChatGPT 订阅独立；不要输入 ChatGPT 登录凭据。费用与协议核查见 [API 核实记录](docs/API-VERIFICATION.md)。

### 原有 Gemini 工具

保留原版功能，凭据改为 Keychain，旧 UserDefaults 密钥首次启动成功迁移后删除。请求改为 header 认证，不再拼接密钥到 URL；不记录 API 原始输出。原版模型列表保留，未通过真实 Gemini 账户验证可用性。科研两种模式使用上面两类独立服务。

## 本地数据与安全

- 凭据：Keychain 服务 `app.screenscribe.credentials`；各后端分开，视觉凭据还按完整端点隔离。可在设置中删除对应凭据。
- 设置：UserDefaults，包括后端、模型、Base URL、模式、快捷键、原图开关；可选图片月上限、账单金额/时间/单价快照及扣减/校准计数按 App ID 哈希隔离保存。不保存密钥或原始 App ID；普通用量响应仅驻内存。
- 历史：`~/Library/Application Support/ScreenScribe/recognitions.json`，目录 700、文件 600；JSON 以原子方式写入。损坏文件保留并显示错误，用户明确清空后才恢复写入。
- HTTP：只发送选区或内置测试图，不自动重试计费请求，不跟随重定向，不展示服务错误正文或凭据。网络请求临时会话不持久缓存。
- 关闭原图持久化影响新记录；历史中的“移除全部原图”可清理旧图。当前打开的结果图仍暂存在内存，退出应用释放。

## 测试

```sh
./scripts/run-standalone-tests.sh
./scripts/verify-fixtures.sh  # 可选：本机需 LuaLaTeX、tikz-feynman 和 Poppler
```

独立 Swift 测试无需真实 API Key。测试覆盖请求协议、字段解析、错误状态、限流、断网、输出格式、历史和设置持久化。五种本地图片、源码、公式预期文本在 `Tests/Fixtures/`，可显示 PNG 后进行截图实测。样例编译与模型输出编译是不同的测试。

无网络界面演示（不调用 API、不写入历史）：

```sh
open -n build/Local/Build/Products/Release/ScreenScribe.app --args --demo --show-settings
```

Keychain/剪贴板系统测试须在正常桌面会话执行，使用随机测试条目并恢复原剪贴板；见 `Tests/KeychainClipboardSmokeTests.swift` 和 [测试报告](docs/TESTING.md)。

## 目录与交付状态

```text
ScreenScribe.xcodeproj/             原有 Xcode 工程
ScreenScribe/Sources/App.swift      菜单、权限入口、截图调度
ScreenScribe/Sources/Services/      原有截图、权限、Gemini 服务
ScreenScribe/Sources/Settings/      原有设置及 Carbon 快捷键
ScreenScribe/Sources/Physics/
  RecognitionTypes.swift           统一识别协议、模式、结果、复制格式
  MathpixProvider.swift            官方数学 OCR 请求和字段解析
  MathpixUsageService/Store.swift   官方本月图片用量、账号隔离与可选剩余估算
  MathpixCreditEstimate/Store.swift 账单保守换算、逐张扣减和每五次校准
  OpenAICompatibleVisionProvider.swift  视觉请求、独立公式/费曼图解析
  APITransport.swift               HTTP 状态、超时、取消、重定向保护
  CredentialStore.swift            Keychain 和旧凭据迁移
  PhysicsSettings*.swift           科研设置与连接测试
  PhysicsWorkspace.swift           加载/错误、原图对照、编辑、复制
  RecognitionHistory*.swift        有界本地历史与管理界面
Tests/                             原有与新增自动测试、五类样例
scripts/                           构建签名、自动测试、样例验证
 docs/                             API 核实、阶段交付与测试报告
```

阶段构建和实际端到端结果见 [测试报告](docs/TESTING.md)。V0.1 下载包面向 Apple Silicon / arm64，使用固定本地开发证书签名，未使用 Apple Developer ID 分发签名，未公证。已提供离线公式排版预览；TikZ 应用内编译预览暂未实现。真实 Mathpix 公式框选及重启后使用已验证，单个样例的服务置信度不能代表总体准确率。多显示器、不同显示缩放、快捷键冲突及其他真实视觉模型结果仍需按报告中的人工检查项验证。没有 PDF 批处理、账号、订阅、云同步或实时 OCR。

后续建议：先用个人 API 对五类样例逐项建立准确率记录，再补真实论文公式、cases/split/矩阵/plus distribution 回归样例；之后加入隔离的预览渲染、更多端点协议与稳定签名发布流程。

## 依赖与许可证

应用使用 Apple 系统框架，并随包携带 KaTeX 0.16.22 的 JavaScript、CSS 和字体用于离线预览，无 Swift Package 或远程 CDN 运行时依赖。KaTeX 为 MIT 许可，详见 [第三方声明](THIRD-PARTY-NOTICES.md)。TeX Live、TikZ-Feynman、Poppler 只用于开发者的可选样例验证，不随应用打包。许可证为 [MIT](LICENSE)，保留 TextGrabber2 和 Samuel Zhang 的版权声明。本项目扩展自 ScreenScribe / TextGrabber2。
