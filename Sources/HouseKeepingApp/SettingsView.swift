import SwiftUI

struct SettingsView: View {
    @Bindable var model: AppModel
    @AppStorage("appearance") private var appearance = "system"
    @AppStorage("editorFontSize") private var fontSize = 13.0

    var body: some View {
        Form {
            Section {
                Toggle(isOn: Binding(
                    get: { model.loginEnabled },
                    set: { enabled in Task { await model.setLoginEnabled(enabled) } },
                )) {
                    Text("Start at login")
                    Text("Run the housekeeping daemon in the background, even when this app is closed.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .disabled(model.isBusy || (!model.loginEnabled && (model.isDirty || model.document == nil)))
                if model.isBusy {
                    ProgressView().controlSize(.small)
                }
                if model.isDirty, !model.loginEnabled {
                    Text("Save your rules before enabling Start at login.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            } header: {
                Text("General")
            } footer: {
                Text("Enabling this starts the daemon now. Disabling it stops the launch agent and removes it from login.")
            }

            Section("Appearance") {
                Picker("Theme", selection: $appearance) {
                    Text("System").tag("system")
                    Text("Light").tag("light")
                    Text("Dark").tag("dark")
                }
                Picker("Editor text size", selection: $fontSize) {
                    Text("Small").tag(11.0)
                    Text("Default").tag(13.0)
                    Text("Large").tag(16.0)
                }
            }

            Section("Configuration & Logs") {
                LabeledContent("Configuration") {
                    Text(model.configPath)
                        .font(.caption)
                        .textSelection(.enabled)
                }
                HStack {
                    Button("Show in Finder") { model.revealConfig() }
                    Button("Open Log") { model.openLogs() }
                }
            }
        }
        .formStyle(.grouped)
    }
}
