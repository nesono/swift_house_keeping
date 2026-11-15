import AppKit
import HouseKeeping
import SwiftUI

struct RulesView: View {
    @Bindable var model: AppModel
    @AppStorage("editorFontSize") private var fontSize = 13.0
    @State private var showExample = false
    @State private var diagnostics: [EditorDiagnostic] = []
    @State private var checkedText: String?
    @State private var editorSelection: EditorSelection?

    private var currentDiagnostics: [EditorDiagnostic] {
        checkedText == model.document?.text ? diagnostics : []
    }

    private static let example = """
    rules:
      - name: flag-old-files
        enabled: false
        description: "Tag files older than 7 days with Orange"
        trigger: { type: schedule, interval: 1h }
        watch_paths: [~/Downloads]
        conditions:
          all:
            - age_days: { gt: 7 }
            - not: { has_tag: Orange }
        actions:
          - set_tag: Orange
          - log: "Flagged {name} as stale"
    """

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 6) {
                Text("A little order, automatically.")
                    .font(.title2.weight(.semibold))
                Text("Rules are checked as you type. Hover over an underline or click an issue for details.")
                    .foregroundStyle(.secondary)
            }
            HStack {
                Label("config.yaml", systemImage: "doc.text")
                    .font(.callout.weight(.medium))
                Spacer()
                Text(model.document == nil ? "Unavailable" : model.isDirty ? "Unsaved changes" : "Saved")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            if model.document != nil {
                YAMLEditor(text: Binding(
                    get: { model.document?.text ?? "" },
                    set: { model.document?.text = $0 },
                ), fontSize: fontSize, diagnostics: currentDiagnostics, selection: editorSelection)
                    .padding(12)
                    .background(.background, in: RoundedRectangle(cornerRadius: 10))
                    .overlay(RoundedRectangle(cornerRadius: 10).stroke(.quaternary))
                    .accessibilityLabel("YAML configuration")
            } else {
                ContentUnavailableView("Couldn’t open configuration", systemImage: "doc.badge.ellipsis",
                                       description: Text("Check the error below and use Reload to try again."))
            }
            if model.document != nil {
                DiagnosticsView(diagnostics: currentDiagnostics, isChecking: checkedText != model.document?.text) { diagnostic in
                    editorSelection = EditorSelection(range: diagnostic.range)
                }
            }
            HStack {
                Text("Drafts are kept when you close the app.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                Button("Example Rule") { showExample = true }
            }
        }
        .padding(24)
        .task(id: model.document?.text) {
            guard let text = model.document?.text else { return }
            do { try await Task.sleep(for: .milliseconds(350)) } catch { return }
            let result = await Task.detached(priority: .userInitiated) {
                ConfigDiagnostics.analyze(text)
            }.value
            guard !Task.isCancelled else { return }
            diagnostics = result
            checkedText = text
        }
        .sheet(isPresented: $showExample) {
            exampleSheet
        }
    }

    private var exampleSheet: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Your first rule").font(.title2.bold())
            Text("Replace “rules: []” with this example, or append the list item to your existing rules. Set enabled to true when ready.")
                .foregroundStyle(.secondary)
            ScrollView {
                Text(Self.example)
                    .font(.system(.callout, design: .monospaced))
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            HStack {
                Button("Copy Example") {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(Self.example, forType: .string)
                }
                Spacer()
                Button("Done") { showExample = false }.keyboardShortcut(.defaultAction)
            }
        }
        .padding(24)
        .frame(width: 600, height: 460)
    }
}
