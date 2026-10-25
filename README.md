# ScreenScribe V0.1 · 理论物理截图识别

面向论文和讲义阅读的桌面截图工具：**框选图片 → 调用自己的识别 API → 编辑 LaTeX / TikZ → 复制**。公式支持离线排版预览。

项目包含原生 **macOS 菜单栏版**和独立的 **Windows 托盘版**。两端沿用同一面板交互，支持 Mathpix 公式识别、用户配置的视觉 API、原图对照、本地历史和识别额度估算。

**当前进度（2026-10-25）**：V0.1 分发资产已发布。Mac 版已完成真实 Mathpix 端到端验收；Windows V0.1 为内测版，已通过 Windows 原生 CI 与安装后自检，客户端人工验收和体积优化仍待推进。

## 下载与版本状态

[打开 V0.1 Release：成熟 Mac 版与内测 Windows 版](https://github.com/pionplusminus/screen-scribe/releases/tag/math)

| 用途 | 文件 | 大小 | 适用范围 |
| --- | --- | --- | --- |
| Mac 安装 | [latexhelper-v0.1-macOS-arm64.dmg](https://github.com/pionplusminus/screen-scribe/releases/download/math/latexhelper-v0.1-macOS-arm64.dmg) | 约 2.09 MiB | macOS 14+，Apple Silicon / arm64 |
| Windows 安装 | [ScreenScribe-Windows-0.1.0-x64-Setup.exe](https://github.com/pionplusminus/screen-scribe/releases/download/math/ScreenScribe-Windows-0.1.0-x64-Setup.exe) | 约 108.32 MiB | Windows 10/11，Intel / AMD x64，内测 |
| Windows 开发交接 | [ScreenScribe-Windows-0.1.0-source.zip](https://github.com/pionplusminus/screen-scribe/releases/download/math/ScreenScribe-Windows-0.1.0-source.zip) | 约 1.12 MiB | 完整源码、资源、测试、锁文件及交接说明 |

版本号为 **0.1.0**，Mac 构建号为 **16**。当前公开 Release 的实际标签为 `math`。Mac 下载文件名为 `latexhelper-…dmg`，包内应用仍为 **ScreenScribe.app**。

源码位置：

- [macOS：main 分支](https://github.com/pionplusminus/screen-scribe/tree/main)。
- [Windows：codex/windows-v0.1 分支的 ScreenScribe-Windows 目录](https://github.com/pionplusminus/screen-scribe/tree/codex/windows-v0.1/ScreenScribe-Windows)。该目录尚未合并到 `main`。
- Release 自动生成的 `Source code (zip/tar.gz)` 对应 `math` 标签的 Mac 源码。**修改 Windows 版请使用上表的专用源码包，或签出 Windows 分支。**

安装包不包含共享 API Key。普通使用者下载对应系统的安装包即可，无需安装 Xcode、Node.js 或开发依赖。

### 安装

**macOS**：打开 DMG，将 ScreenScribe 拖到 Applications，启动后从菜单栏图标打开面板。发布包使用固定本地开发证书签名，尚未采用 Apple Developer ID 分发签名或公证；首次启动可能需要按系统安全提示确认。

**Windows**：运行 EXE 按向导安装，再从桌面、开始菜单或系统托盘打开。默认安装到当前用户目录，无需管理员权限。安装包尚未代码签名，系统可能显示未知发布者。Windows 包较大主要因为随包携带 Electron 运行环境；轻量化尚未实施。

## 主要功能

- **直接框选与图片输入**：快捷键或面板按钮框选，也可导入图片或主动粘贴截图；识别请求只包含用户选定的图片。
- **公式识别与源码精修**：Mathpix 请求紧凑 LaTeX，减少冗余空格和括号；保留必要环境、显式间距和文本内容，不在本地擅自化简公式。
- **OCR / Data / Original**：同一面板完成公式排版预览、源码编辑和原图对照，设置与历史也在面板内切换。
- **多种复制格式**：纯 LaTeX、`$…$`、`$$…$$`、`equation`；复制菜单另提供 `\[…\]`。实际复制保留源码换行和环境。
- **离线公式预览**：KaTeX、CSS 和字体随应用携带，预览无需 CDN。置信度只展示服务提供的数值，缺失时显示未提供。
- **本地历史**：最多 50 条、约 25 MB，支持编辑、复制、删除和清空；默认不将原图写入历史，可选择开启。
- **Mathpix 额度显示**：展示本月图片用量，以及由 Billing 快照保守推算的总剩余次数；逐次扣减、每五次校准，重启保留状态。
- **实验性费曼图重建**：视觉模型可返回 TikZ / TikZ-Feynman 源码、结构说明和待确认项，需人工对照原图。

Mac 版另外保留原有的 **Apple Vision 离线文字 OCR** 和 **Gemini 自定义提示词工具**；Windows V0.1 未移植这两项旧工具。两端均不在应用中编译或执行生成的 TikZ / TeX。

## 快速开始

1. 安装并打开面板，进入设置，选择 Mathpix 或兼容视觉 API。
2. 填写并保存自己的凭据；视觉服务还需填写 Base URL 和实际支持图像输入的模型名称。
3. 选择公式或费曼图任务，框选、导入或粘贴图片。费曼图任务使用视觉服务。
4. 在 OCR / Data / Original 间核对、编辑并复制结果。
5. 如需总剩余次数估算，在额度设置中保存 Billing 余额、待结算金额、图片单价和观察时间。

| 操作 | macOS 默认快捷键 | Windows 默认快捷键 |
| --- | --- | --- |
| 直接框选识别 | ⌘⇧L | Ctrl+Shift+L |
| 粘贴图片识别 | ⌘⇧V | Ctrl+Shift+V |
| 原有离线文字 OCR | ⌘⇧T | 未提供 |
| 取消框选 | Esc | Esc 或鼠标右键 |

快捷键可以在设置中更改，注册冲突会显示错误；已有用户的自定义组合会保留。Windows 也可先按 Win+Shift+S 截图，再粘贴识别。

Mac 首次直接框选需要系统录屏授权。通过设置中的“启用直接框选（系统授权）”与“在 Finder 中定位此应用”确认授权对象，再按系统提示操作。应用不会在启动或后台自动反复申请录屏权限；不同签名构建的旧授权可能无法沿用。

## 识别服务与费用

### Mathpix：公式识别

填写个人 **App ID** 和 **App Key**。程序通过 HTTPS 调用 `POST https://api.mathpix.com/v3/text`，凭据位于请求 headers，只提取已验证的数学 LaTeX 字段。

请求启用 `rm_spaces`、`idiomatic_braces` 等紧凑源码选项，并仅请求行级数据，避免此前行级与词级数据选项冲突。无法识别内容、限流、认证或网络错误会在面板提示，不自动重试计费请求。

Mathpix 后端用于公式，不提供本应用所需的费曼图转 TikZ 工作流。遇到费曼图请切换视觉服务。复杂公式、低置信结果以及模型未标记的歧义都需要人工核对。

### 兼容视觉 API：公式与实验性费曼图

- **Base URL**：填写 HTTPS API 根地址，例如 `https://api.openai.com/v1`，不包含末尾的 `/chat/completions`。
- **模型**：填写自己账户实际可用、支持图像输入的模型，不预设任意兼容服务都可用。
- **Key**：按服务端点隔离保存；切换地址不会自动把原密钥用于新服务。
- **当前协议**：Chat Completions，使用 base64 PNG 的 `image_url` 输入；尚未实现 Responses 专用端点。

公式与费曼图使用独立提示词和解析器。费曼图结果进行结构和格式检查后作为可编辑源码展示；这些检查不证明拓扑、箭头或粒子标签正确，也不保证任意返回文档都能编译。

“测试连接”会发送内置公开公式图，可能计费；它不上传屏幕，也不能代替复杂样例的准确率测试。识别费用由所选服务收取。OpenAI API 与 ChatGPT 订阅分别计费，应用不使用 ChatGPT 登录凭据。

服务协议和既有核实记录见 [API 核实说明](docs/API-VERIFICATION.md)。

## 剩余次数如何计算

**“总剩余约 N 次”是账单快照估算，不是实时账户余额，也不是服务承诺的可识别次数。**

应用查询的 `GET https://api.mathpix.com/v3/ocr-usage` 用于读取图片用量；Billing 金额由用户手动填写和更新。计算过程为：

1. 用余额、待结算金额和普通图片单价计算基础可覆盖次数，内部采用整数微美元，次数向下取整。
2. 为待结算金额额外预留 $0.01，并结合已知图片用量补足可能的精度差额。
3. 每次有效图片请求发出前先在本地扣 1 次，失败和手动重试也保守计入。
4. **每完成 5 次 Mathpix 请求，查询官方图片用量校准**；服务统计迟到时保留本地扣减，不因迟到数据回涨，也不重复扣除同一批本地请求。
5. 重启后保留计数和五次余数；跨月或记录异常时要求更新账单快照。

用量按 UTC 自然月查询。可选“图片月上限”是用户填写的展示参数，不修改服务端限额，也不会把控制台的请求速率或 PDF 页数限制当成图片余额。其他设备、其他 Key、不同接口及不同单价的消费可能造成差额，需要重新更新快照。第五次查询刷新的是图片用量，**不会自动刷新 Billing 金额**。

## 架构

| 层次 | macOS | Windows |
| --- | --- | --- |
| 桌面外壳 | Swift / SwiftUI / AppKit，菜单栏和单个 NSPopover | Electron 45，托盘和单个面板窗口 |
| 截图与快捷键 | 原生选区层、ScreenCaptureKit、旧系统截图后端；Carbon 快捷键 | desktopCapturer、各屏幕选区覆盖层、globalShortcut |
| 识别编排 | 统一识别协议、工作区、取消与结果状态 | 主进程 Controller、受限 IPC、识别 Provider |
| 公式排版 | WKWebView 内本地 KaTeX | 隔离渲染器内本地 KaTeX |
| 凭据保护 | macOS Keychain；固定本地构建使用冻结 XPC 凭据组件 | Windows DPAPI，通过 Electron safeStorage 加密 |
| 本机数据 | UserDefaults、应用支持目录中的 JSON 历史 | 当前用户配置目录中的有界 JSON 存储 |

识别网络请求与凭据操作由受控服务层负责；模型返回内容作为文本和结构化字段处理。Windows 渲染器启用 sandbox / context isolation，关闭 Node 集成；两端公式预览均只加载本地资源，KaTeX 关闭 trust。

Windows 详细结构见 [架构说明](https://github.com/pionplusminus/screen-scribe/blob/codex/windows-v0.1/ScreenScribe-Windows/docs/ARCHITECTURE.md)。

## 数据与隐私

- API Key 不写入源码、普通设置、历史或日志；应用不附带共享密钥。
- 截图识别只发送用户明确选定的图片；连接测试只发送内置公开图。完整桌面参考画面只在本机用于框选。
- 不监听剪贴板、不后台连续截图、不自动重试计费请求；带凭据请求不跟随 HTTP 重定向。
- 历史默认仅持久化文本。关闭原图保存只影响新记录，已有图片需通过历史管理明确清理。
- 历史源码与账单快照属于本机数据，凭据的系统加密不等于对整个数据目录加密。Windows DPAPI 与登录用户相关，不能防护已被控制的同一用户会话。

| 数据 | macOS | Windows |
| --- | --- | --- |
| 历史与配置 | 历史位于 `~/Library/Application Support/ScreenScribe/recognitions.json`，设置位于 UserDefaults | `%APPDATA%\ScreenScribe-Windows` |
| API 凭据 | Keychain 专用条目 | 用户配置目录内的 DPAPI 密文 |
| 卸载 | 本机数据需单独管理 | 卸载器默认保留用户配置和历史 |

Mac 本地开发签名状态保存在被 Git 忽略的 `.local-signing/`。该目录及冻结凭据组件不是构建缓存，不应随意删除，也不应随源码交接或分发。固定签名与凭据组件的工作方式见 [本地签名说明](scripts/local-signing/README.md)。

## 已完成的验证与当前限制

以下是既有测试记录，不将功能实现、Mock 测试与真实 API 验收混为一项。

| 项目 | macOS | Windows |
| --- | --- | --- |
| 自动回归 | 15 组独立 Swift 测试通过 | 本机 68 项通过；Windows CI 67 项通过、1 项符号链接测试跳过 |
| 实际运行环境 | Apple Silicon / macOS 26 | Windows Server 2025 x64，10.0.26100 |
| 真实 Mathpix | 直接框选、Original 对照、识别与连续五次额度校准通过 | 尚未使用真实账户验收 |
| 凭据恢复 | 主应用更新并重启后自动读回，未重复录屏或钥匙串弹窗 | DPAPI 保存、从新凭据库重新读取和删除通过 |
| 安装与原生能力 | Release 构建、签名及 DMG 核验通过 | 构建、151 项静态检查、原生自检、静默安装、安装后自检和卸载通过 |

Windows 自检在源码运行和安装后的程序中各通过 14 项检查，覆盖凭据、快捷键、隔离渲染器、显示器匹配及实际桌面截图裁剪；使用自有公开彩色测试窗对照。**它没有自动操作正式选区界面的鼠标拖动或托盘，因此不等于 Windows 10/11 客户端完整人工验收。**

- [Mac 测试说明](docs/TESTING.md)
- [Windows 测试说明](https://github.com/pionplusminus/screen-scribe/blob/codex/windows-v0.1/ScreenScribe-Windows/docs/TEST-RESULTS.md)
- [Windows 成功 CI](https://github.com/pionplusminus/screen-scribe/actions/runs/40109506792)

尚待完成：

- Windows 10/11 客户端正式框选、托盘、混合 DPI 多屏和真实 API 验收；Mac 的更多系统版本、多屏、缩放与全屏 Space 回归。
- 视觉后端与原有 Gemini 工具的真实账户测试，以及真实论文公式和费曼图准确率记录。
- Windows 安装包轻量化；当前保留 Electron 实现作为功能基线，后续优化由协作者接续。
- 更完整的分发签名、公证和发布流程。

当前未提供 PDF 批处理、实时 OCR、云同步、账号或订阅系统，也没有 TikZ 应用内编译预览。Mac 当前分发包为 arm64，Windows 当前分发包为 x64，其他架构未完成分发验收。

## 从源码构建

### macOS

需要 Xcode 26+ SDK；最低部署版本为 macOS 14。既有构建验证环境为 Xcode 26.6 / Swift 6.3.3。

在仓库根目录执行：

```sh
./scripts/build-local.sh
open build/Local/Build/Products/Release/ScreenScribe.app
```

脚本构建 Release 并校验签名。已有固定签名配置时会复用同一身份，配置失效则停止，不静默回退；全新检出且未配置签名时才使用 ad-hoc。脚本不会创建证书、改信任或自动授权。长期使用与分发应按自己的签名身份规划，详情见 [本地签名说明](scripts/local-signing/README.md)。

无真实 API 的自动回归：

```sh
./scripts/run-standalone-tests.sh
```

可选系统与样例检查为 `scripts/run-system-smoke-tests.sh`、`scripts/verify-fixtures.sh`；前者需正常桌面会话，后者需 LuaLaTeX、TikZ-Feynman 和 Poppler。样例编译通过不代表模型输出可编译或识别准确。

### Windows

推荐在目标 Windows 电脑构建，需要 **Node.js ≥ 22.12.0** 和 npm。可解压专用源码 ZIP 后进入项目目录；或签出独立分支：

```sh
git clone --branch codex/windows-v0.1 https://github.com/pionplusminus/screen-scribe.git
cd screen-scribe/ScreenScribe-Windows
npm ci
npm run check
npm test
npm run smoke
npm run dist:win
```

安装器输出为 `dist/ScreenScribe-Windows-0.1.0-x64-Setup.exe`，不会自动发布。Electron 与 electron-builder 版本由锁文件固定，首次安装依赖需要联网。

Mac 上可用 `npm run demo` 查看 Windows 版的隔离界面演示；演示禁用真实截图、OS 凭据与识别请求，不能作为 Windows 实机识别证据。更多说明见 [Windows README](https://github.com/pionplusminus/screen-scribe/blob/codex/windows-v0.1/ScreenScribe-Windows/README.md)。

## 目录与开发交接

以下为 Windows 分支中的完整目录视图；当前 `main` 仅包含 Mac 端：

```text
ScreenScribe.xcodeproj/       macOS Xcode 工程
ScreenScribe/Sources/         macOS 菜单栏、截图、快捷键与科研识别
Tests/                       Swift 回归测试和公开公式/费曼图样例
scripts/                     Mac 构建、签名与验证工具
docs/                        Mac 测试、API 核实和发布说明
ScreenScribe-Windows/
  src/                       主进程、受限桥接、渲染器、截图和识别服务
  assets/                    图标、公开测试图、离线 KaTeX 和字体
  tests/                     Node.js 自动回归
  scripts/                   Windows 自检与打包校验
  docs/                      架构、接口、使用及验收说明
  package.json               开发命令与 NSIS 打包配置
  package-lock.json          固定依赖版本和完整性
.github/workflows/           构建与验证 CI
```

合作者继续开发 Windows 版时，使用约 1.12 MiB 的专用源码 ZIP 即可：包含完整源码、资源、测试、许可证、依赖锁文件和交接说明，不含 `node_modules`、缓存、EXE、Git 历史、用户数据或本机操作日志。解压后执行 `npm ci` 恢复依赖；需要运行现有版本作对照时，另取 EXE 安装包。

本机生成文件被 Git 忽略，默认不随仓库克隆：

- Mac 正式构建：`build/Local/Build/Products/Release/ScreenScribe.app`
- Mac DMG：`build/Release-v0.1/ScreenScribe-v0.1-macOS-arm64.dmg`
- Windows 安装器与源码包：`ScreenScribe-Windows/dist/`

### 已发布文件校验值

```text
latexhelper-v0.1-macOS-arm64.dmg
ce86385de15fd75a4ba2714349cb5ead6e44dd1dd3b0d3ef0feaba822b174c20

ScreenScribe-Windows-0.1.0-x64-Setup.exe
dcabd3a36982763e306857146c585c1ccbf516b6796c187790aaf64eebc86ab9

ScreenScribe-Windows-0.1.0-source.zip
daaee2a1987fcfa1759ca88d027a2ee8a34248a3287f05aef90231fcce157c51
```

以上为 SHA-256，来自当前 Release 资产元数据，并与本机对应文件核对。Mac 本机 DMG 与公开附件文件名不同，内容校验值相同。

## 依赖与许可证

项目采用 [MIT 许可证](LICENSE)，扩展自 ScreenScribe / TextGrabber2，保留原作者及 Samuel Zhang 的版权声明。

Mac 使用 Apple 系统框架、Swift / SwiftUI / AppKit，以及随包携带的 KaTeX；Windows 使用 Electron 45.0.0、electron-builder 26.18.0 和本地 KaTeX。Node.js 是 Windows 开发依赖，不要求最终使用者另外安装。TeX Live、TikZ-Feynman 与 Poppler 仅用于开发者的可选样例验证，不随程序分发。

第三方许可见 [Mac 第三方声明](THIRD-PARTY-NOTICES.md) 和 [Windows 第三方声明](https://github.com/pionplusminus/screen-scribe/blob/codex/windows-v0.1/ScreenScribe-Windows/THIRD-PARTY-NOTICES.md)。
