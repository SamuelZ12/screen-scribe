import SwiftUI

/// View for editing or creating a prompt
struct PromptEditorView: View {
    @Environment(\.dismiss) private var dismiss

    let isNew: Bool
    let originalPrompt: Prompt?
    let onSave: (Prompt) -> Void

    @State private var name: String
    @State private var content: String
    @State private var copyFormat: Prompt.CopyFormat

    private var isBuiltIn: Bool {
        originalPrompt?.isBuiltIn ?? false
    }

    init(prompt: Prompt?, onSave: @escaping (Prompt) -> Void) {
        self.isNew = prompt == nil
        self.originalPrompt = prompt
        self.onSave = onSave

        _name = State(initialValue: prompt?.name ?? "")
        _content = State(initialValue: prompt?.content ?? "")
        _copyFormat = State(initialValue: prompt?.copyFormat ?? .lineBreaks)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            // Header
            Text(isNew ? "New Prompt" : (isBuiltIn ? "Edit Copy Format" : "Edit Prompt"))
                .font(.headline)

            // Name field
            VStack(alignment: .leading, spacing: 4) {
                Text("Name")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)

                TextField("Prompt name", text: $name)
                    .textFieldStyle(.roundedBorder)
                    .disabled(isBuiltIn)

                if isBuiltIn {
                    Text("Built-in prompt names cannot be changed")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            // Content field
            VStack(alignment: .leading, spacing: 4) {
                Text("Prompt Content")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)

                TextEditor(text: $content)
                    .font(.system(.body, design: .monospaced))
                    .frame(minHeight: 200)
                    .scrollContentBackground(.hidden)
                    .padding(8)
                    .background(Color(nsColor: .textBackgroundColor))
                    .clipShape(RoundedRectangle(cornerRadius: 6))
                    .overlay(
                        RoundedRectangle(cornerRadius: 6)
                            .stroke(Color(nsColor: .separatorColor), lineWidth: 1)
                    )
                    .disabled(isBuiltIn)

                if isBuiltIn {
                    Text("Built-in prompt content cannot be modified")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            // Copy format picker
            VStack(alignment: .leading, spacing: 4) {
                Text("Copy Format")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)

                Picker("", selection: $copyFormat) {
                    ForEach(Prompt.CopyFormat.allCases, id: \.self) { format in
                        Text(format.displayName).tag(format)
                    }
                }
                .pickerStyle(.segmented)
                .labelsHidden()

                Text("How to format the output when copying to clipboard")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            // Buttons
            HStack {
                Spacer()

                Button("Cancel") {
                    dismiss()
                }
                .keyboardShortcut(.escape)

                Button(isNew ? "Create" : "Save") {
                    savePrompt()
                }
                .keyboardShortcut(.return)
                .buttonStyle(.borderedProminent)
                .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty && !isBuiltIn)
            }
        }
        .padding(20)
        .frame(width: 500, height: 480)
    }

    private func savePrompt() {
        let trimmedName = name.trimmingCharacters(in: .whitespaces)
        let trimmedContent = content.trimmingCharacters(in: .whitespacesAndNewlines)

        if isNew {
            // Create new prompt
            let newPrompt = Prompt(
                name: trimmedName,
                content: trimmedContent,
                copyFormat: copyFormat
            )
            onSave(newPrompt)
        } else if let original = originalPrompt {
            // Update existing prompt
            var updatedPrompt = original
            if !isBuiltIn {
                updatedPrompt.name = trimmedName
                updatedPrompt.content = trimmedContent
            }
            updatedPrompt.copyFormat = copyFormat
            onSave(updatedPrompt)
        }

        dismiss()
    }
}
