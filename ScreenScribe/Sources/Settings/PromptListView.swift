import SwiftUI

/// Row view for displaying a prompt in the list
struct PromptRowView: View {
    let prompt: Prompt
    let isDefault: Bool

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(prompt.name)
                        .fontWeight(isDefault ? .semibold : .regular)

                    if prompt.isBuiltIn {
                        Text("Built-in")
                            .font(.caption2)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Color.blue.opacity(0.15))
                            .foregroundStyle(.blue)
                            .clipShape(Capsule())
                    }
                }

                Text(prompt.copyFormat.displayName)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            if isDefault {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(.green)
                    .help("Default prompt")
            }
        }
        .contentShape(Rectangle())
    }
}

/// View for managing prompts - list, add, edit, delete
struct PromptListView: View {
    @ObservedObject private var promptManager = PromptManager.shared
    @State private var selectedPromptId: UUID?
    @State private var isShowingEditor = false
    @State private var promptToEdit: Prompt?
    @State private var isCreatingNew = false

    private var selectedPrompt: Prompt? {
        guard let id = selectedPromptId else { return nil }
        return promptManager.prompts.first { $0.id == id }
    }

    var body: some View {
        VStack(spacing: 0) {
            // List of prompts
            List(selection: $selectedPromptId) {
                Section("Built-in") {
                    ForEach(promptManager.builtInPrompts) { prompt in
                        PromptRowView(
                            prompt: prompt,
                            isDefault: prompt.id == promptManager.defaultPrompt.id
                        )
                        .tag(prompt.id)
                    }
                }

                Section("Custom") {
                    if promptManager.customPrompts.isEmpty {
                        Text("No custom prompts")
                            .foregroundStyle(.secondary)
                            .italic()
                    } else {
                        ForEach(promptManager.customPrompts) { prompt in
                            PromptRowView(
                                prompt: prompt,
                                isDefault: prompt.id == promptManager.defaultPrompt.id
                            )
                            .tag(prompt.id)
                        }
                    }
                }
            }
            .listStyle(.inset(alternatesRowBackgrounds: true))

            Divider()

            // Action bar
            HStack(spacing: 12) {
                // Add button
                Button {
                    isCreatingNew = true
                    promptToEdit = nil
                    isShowingEditor = true
                } label: {
                    Image(systemName: "plus")
                }
                .help("Create new prompt")

                // Edit button
                Button {
                    if let prompt = selectedPrompt {
                        isCreatingNew = false
                        promptToEdit = prompt
                        isShowingEditor = true
                    }
                } label: {
                    Image(systemName: "pencil")
                }
                .disabled(selectedPrompt == nil)
                .help("Edit selected prompt")

                // Delete button
                Button {
                    if let prompt = selectedPrompt, !prompt.isBuiltIn {
                        promptManager.deletePrompt(prompt)
                        selectedPromptId = nil
                    }
                } label: {
                    Image(systemName: "minus")
                }
                .disabled(selectedPrompt == nil || selectedPrompt?.isBuiltIn == true)
                .help("Delete selected prompt")

                Spacer()

                // Set as default button
                Button("Set as Default") {
                    if let prompt = selectedPrompt {
                        promptManager.setDefaultPrompt(prompt)
                    }
                }
                .disabled(selectedPrompt == nil || selectedPrompt?.id == promptManager.defaultPrompt.id)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(Color(nsColor: .windowBackgroundColor))
        }
        .sheet(isPresented: $isShowingEditor) {
            PromptEditorView(prompt: isCreatingNew ? nil : promptToEdit) { savedPrompt in
                if isCreatingNew {
                    promptManager.addPrompt(savedPrompt)
                } else {
                    promptManager.updatePrompt(savedPrompt)
                }
            }
        }
    }
}

struct PromptListViewPreview1: PreviewProvider {
    static var previews: some View {
    PromptListView()
        .frame(width: 400, height: 350)
    }
}
