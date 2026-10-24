# Windows V0.1 验证结果

目标：普通 Intel / AMD x64 的 Windows 10/11。当前软件是独立 Windows 实现，Mac 版源代码、签名、凭据和应用均不变。

## 已完成

- `npm run check`：源代码语法与构建输入检查通过。
- `npm test`：63 项通过。使用合成账户、临时存储和 Mock HTTP；涵盖 Mathpix/视觉 API 协议与解析、失败/取消、凭据加密适配器、历史恢复、2,232 组金额组合、逐张扣减与五次校准、异步凭据/用量竞态、混合 DPI/负坐标裁剪和快捷键冲突。
- `npm run smoke`：在 Mac 的隔离 Electron 演示会话实际加载 sandbox 渲染器与 IPC。启动器必须收到版本匹配的 IPC 证据才通过，不能把已有实例退出视为成功。
- 在自有 Electron 演示窗口检查了 KaTeX 预览、Original、Data 编辑、保存后的历史以及同面板设置/视觉服务切换。演示不读 Mac 凭据，不申请录屏权限、不注册真实全局快捷键、不调用 API。
- `npm run dist:win`：生成实际 Windows x64 NSIS EXE，非网页或安装包占位。`scripts/verify-package.cjs` 检查 PE64 机器类型、ASAR 程序/资源/字体/许可、版本和本地安全边界；此前构建通过 145 项静态检查。最终打包摘要以 artifacts/package-verification.json 为准。
- npm 官方依赖审计返回 0 个已知漏洞（当次查询）；依赖版本和完整性保存在 package-lock.json。

## Windows 原生验收

已提供 `--platform-self-test` 与 CI：仅使用合成 DPAPI 凭据、内置公开图和唯一彩色测试窗，不连接真实识别账户、不上传桌面内容、不保存桌面缩略图。检查 Windows 加密持久化、快捷键、渲染器/IPC、显示器匹配与实际裁剪；唯一彩色画面对照避免纯白画面误通过。

Windows CI 还会静默安装生成的 EXE，在已安装副本运行同一自检，再卸载隔离副本。工作流仅有 contents:read 权限，不发布 Release，不修改 Mac main。

**当前正在准备独立 Windows 分支的原生 CI 验收，尚未取得 Windows 原生通过结果。** 实际 run URL、提交与报告将随运行结果更新。静态检查和 Mac 演示不等同于 Windows 实机验收。

## 必须保留的边界

尚未用真实 Windows 账户发送 Mathpix 或视觉服务请求，没有把 Mac 版真实 API 证据冒称为 Windows 版真实识别通过。真实 API 需用户自行填写密钥并明确触发；没有把 Mac 凭据迁入 Windows 项目。

多显示器混合缩放、跨显示器边界、远程桌面、受保护内容及 Windows 10 各版本仍需额外人工检查。每次框选仅覆盖起始屏幕，跨屏拖动会在该屏边缘截断。TikZ 为实验性重建，只做格式校验，不自动执行 TeX。总剩余为账单快照保守估算，usage 不提供实时 Billing 金额。
