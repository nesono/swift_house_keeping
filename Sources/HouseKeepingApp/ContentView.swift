import HouseKeeping
import SwiftUI

struct ContentView: View {
    @Bindable var model: AppModel
    @Binding var selection: Page?
    @State private var confirmReload = false
    @Environment(\.scenePhase) private var scenePhase

    enum Page: String, CaseIterable, Identifiable {
        case rules = "Rules"
        case settings = "Settings"

        var id: String {
            rawValue
        }

        var icon: String {
            self == .rules ? "line.3.horizontal.decrease.circle" : "gearshape"
        }
    }

    var body: some View {
        NavigationSplitView {
            VStack(alignment: .leading, spacing: 0) {
                Label("House Keeping", systemImage: "sparkles")
                    .font(.headline)
                    .padding(20)
                List(Page.allCases, selection: $selection) { page in
                    Label(page.rawValue, systemImage: page.icon).tag(page)
                }
                .listStyle(.sidebar)
                VStack(alignment: .leading, spacing: 6) {
                    Label(model.running ? "Daemon running" : "Daemon stopped", systemImage: "circle.fill")
                        .foregroundStyle(model.running ? .green : .secondary)
                    Text("Once started, the daemon keeps running after you close this app.")
                        .foregroundStyle(.secondary)
                }
                .font(.caption)
                .padding(20)
            }
            .navigationSplitViewColumnWidth(min: 180, ideal: 200, max: 240)
        } detail: {
            VStack(spacing: 0) {
                if selection == .settings {
                    SettingsView(model: model)
                } else {
                    RulesView(model: model)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .safeAreaInset(edge: .bottom, spacing: 0) {
                if let message = model.message {
                    StatusMessageView(message: message, isError: model.isError, validationID: model.validationID)
                }
            }
            .navigationTitle(selection?.rawValue ?? "Rules")
            .toolbar { rulesToolbar }
        }
        .frame(minWidth: 720, minHeight: 500)
        .confirmationDialog("Discard your unsaved edits and reload from disk?", isPresented: $confirmReload) {
            Button("Discard and Reload", role: .destructive) { model.reload() }
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { model.refreshStatus() }
        }
        .task {
            while !Task.isCancelled {
                model.refreshStatus()
                do { try await Task.sleep(for: .seconds(3)) } catch { break }
            }
        }
    }

    @ToolbarContentBuilder
    private var rulesToolbar: some ToolbarContent {
        if selection != .settings {
            ToolbarItemGroup(placement: .primaryAction) {
                Button {
                    if model.isDirty { confirmReload = true } else { model.reload() }
                } label: {
                    Label("Reload", systemImage: "arrow.clockwise")
                }
                .help("Reload configuration from disk")

                Button {
                    model.validate()
                } label: {
                    Label("Validate Rules", systemImage: "checkmark.circle")
                }
                .help("Validate rules (⌘K)")
                .disabled(model.document == nil)

                Button {
                    model.save()
                } label: {
                    Label("Save Rules", systemImage: "square.and.arrow.down")
                }
                .help("Save rules (⌘S)")
                .disabled(!model.isDirty || model.isBusy)
            }
        }
    }
}
