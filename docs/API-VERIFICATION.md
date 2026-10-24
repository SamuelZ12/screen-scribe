# API 核实记录

核实日期：2026-10-23。Mathpix 已在本轮以用户授权的临时账户完成真实请求测试；视觉后端仍未做真实账户验证。

## Mathpix

- 认证：`app_id`、`app_key` HTTP headers，固定 `https://api.mathpix.com/v3/text`，不允许改向其他域名。
- 请求：PNG base64 data URL 放入 JSON `src`，请求 `latex_styled`、`data`，`data_options.include_latex=true`；保留有意义的空格和字体，不请求表达式化简。2026-10-24 新识别启用官方 `rm_spaces=true` 与 `idiomatic_braces=true`，只让服务压缩冗余 token 空白与可省略括号，不做本地全局删空格。
- 返回：单个方程可有 `latex_styled`；其他数学片段从 `data` 中 `type=latex` 的 `value` 提取。`text` 是 Mathpix Markdown，不能直接作为纯公式；本实现不以它兜底。多个片段放入 gathered 并提示用户检查排列，不猜测对齐。
- 使用非空 `error`/`error_info` 及非 2xx 判断失败；null 不视为错误。对已知错误码显示安全的具体提示，不展示服务错误正文。读取 confidence、line_data 的低置信行及未转换行用于核查提示。置信度不能证明数学正确，也不能定位全部歧义。
- **真实接口约束（已验证）**：同时传 `include_line_data=true` 和 `include_word_data=true` 会返回 HTTP 200 + `opts_conflict`，提示两者不能同时请求。本版仅请求 line_data；保留可选 word_data 的解析兼容性。此前仅据文档与 mock 未发现这项冲突，现以真实服务行为修正。
- 官方文档列明：5 MB JSON、2 MB base64 图像、URL 下载图像 10 MB。本实现对 base64 长度采用保守的 2,000,000 字节上限，超限要求重新框选，不静默缩图丢失符号。
- 文档列出公式、文本、表格和化学图，未定义费曼图 TikZ 返回字段。本应用明确拒绝 Mathpix 费曼图模式。
- 官方价格页当前图像 0–1M 档 $0.002/张，超过 12 行文本可能按 PDF 页计费；还有账户激活费用。以账户账单及最新价格页为准，不在应用中承诺固定费用。

来源：[图像接口](https://docs.mathpix.com/reference/post-v3-text)、[认证](https://docs.mathpix.com/reference/authentication)、[价格](https://mathpix.com/pricing/api)。个人 BYOK 密钥由用户输入并存 Keychain，不将共享开发者密钥编入客户端；向他人分发服务时应重新评估服务端/app token 方案。

## OpenAI 兼容视觉 API

- 使用 `POST {Base URL}/chat/completions`、`Authorization: Bearer …`，`messages[].content` 中分别放 `text` 与 `image_url`（base64 PNG data URL）。选择此协议是为了兼容可配置端点；不是宣称所有兼容服务都支持视觉。
- 使用支持图像输入的模型，名称由用户填写。OpenAI 的推荐 Responses API 与此兼容协议不同，本版未实现 Responses 专用端点。
- 读取 `choices[0].message.content`；拒绝拒答、截断、错误响应和不符合任务格式的输出。费曼图为独立 JSON schema（code、structure、uncertainties），不复用公式解析。
- 官方视觉文档当前支持 PNG、JPEG、WEBP、非动画 GIF，总请求上限 512 MB；实际模型上下文、缩放与第三方限制不同。本应用对 PNG 自设 10 MB 保守上限，Mathpix 的限制更低。
- 图像按输入 token 计费，输出按模型输出 token 计费，金额随模型和图像尺寸/detail 变化。第三方服务以其账单为准；测试连接也会产生一次图片请求。
- 视觉模型可能误读细小符号、线型与空间连接。没有官方费曼图重建正确性保证，必须对照原图验证箭头、标签、连接；提示词要求对歧义明确标注、不按物理直觉添线。
- API Key 与 ChatGPT 订阅独立；本应用不使用 ChatGPT 登录凭据。

来源：[图像输入与视觉限制](https://developers.openai.com/api/docs/guides/images-vision?api-mode=chat)、[API 价格](https://developers.openai.com/api/docs/pricing)。

## 安全边界

只提交框选后的 PNG。凭据不出现在 URL、历史、日志或服务错误正文；HTTP 重定向被拒绝。视觉端点必须 HTTPS、无 URL 用户名/密码/查询串/片段，并将此端点的凭据单独绑定，改地址后需要重新保存。无自动重试，避免不明确地重复计费。

## 2026-10-24：Mathpix 能力、限额与余额核实

本次直接阅读 Mathpix 官方概览、限额、账单、价格与用量接口文档；没有为核实通用能力而额外发送付费识别请求，也未读取或记录真实凭据。

- **已实测能力**：当前账户已通过 `v3/text` 完成截图公式识别并取得 LaTeX。官方概览还列出单图科学文字识别、`v3/pdf` 文档转换、`v3/converter` 格式转换、`v3/strokes` 数字笔迹和 `files/v1` 批量文档处理。这些是产品通用能力，尚未逐项验证当前 Key 的权限、组织配置或识别效果，不能据文档直接承诺该 Key 全部可用。[能力概览](https://mathpix.com/docs/convert/overview)
- **用户截图中的 `200 / minute`** 是同步图像请求（`v3/text`、`v3/latex`）的每分钟速率上限；**`20000 / month` 位于 PAGE LIMIT 列**，是 `v3/pdf` 与 `files/v1` 共用的每月文档页上限。限额按单个 API Key 计算，月限额在自然月开始时重置。截图没有显示本月已用页数，也没有给出图片识别的总次数余额，不能将 20,000 页解释为可截图识别 20,000 次。[速率与页数限额](https://mathpix.com/docs/convert/limits)
- **图片默认没有月次数上限**，但可按请求为某个 Key 设置图片月上限。无默认次数上限并不表示免费或可无限免费使用；图片采用按量计费。截图无法证明当前组织有无专属套餐、额外图片上限、赠送额度或特殊单价。[图片数量限制](https://mathpix.com/docs/convert/limits)、[账单说明](https://mathpix.com/docs/convert/billing)
- **公开标准价格**：图像 OCR `v3/text` 的前 100 万张档为 **$0.002/张**，超过 100 万张的档为 $0.0015/张；超过 12 行文本的图片可能按 `v3/pdf` 的每页价格计费。标准 `v3/pdf` 前 100 万页档为 $0.005/页。以上是公开价格，不是对当前组织实际合同价格或可用余额的确认，也不能由可能采用页价推断该图片一定扣除 PAGE LIMIT。[官方价格表](https://mathpix.com/pricing/api)
- **用量接口不等于余额接口**：`GET v3/ocr-usage` 返回指定时间范围和分组下的 `ocr_usage` 记录，包括 `app_id`、`usage_type`、`count` 等；公开响应未提供总次数包、剩余次数、限额或账户信用余额字段。官方说明该数据对应控制台的按小时用量，因此统计可能延迟，识别后刷新不能保证立即增加一次。[用量接口](https://docs.mathpix.com/reference/ocr-usage)、[用量统计说明](https://mathpix.com/docs/convert/limits)
- **真实用量参数已验证**：官方 Python SDK 的 `query_usage` 支持 `group_by` 列表和 `page/per_page`。本机仅以 `usage_type` 分组时曾出现无法严格校验的记录身份；改为重复 `group_by=app_id&group_by=usage_type` 后，真实查询返回可校验的当前账号记录，成功显示当月图片已用 30 次。本实现仍拒绝缺失或非字符串账号、非整数/负数计数、溢出和可能截断的满页，不将未知记录默认为当前账号。[官方 SDK](https://raw.githubusercontent.com/Mathpix/mpxpy/master/mpxpy/mathpix_client.py)、[官方测试](https://raw.githubusercontent.com/Mathpix/mpxpy/master/tests/test_query_usage.py)
- **仅凭 OCR Key 和限额截图无法确定总剩余**：应在 Mathpix Console 的所属组织 **Billing** 中查看 `Credit balance`、本月 `Current expected usage` 和当前套餐，并结合组织合同判断。标准按量计划的信用余额用于抵扣后续账单；余额不能直接当作会自动停止服务的固定次数包。官方公开接口和用户这张限额截图不足以算出准确总剩余。软件显示官方图片用量；填写图片月上限后可估算本月剩余，填写 Billing 账单快照后可估算抵扣金可覆盖的总图片数，详见下文。[账单与信用余额](https://mathpix.com/docs/convert/billing)

### 2026-10-24 15:54 补充：可以根据账单估算可覆盖张数

用户追问后，通过现有登录会话实际只读检查并刷新了 Console Billing。该页面可提供抵扣金和本月预估费用；普通 OCR Key 的公开用量接口不包含这两个值，是当前自动获取方式的限制，不能表述为“无法换算次数”。

若取得的是已扣除所有待结算费用的净可用金额 `B`，固定单价 `p` 下可估算 `floor(max(B,0)/p)`。若取得的是账单页 Credit balance `C` 及尚未抵扣的当月 Current expected usage `U`，则估算 `floor(max(C-U,0)/p)`，需避免重复扣除。这里计算的是抵扣金预计可覆盖的普通图片数；按量后付账户在抵扣金耗尽后仍可能产生账单。网页统计延迟、金额取整、其他 Key/端点消费、超过 12 行图片页价及阶梯/合同价都会影响估算，不应标注为精确实时的服务硬剩余次数。[账单说明](https://mathpix.com/docs/convert/billing)、[官方单价](https://mathpix.com/pricing/api)

本次个人账单金额仅用于向用户答复，未保存到仓库；没有新增识别调用、账单修改或网页登录凭据提取。
