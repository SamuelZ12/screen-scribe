import SwiftUI
import AppKit

struct PhysicsSettingsView: View {
    @ObservedObject private var settings = PhysicsSettings.shared
    @ObservedObject private var usage = MathpixUsageStore.shared
    @ObservedObject private var credit = MathpixCreditStore.shared
    @State private var appID = ""
    @State private var key = ""
    @State private var message = ""
    @State private var testing = false
    @State private var saving = false
    @State private var loadTask: Task<Void, Never>?
    @State private var testTask: Task<Void, Never>?
    @State private var creditUSD = ""
    @State private var pendingUSD = ""
    @State private var imagePriceUSD = "0.002"
    @State private var billingObservedAt = Date()
    @State private var creditMessage = ""
    var body: some View {
        Form {
            Section("识别服务") {
                Picker("服务", selection: $settings.backend) { ForEach(RecognitionBackend.allCases) { Text($0.title).tag($0) } }.disabled(testing || saving)
                Picker("默认任务", selection: $settings.mode) { ForEach(RecognitionMode.allCases) { Text($0.title).tag($0) } }
                if settings.backend == .mathpix {
                    TextField("Mathpix App ID", text: $appID)
                } else {
                    TextField("API Base URL（含 /v1）", text: $settings.baseURL).disabled(testing || saving)
                    TextField("支持视觉输入的模型名称", text: $settings.model)
                    Text("仅支持 Chat Completions 图像输入协议。第三方服务需自行确认视觉能力。API Key 与 ChatGPT 订阅、登录凭据独立。")
                        .font(.caption).foregroundStyle(.secondary)
                }
                SecureField(settings.backend == .mathpix ? "Mathpix App Key" : "此端点专用 API Key", text: $key)
                Text(Bundle.main.object(forInfoDictionaryKey: "ScreenScribeCredentialServiceRequirement") != nil
                     ? "凭据保存在本机钥匙串，不会要求系统密码。填写后可测试连接；点击保存后，重启及本机更新会继续使用。"
                     : "钥匙串以静默方式访问，不会要求系统密码。填写后测试连接即可在本次运行中使用；保存成功后可供下次启动读取。")
                    .font(.caption).foregroundStyle(.secondary)
                HStack {
                    Button("读取已存凭据") { load() }.disabled(testing)
                    Button(saving ? "保存中…" : "保存凭据") { save() }.disabled(testing || saving)
                    Button("删除凭据", role: .destructive) { delete() }.disabled(testing)
                    Button(testing ? "测试中…" : "测试连接（上传测试公式）") { test() }.disabled(testing)
                    if testing { Button("取消") { testTask?.cancel() } }
                }
                Text("测试会向所选服务发送内置的 x²+1 公式小图，可能产生 API 费用。只发送此服务的凭据，不会上传屏幕。")
                    .font(.caption).foregroundStyle(.secondary)
                if !message.isEmpty { Text(message).textSelection(.enabled) }
            }
            if settings.backend == .mathpix {
                Section("总剩余额度 · 保守估算") {
                    Text(credit.statusText).fontWeight(.medium).monospacedDigit()
                    TextField("Credit balance（美元）", text: $creditUSD)
                    TextField("Current expected usage（美元）", text: $pendingUSD)
                    TextField("普通图片单价（美元/次）", text: $imagePriceUSD)
                    DatePicker("账单快照时间", selection: $billingObservedAt, displayedComponents: [.date, .hourAndMinute])
                    HStack {
                        Button("保存账单快照") { saveCredit() }
                        Button("清除估算") { credit.clearEstimate(); loadCredit(); creditMessage = "" }
                            .disabled(credit.estimate == nil)
                        Link("查看 Mathpix 账单", destination: URL(string: "https://console.mathpix.com/")!)
                    }
                    Text("费用按分向上预留，剩余次数向下取整。每次请求先本地扣 1 次，每完成 5 次查询官方用量校准；服务统计延迟时不回涨。")
                        .font(.caption).foregroundStyle(.secondary)
                    Text(credit.detailText).font(.caption).foregroundStyle(.secondary)
                    Text("余额使用你填写的账单快照。更新快照会重设本地计数；本月用量刷新不会自动读取 Billing 金额。")
                        .font(.caption).foregroundStyle(.secondary)
                    if !creditMessage.isEmpty { Text(creditMessage).font(.caption).textSelection(.enabled) }
                }
                Section("本月用量") {
                    HStack {
                        Text(usage.statusText).monospacedDigit()
                        Spacer()
                        Button("刷新用量") { Task { await refreshUsage() } }
                            .disabled(usage.refreshing || testing || saving)
                    }
                    HStack {
                        Text("图片识别月上限（可选）")
                        TextField("未设置", value: Binding(get: { usage.monthlyBudget }, set: { usage.setMonthlyBudget($0) }), format: .number)
                            .frame(width: 105).multilineTextAlignment(.trailing)
                    }
                    Text("填入实际图片月上限后显示估算剩余；0 表示未设置。这里只用于计算显示，不修改服务限额。控制台的 PAGE LIMIT 是文档页数，RATE LIMIT 是请求速率，均不能当作截图识别的总次数。")
                        .font(.caption).foregroundStyle(.secondary)
                    Text(usage.detailText).font(.caption).foregroundStyle(.secondary)
                    Link("打开 Mathpix 用量与账单", destination: URL(string: "https://console.mathpix.com/")!)
                }
            }
            Section("本地数据") {
                Toggle("在历史中保存原始截图（默认关闭）", isOn: $settings.persistImages)
                Text("关闭时仍保留文本；历史最多 50 条。关闭后请在历史窗口移除以前保存的原图。")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Section("权限与费用") {
                HStack {
                    Button("启用直接框选（系统授权）") { ScreenCapturePermissionManager.shared.openSystemSettings() }
                    Button("在 Finder 中定位此应用") { NSWorkspace.shared.activateFileViewerSelecting([Bundle.main.bundleURL]) }
                }
                Text("直接框选需要 macOS 屏幕录制授权。固定签名可维持更新前后的应用身份，旧临时版本的授权无法自动转移。请为下方路径的应用确认一次，并按系统提示重启。应用不会在后台申请权限。全局快捷键在“快捷键与原有工具”中配置。")
                Text(Bundle.main.bundleURL.path).font(.caption).foregroundStyle(.secondary).textSelection(.enabled)
                Link("Mathpix API 价格", destination: URL(string: "https://mathpix.com/pricing/api")!)
                Link("OpenAI API 价格", destination: URL(string: "https://developers.openai.com/api/docs/pricing")!)
            }
        }.formStyle(.grouped)
        .onAppear { load(); loadCredit() }.onChange(of: settings.backend) { _, _ in load(); loadCredit() }
        .onChange(of: credit.estimate) { _, _ in loadCredit() }
        .onChange(of: settings.baseURL) { _, _ in loadTask?.cancel(); key = ""; message = "端点已修改，请为新端点重新读取或保存专用密钥。" }
        .onDisappear { loadTask?.cancel(); testTask?.cancel() }
    }
    private var account: String { get throws { settings.backend == .mathpix ? "mathpix.key" : try OpenAICompatibleVisionProvider.credentialAccount(baseURL: settings.baseURL) } }
    private func loadCredit() {
        creditUSD = credit.estimate?.creditUSD ?? ""
        pendingUSD = credit.estimate?.pendingUSD ?? ""
        imagePriceUSD = credit.estimate?.imagePriceUSD ?? "0.002"
        billingObservedAt = credit.estimate?.observedAt ?? Date()
    }
    private func saveCredit() {
        guard credit.save(creditUSD: creditUSD, pendingUSD: pendingUSD, imagePriceUSD: imagePriceUSD, observedAt: billingObservedAt) else {
            creditMessage = "请先读取 Mathpix 配置，并检查金额、正数单价与快照时间。金额使用小数点，最多两位小数。"
            return
        }
        if let snapshot = usage.snapshot { credit.setUsageBaseline(imageCount: snapshot.imageCount, periodStart: snapshot.periodStart) }
        creditMessage = "账单快照已保存在本机；之后逐张扣减，每 5 次校准用量。"
    }
    private func load() {
        loadTask?.cancel()
        if let cached = settings.cachedCredentials() { appID = cached.appID; key = cached.key; return }
        loadTask = Task { @MainActor in
            do {
                let configuration = try await settings.configuration()
                try Task.checkCancellation()
                guard settings.backend == configuration.backend, settings.baseURL == configuration.baseURL,
                      settings.model == configuration.model else { return }
                appID = configuration.appID; key = configuration.apiKey; message = ""
            } catch is CancellationError {} catch { if !Task.isCancelled { message = error.localizedDescription } }
        }
    }
    private func save() {
        loadTask?.cancel()
        let id = appID.trimmingCharacters(in: .whitespacesAndNewlines)
        let secret = key.trimmingCharacters(in: .whitespacesAndNewlines)
        let selected = settings.backend
        let targetAccount: String
        do { targetAccount = try account } catch { message = error.localizedDescription; return }
        saving = true
        try? settings.rememberCredentials(RecognitionConfiguration(backend: selected, model: settings.model, baseURL: settings.baseURL, appID: id, apiKey: secret))
        Task { @MainActor in
            defer { saving = false }
            do {
                try await CredentialStore.saveAsync(secret, account: targetAccount)
                if selected == .mathpix { try await CredentialStore.saveAsync(id, account: "mathpix.id") }
                message = "凭据已保存到 macOS 钥匙串。"
            } catch { message = error.localizedDescription }
        }
    }
    private func delete() {
        loadTask?.cancel()
        settings.forgetCredentials()
        let selected = settings.backend
        let selectedBaseURL = settings.baseURL
        let targetAccount: String
        do { targetAccount = try account } catch { message = error.localizedDescription; return }
        Task { @MainActor in
            do {
                try await CredentialStore.deleteAsync(targetAccount)
                if selected == .mathpix { try await CredentialStore.deleteAsync("mathpix.id") }
                guard settings.backend == selected, settings.baseURL == selectedBaseURL else { return }
                if selected == .mathpix { appID = "" }
                key = ""; message = "凭据已删除。"
            } catch { message = error.localizedDescription }
        }
    }
    private func test() {
        // Test exactly the visible fields. Do not write and re-read Keychain on the UI thread.
        loadTask?.cancel()
        let configuration = RecognitionConfiguration(backend: settings.backend, model: settings.model, baseURL: settings.baseURL,
                                                     appID: appID.trimmingCharacters(in: .whitespacesAndNewlines),
                                                     apiKey: key.trimmingCharacters(in: .whitespacesAndNewlines))
        testing = true; message = "正在验证实际图像输入…"
        testTask = Task { @MainActor in
            defer { testing = false; testTask = nil }
            do {
                let output: RecognitionOutput
                let png = Self.testPNG()
                switch configuration.backend {
                case .mathpix:
                    let appID = configuration.appID
                    output = try await MathpixProvider(appID: appID, apiKey: configuration.apiKey, beforeSend: {
                        await MathpixCreditStore.shared.recordAttempt(appID: appID)
                    }, afterSend: {
                        await PhysicsSettings.shared.completedMathpixRequest(using: configuration)
                    }).recognize(png: png, mode: .equation)
                case .openAI: output = try await OpenAICompatibleVisionProvider(configuration: configuration).recognize(png: png, mode: .equation)
                }
                try settings.rememberCredentials(configuration)
                message = "服务接受了图像并返回：\(output.code.prefix(200))。请核对是否为 x²+1；这不验证复杂公式或费曼图准确率。"
            } catch { message = error.localizedDescription }
        }
    }
    private func refreshUsage() async {
        guard settings.backend == .mathpix else { return }
        if let configuration = try? await settings.configuration() { settings.refreshMathpixUsage(using: configuration) }
    }
    static func testPNG() -> Data {
        let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 240, pixelsHigh: 80,
                                      bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                                      colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: bitmap)
        NSColor.white.setFill(); NSRect(x: 0, y: 0, width: 240, height: 80).fill()
        ("x² + 1" as NSString).draw(at: NSPoint(x: 20, y: 20), withAttributes: [.font: NSFont.systemFont(ofSize: 32), .foregroundColor: NSColor.black])
        NSGraphicsContext.restoreGraphicsState()
        return bitmap.representation(using: .png, properties: [:])!
    }
}
