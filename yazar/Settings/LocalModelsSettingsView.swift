import SwiftUI

/// Picks the notes engine, and — for the local one — installs the `mlx-lm`
/// runtime, chooses a model, and downloads it.
///
/// `NotesSettingsView` stays the paste-a-transcript page; this one is about the
/// engine underneath it, which is shared with roadmap item 1's dictation
/// cleanup.
struct LocalModelsSettingsView: View {
    @Bindable var settings: Settings
    @Bindable var engine: LocalLLMEngine

    @State private var customModel = ""
    @State private var isAddingCustomModel = false
    @FocusState private var customModelFocused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            SettingsSection("Engine") {
                SettingsRow("Notes engine", description: settings.languageModelProvider.summary) {
                    Picker("Notes engine", selection: $settings.languageModelProvider) {
                        ForEach(LanguageModelProvider.allCases) { provider in
                            Text(provider.displayName).tag(provider)
                        }
                    }
                    .labelsHidden()
                    .frame(width: 220, alignment: .trailing)
                }

                RowDivider()
                runtimeRow
            }

            if engine.isInstalled {
                SettingsSection("Model") {
                    SettingsRow(
                        "Model",
                        description: "Hugging Face repo run on this Mac. Downloaded on first use."
                    ) {
                        modelMenu
                    }

                    RowDivider()

                    SettingsRow("Weights", description: modelStateDescription) {
                        modelStateControl
                    }
                }

                SettingsSection("Storage") {
                    SettingsRow(
                        "On disk",
                        description: "Runtime and downloaded models under Application Support."
                    ) {
                        HStack(spacing: 8) {
                            Text(engine.diskUsage.formatted(.byteCount(style: .file)))
                                .font(.system(size: 12))
                                .foregroundStyle(.secondary)
                            Button("Reveal") { engine.revealInFinder() }
                        }
                    }

                    RowDivider()

                    SettingsRow(
                        "Downloaded models",
                        description: "Remove model weights but keep the runtime installed."
                    ) {
                        Button("Remove Models", role: .destructive) {
                            engine.removeDownloadedModels()
                        }
                    }
                }
            }
        }
        .sheet(isPresented: $isAddingCustomModel) { customModelSheet }
        .onAppear {
            engine.refreshDiskUsage()
            engine.refreshModelState(for: settings.localModel)
        }
        .onChange(of: settings.localModel) { _, model in
            engine.refreshModelState(for: model)
        }
    }

    // MARK: Runtime row

    @ViewBuilder
    private var runtimeRow: some View {
        switch engine.installState {
        case .notInstalled:
            SettingsRow(
                "Runtime",
                description: "Downloads a package manager, a private copy of Python, and mlx-lm — about 350 MB. Models are separate."
            ) {
                Button("Install") { engine.install() }
                    .buttonStyle(.borderedProminent)
            }
        case .installing(let progress):
            SettingsRow("Runtime", description: progress.step.label) {
                HStack(spacing: 8) {
                    ProgressView().controlSize(.small)
                    Button("Cancel") { engine.cancelInstall() }
                }
            }
        case .installed(let version):
            SettingsRow("Runtime", description: "mlx-lm \(version) is installed on this Mac.") {
                HStack(spacing: 8) {
                    GrantedLabel("Installed")
                    Button("Remove", role: .destructive) { engine.uninstall() }
                }
            }
        case .failed(let message):
            SettingsRow("Runtime", description: message) {
                Button("Try Again") { engine.install() }
            }
        }
    }

    // MARK: Model menu

    private var modelMenu: some View {
        Menu {
            Section("Suggested Models") {
                ForEach(SuggestedLocalModel.all) { model in
                    Toggle(isOn: selectionOf(model.id)) {
                        Text(model.id)
                        Text(model.summary)
                    }
                }
            }

            if !isSuggested(settings.localModel) {
                Section("Custom Model") {
                    Toggle(isOn: selectionOf(settings.localModel)) {
                        Text(settings.localModel)
                    }
                }
            }

            Button("Add a Custom Model…") { startAddingCustomModel() }
        } label: {
            Text(settings.localModel)
        }
        .frame(width: 220)
    }

    @ViewBuilder
    private var modelStateControl: some View {
        switch engine.modelState {
        case .notDownloaded:
            Button("Download") { engine.prepare(model: settings.localModel) }
                .buttonStyle(.bordered)
        case .downloading:
            ProgressView().controlSize(.small)
        case .ready:
            GrantedLabel("Downloaded")
        case .failed:
            Button("Retry") { engine.prepare(model: settings.localModel) }
                .buttonStyle(.bordered)
        }
    }

    private var modelStateDescription: String {
        switch engine.modelState {
        case .notDownloaded:
            "Not on this Mac yet. Downloading can take several minutes and gigabytes."
        case .downloading(let line):
            line ?? "Downloading and loading the model…"
        case .ready:
            "Loaded and ready."
        case .failed(let message):
            message
        }
    }

    // MARK: Custom model sheet

    private func selectionOf(_ model: String) -> Binding<Bool> {
        Binding {
            settings.localModel == model
        } set: { isSelected in
            if isSelected { settings.localModel = model }
        }
    }

    private func isSuggested(_ model: String) -> Bool {
        SuggestedLocalModel.all.contains { $0.id == model }
    }

    private func startAddingCustomModel() {
        customModel = isSuggested(settings.localModel) ? "" : settings.localModel
        isAddingCustomModel = true
    }

    private var trimmedCustomModel: String {
        customModel.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var customModelSheet: some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 3) {
                Text("Add a Custom Model")
                    .font(.system(size: 13, weight: .semibold))
                Text("Enter a Hugging Face repo id, for example mlx-community/Qwen3-8B-4bit. MLX-format models only.")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            TextField("org/model", text: $customModel)
                .textFieldStyle(.roundedBorder)
                .focused($customModelFocused)

            HStack {
                Spacer()
                Button("Cancel") { isAddingCustomModel = false }
                    .keyboardShortcut(.cancelAction)
                Button("Add") {
                    settings.localModel = trimmedCustomModel
                    isAddingCustomModel = false
                }
                .keyboardShortcut(.defaultAction)
                .disabled(trimmedCustomModel.isEmpty)
            }
        }
        .padding(20)
        .frame(width: 360)
        .onAppear { customModelFocused = true }
    }
}

#Preview {
    LocalModelsSettingsView(settings: Settings(), engine: LocalLLMEngine())
}
