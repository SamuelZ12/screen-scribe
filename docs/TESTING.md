# V0.1 测试说明

截至 2026-10-24，现有功能的 15 组独立 Swift 回归测试全部通过。真实桌面验收使用 Apple Silicon、macOS 26、Xcode 26.6 / Swift 6.3.3；最低部署版本为 macOS 14，但尚未在所有支持系统版本上逐一实测。

## 自动回归

```sh
./scripts/run-standalone-tests.sh
```

这些测试使用合成凭据和注入的网络响应，不调用付费识别服务，不读取真实 API Key。

| 测试组 | 覆盖内容 |
| --- | --- |
| GeminiModelCatalogTests | 原有模型目录与配置回归 |
| GeminiServiceRequestTests | 模型、请求结构、header 认证与输出限制 |
| ScreenCaptureCLIArgumentsTests | 系统框选命令参数与选区行为 |
| ScreenCaptureStrategyTests | 不同 macOS 版本的截图后端选择 |
| ScreenRegionSelectionTeardownTests | 框选覆盖层拆卸与复用 |
| MathpixProviderTests | 数学字段解析、紧凑 LaTeX 选项、图片大小、错误与取消、计费请求回调 |
| VisionProviderTests | 视觉请求、公式与费曼图独立解析、拒答及异常输出 |
| HistoryPersistenceTests | 有界历史、原图开关、损坏文件处理与设置持久化 |
| ScreenPermissionRegressionTests | 无自动权限申请、未获确认时停止截图 |
| MathpixUsageTests | 官方只读用量请求、账号和类型分组、日期边界及严格计数校验 |
| MathpixUsageStoreTests | 账号隔离、可选月上限、过期数据、失败及迟到响应 |
| PhysicsSettingsConcurrencyTests | 凭据读取期间取消、删除、切换后端或端点的并发行为 |
| MathpixCreditEstimateTests | 29,484 组金额组合、定点精度、保守取整、逐次扣减与溢出 |
| MathpixCreditStoreTests | 账单快照、账号隔离、重启恢复、去重校准与跨月处理 |
| MathpixQuotaCadenceTests | 每五次完成后查询用量、失败计数、延迟统计及额外消费校准 |

可选检查：

```sh
./scripts/run-system-smoke-tests.sh
./scripts/verify-fixtures.sh
```

系统 smoke 测试需要正常桌面会话，使用临时合成钥匙串条目并恢复剪贴板。样例检查需要 LuaLaTeX、TikZ-Feynman 和 Poppler；它验证本地测试图的构建，不代表识别模型能正确还原费曼图。

## 已完成的实际验证

- 原生直接框选公式，Original 对照为正确选区；真实 Mathpix 返回完整 LaTeX。Escape 取消不新增识别历史。
- 更新主应用并完整退出重启后，已保存的配置自动读取；测试期间没有重复录屏或钥匙串弹窗。
- 紧凑源码选项、离线 KaTeX 预览、同面板设置与四行复制区已检查。
- 连续五次公开公式识别均成功；每次本地剩余估算减一，第五次完成后自动查询官方图片用量。重启后保留扣减和校准状态。
- 嵌入式凭据组件完成真实 XPC 正反测试：不同主应用构建可访问合成条目；错误客户端签名、错误组件身份与篡改组件均被拒绝。
- Release 构建及严格签名校验通过。签名校验与 Apple 公证是不同流程，本版未公证。

## 验证边界

单张公式的高置信度不代表总体识别准确率。多显示器、混合 Retina 缩放、全屏 Space、其他 macOS 版本仍需进一步实测。OpenAI 兼容视觉服务和保留的 Gemini 工具尚未使用真实账户逐项验证；费曼图重建为实验功能，必须对照原图核查。

总剩余表示账单快照可覆盖的普通图片次数估算。每五次刷新的是图片用量接口，不会自动读取 Billing 金额；其他 Key、其他端点、长文本差价和跨月账单需要更新快照。
