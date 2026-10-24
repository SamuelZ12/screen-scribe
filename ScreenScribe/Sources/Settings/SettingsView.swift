import SwiftUI
import Carbon

private class EventMonitor {
    var monitor: Any?

    init(eventMask: NSEvent.EventTypeMask, handler: @escaping (NSEvent) -> NSEvent?) {
        self.monitor = NSEvent.addLocalMonitorForEvents(matching: eventMask, handler: handler)
    }

    deinit {
        if let monitor = self.monitor {
            NSEvent.removeMonitor(monitor)
        }
    }
}

struct ShortcutRecorderButton: View {
    let label: String
    @Binding var shortcut: ShortcutMonitor.KeyboardShortcut?
    @State private var isRecording = false
    @State private var eventMonitor: EventMonitor?

    var body: some View {
        Button {
            if isRecording {
                eventMonitor = nil
                isRecording = false
            } else {
                isRecording = true
                startRecording()
            }
        } label: {
            HStack {
                Text(isRecording ? "Recording..." : (shortcut?.description ?? "Click to Record"))
                    .foregroundStyle(isRecording ? .secondary : .primary)
                if !isRecording {
                    Image(systemName: "keyboard")
                        .foregroundStyle(.secondary)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.vertical, 4)
            .padding(.horizontal, 8)
            .background(.background.secondary, in: RoundedRectangle(cornerRadius: 6))
        }
        .buttonStyle(.plain)
        .onDisappear { eventMonitor = nil; isRecording = false }
    }

    private func startRecording() {
        DispatchQueue.main.async {
            self.eventMonitor = nil
            self.eventMonitor = EventMonitor(eventMask: [.keyDown, .flagsChanged]) { event in
                if event.type == .keyDown &&
                   event.keyCode != kVK_Shift &&
                   event.keyCode != kVK_Control &&
                   event.keyCode != kVK_Option &&
                   event.keyCode != kVK_Command &&
                   event.keyCode != kVK_Function {
                    if event.keyCode == 53 { isRecording = false; self.eventMonitor = nil; return nil }
                    guard !event.modifierFlags.intersection([.command, .control, .option]).isEmpty else { return nil }
                    let newShortcut = ShortcutMonitor.KeyboardShortcut(
                        keyCode: Int(event.keyCode),
                        modifiers: event.modifierFlags
                    )
                    shortcut = newShortcut
                    isRecording = false
                    self.eventMonitor = nil
                    return nil
                } else if event.type == .flagsChanged {
                    return event
                }
                return event
            }
        }
    }
}

struct LegacySettingsView: View {
    @StateObject private var settings = SettingsManager.shared
    @ObservedObject private var shortcuts = ShortcutMonitor.shared
    @State private var apiKeyInput = ""
    @State private var credentialMessage = ""
    @State private var isValidAPIKey: Bool = false

    private func validateAPIKey(_ key: String) -> Bool {
        let trimmed = key.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.starts(with: "AIza") && trimmed.count == 39
    }

    var body: some View {
        Form {
            Section {
                HStack {
                    Button("保存 Gemini 密钥") { Task { do { try await CredentialStore.saveAsync(apiKeyInput, account: "gemini.key"); credentialMessage = "已保存到钥匙串" } catch { credentialMessage = error.localizedDescription } } }
                    Button("删除 Gemini 密钥") { Task { do { try await CredentialStore.deleteAsync("gemini.key"); apiKeyInput = ""; credentialMessage = "已删除" } catch { credentialMessage = error.localizedDescription } } }
                }
                Text(credentialMessage)
                VStack(alignment: .leading) {
                    LabeledContent("Gemini API Key:") {
                        HStack {
                            SecureField("Enter your API key", text: $apiKeyInput)
                                .textFieldStyle(.roundedBorder)
                                .frame(width: 300)
                                .onChange(of: apiKeyInput) { _, newValue in
                                    let trimmed = newValue.trimmingCharacters(in: .whitespacesAndNewlines)
                                    if newValue != trimmed {
                                        apiKeyInput = trimmed
                                    }
                                    isValidAPIKey = validateAPIKey(trimmed)
                                }
                            if !apiKeyInput.isEmpty {
                                if isValidAPIKey {
                                    Image(systemName: "checkmark.circle.fill")
                                        .foregroundColor(.green)
                                } else {
                                    Image(systemName: "xmark.circle.fill")
                                        .foregroundColor(.red)
                                }
                            }
                        }
                    }

                    if !apiKeyInput.isEmpty && !isValidAPIKey {
                        Text("Invalid API key format. Key should start with 'AIza' followed by 35 characters.")
                            .font(.caption)
                            .foregroundColor(.red)
                    }

                    Text("Get your API key from [Google AI Studio](https://makersuite.google.com/app/apikey)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .tint(.blue)
                }

                VStack(alignment: .leading, spacing: 8) {
                    LabeledContent("Gemini Model:") {
                        Picker("", selection: $settings.selectedModel) {
                            ForEach(Config.availableGeminiModels) { model in
                                Text(model.label).tag(model.id)
                            }
                        }
                        .pickerStyle(.menu)
                        .frame(width: 330)
                    }
                    Text("Choose speed / cost trade-offs for AI extraction")
                        .font(.caption).foregroundStyle(.secondary)
                }
            } header: {
                Text("API Configuration")
            } footer: {
                Text("The API key is required for AI-powered extraction")
                    .foregroundStyle(.secondary)
            }

            Section {
                ForEach(shortcuts.registrationErrors, id: \.self) { Text($0).foregroundStyle(.red) }
                LabeledContent("离线文字:") {
                    ShortcutRecorderButton(
                        label: "Text Shortcut",
                        shortcut: Binding(
                            get: { settings.textShortcut },
                            set: { settings.textShortcut = $0 }
                        )
                    )
                    .frame(width: 200)
                }

                LabeledContent("科研截图识别:") {
                    ShortcutRecorderButton(
                        label: "Default Prompt Shortcut",
                        shortcut: Binding(
                            get: { settings.defaultPromptShortcut },
                            set: { settings.defaultPromptShortcut = $0 }
                        )
                    )
                    .frame(width: 200)
                }
            } header: {
                Text("Keyboard Shortcuts")
            } footer: {
                Text("科研识别快捷键使用所选服务与任务模式。默认 ⌘⇧L；离线文字默认 ⌘⇧T。")
                    .foregroundStyle(.secondary)
            }

            Section {
                PromptListView()
                    .frame(height: 280)
            } header: {
                Text("Prompts")
            } footer: {
                Text("Manage AI prompts for extraction. Set a default prompt for the keyboard shortcut.")
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onAppear {
            Task {
                apiKeyInput = (try? await CredentialStore.readAsync("gemini.key")) ?? ""
                isValidAPIKey = validateAPIKey(apiKeyInput)
            }
        }
    }
}

struct SettingsViewPreview1: PreviewProvider {
    static var previews: some View {
    SettingsView()
    }
}

struct SettingsView: View {
    var body: some View {
        TabView {
            PhysicsSettingsView().tabItem { Text("科研识别") }
            LegacySettingsView().tabItem { Text("快捷键与原有工具") }
        }.frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
