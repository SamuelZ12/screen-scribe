# 固定本地开发签名

这套工具为本机开发保存同一张签名证书，使不同版本具有相同的指定代码要求（DR）。它不会迁移旧版 ad-hoc 的录屏授权，也不会替用户授予录屏权限。

入口命令均需明确指定状态目录。建议使用仓库根目录的 `.local-signing/`，并先在 `.gitignore` 忽略它；不要放在经常清理的 `build/` 中。工具会核实目录确实被 Git 忽略、属于当前用户、权限为 `0700`，并拒绝符号链接。

```sh
python3 scripts/local-signing/local_signing.py prepare --state-dir .local-signing
python3 scripts/local-signing/local_signing.py status --state-dir .local-signing
```

`prepare` 才会创建证书和专用 Keychain。它不会激活信任，不会调用截图 API，不会读取已有 API 凭据。若配置存在，只复用原身份；配置不完整时停止，不会重新生成证书。所有密码只在内存和子进程标准输入中传递，不进入命令参数、日志或配置文件。私钥和 PKCS12 临时文件位于权限为 `0700` 的临时目录中，文件权限为 `0600`，正常退出或失败时删除。

专用 Keychain 的私钥 ACL 只允许 `/usr/bin/codesign`。专用 Keychain 的随机密码保存到登录 Keychain 的新服务 `app.screenscribe.local-signing.keychain-password.v1`，账户由状态目录的 SHA-256 派生，ACL 只允许这一个固定的 Security helper。不会读取、覆盖或修改 ScreenScribe 的 OCR/API 密钥条目。

固定 helper 编译一次后保存在状态目录。源码或该二进制变化时停止并要求明确迁移，不会自动重编译、更新密码条目 ACL 或重新生成身份。状态目录中的 `metadata.json` 只有公开路径、证书指纹、identifier、helper 校验信息和创建时间，没有密码或私钥。`status` 会静默验证密码条目可读，不打印其内容，也不解锁专用 Keychain。

创建专用 Keychain 的系统 API 可能临时把它加入搜索列表；helper 会在成功和失败时恢复原来的完整搜索列表和默认 Keychain。后续使用都通过明确路径指定专用 Keychain，不把它持久加入搜索列表。本机实测 `codesign --keychain` 仍需要从用户搜索列表中发现该身份；工具只在短时签名操作中临时注册专用 Keychain，使用操作锁串行执行，并在成功或失败后恢复原列表，且不修改默认 Keychain。若期间有独立列表变更，只移除工具自己临时加入的条目，保留外部变更。发生恢复错误时会停止并报告，不再继续签名。

## 单独激活用途受限的用户信任

此步骤必须由用户明确执行；其他命令不会自动调用它：

```sh
python3 scripts/local-signing/local_signing.py activate-trust --state-dir .local-signing
```

实际调用仅为：

```text
security add-trusted-cert -r trustRoot -p codeSign -a /usr/bin/codesign \
  -k <专用 Keychain> <本机生成的公开证书>
```

它只添加当前用户的信任设置，并同时限制到 `codeSign` 用途和 `/usr/bin/codesign` 应用。不会使用管理员/系统域、SSL、basic 或通用“始终信任”。macOS 可能要求用户认证此项明确的信任修改。证书仍仅供本机开发，不能代替 Apple Developer ID 或公证。

`security find-identity -v` 由 `security` 进程进行信任判断，在上述应用约束下可能仍显示 `0 valid identities`；不要据此放宽信任设置。签名及以下交叉验证结果才是验证依据。

## 签名

```sh
python3 scripts/local-signing/local_signing.py sign --state-dir .local-signing \
  --identifier app.samuelz12.screenscribe-dev \
  build/Local/Build/Products/Release/ScreenScribe.app
```

签名前 helper 静默读取自己的密码条目并解锁专用 Keychain，签名后立即重新锁定。签名通过证书 SHA-1 指纹精确选择身份，DR 同时要求固定 identifier 和这张证书的 leaf 指纹。不会使用仅 identifier 的弱 DR，不会自动回退 ad-hoc。工具会执行 `codesign --verify --strict --all-architectures -R` 验证该 DR。

Security helper 启动后立即调用 `SecKeychainSetUserInteractionAllowed(false)`，任何需要认证的 Security API 都应失败，不能自动放宽 ACL。**这个进程设置不会继承到 Apple 的独立 `codesign` 进程；`codesign` 没有公开的禁止认证 UI 开关。** 工具通过明确私钥 ACL、提前静默解锁和超时终止减少弹窗原因，但不能承诺系统策略改变时 `codesign` 绝不产生弹窗。发生失败或超时时停止；不会改信任、扩展 ACL 或尝试旧身份。

从旧 ad-hoc 身份切换到固定身份后，旧 cdhash 的录屏授权不能自动沿用。新身份首次录屏仍需要用户亲自授权；是否持续保持授权，必须在授权后跨两个不同代码构建实际测试。

## 已做的检查与限制

已完成 Python 语法/命令约束检查、Swift 编译；在用户明确同意后创建固定身份，并激活上述 codeSign + /usr/bin/codesign 的用户用途约束。两个不同内容的合成程序均签名与严格验证成功，实际断言 DR 相同且 CDHash 不同；ScreenScribe Release 亦已使用同一固定证书签名并严格验证。搜索列表恢复、默认 Keychain 保持、scoped 密码静默可读均已核实。用户已完成固定版录屏授权，真实框选、重启以及主 app 跨构建录屏保持已验证；凭据组件的后续验证状态见下一节。

参考：[Apple DTS 对 ad-hoc 导致录屏授权丢失的确认](https://developer.apple.com/forums/thread/819406)、[TN3127：代码指定要求](https://developer.apple.com/documentation/technotes/tn3127-inside-code-signing-requirements)、[Apple Code Signing Tasks](https://developer.apple.com/library/archive/documentation/Security/Conceptual/CodeSigningGuide/Procedures/Procedures.html)。本机 `man security` 记录了 `-p codeSign`、`-a appPath` 和用户域认证语义。

## 本地自签凭据组件（2026-10-24）

固定证书和 DR 已通过实际 app 跨构建录屏测试，但不足以稳定 legacy Keychain：没有 Apple Team ID 的程序仍按 CDHash 匹配 partition。两份同 DR、不同 CDHash 的合成程序已实际复现默认/显式 self trusted-app ACL 都被拒绝。没有通过删除 partition、开放其他应用或扩大证书信任解决它。

本地构建因此使用另一个不可变的嵌入式 XPC 服务作为新凭据条目的所有者。它不安装 daemon/LaunchAgent，不操作旧条目 ACL。入口为：

```sh
python3 scripts/local-signing/credential_xpc.py prepare --state-dir .local-signing
python3 scripts/local-signing/credential_xpc.py stage --state-dir .local-signing \
  --app build/Local/Build/Products/Release/ScreenScribe.app
```

`build-local.sh` 已顺序调用这两步，随后签主 app。首次 prepare 只编译并签一次组件，保存于 `.local-signing/credential-xpc/`；后续校验整个包的文件哈希/权限、源码、公开策略，再原样复制到 `Contents/XPCServices/ScreenScribeCredentialHelper.xpc`，不会重编译或重签。任何不一致均停止，不通过生成新 owner 或回退旧 Keychain 隐藏问题。不要删除 `.local-signing/`，也不要随意编辑已冻结的 `credential-xpc.swift`；组件升级需要显式规划新旧 owner 的凭据迁移。

服务先检查 UID，并在连接 resume 前使用公有 `NSXPCConnection.setCodeSigningRequirement` 限定每条消息的主程序固定 DR。客户端反向限定服务固定 CDHash，先 strict 静态校验包、再发不含密钥的 ping，收到可信回复后才发送操作。不能只验证父 PID，也不能把密钥放在首次未经验证的请求中。服务仅暴露 ping/read/save/delete，限制账号及输入长度；所有自身 Security API 禁交互。`JoinExistingSession=true` 使它使用本用户的钥匙串会话，不新增网络或系统访问能力。

真实合成正反测试已通过：A 保存后不同 CDHash 的 B 可读/更新/删除；错误客户端 DR、错误服务 DR、篡改服务包均被拒绝且未创建条目。公开验证范围见 [测试说明](../../docs/TESTING.md)，复验命令为 `python3 scripts/test-credential-xpc.py`。实际配置保存后，真实 app 再次构建、完整退出重启，仍自动读回凭据；最终直接框选、原图对照及官方 Mathpix 识别已于 2026-10-24 通过，未重新授权或输入密钥，也未出现录屏/钥匙串弹窗。完整操作审计与合成测试逐项记录仅保留在开发机器。
