import HouseKeeping
import SwiftUI

struct DiagnosticsView: View {
    let diagnostics: [EditorDiagnostic]
    let isChecking: Bool
    let select: (EditorDiagnostic) -> Void
    @State private var expanded = true

    var body: some View {
        if isChecking {
            Label("Checking rules…", systemImage: "ellipsis.circle")
                .font(.caption)
                .foregroundStyle(.secondary)
        } else if diagnostics.isEmpty {
            Label("No issues found", systemImage: "checkmark.circle")
                .font(.caption)
                .foregroundStyle(.secondary)
        } else {
            DisclosureGroup(isExpanded: $expanded) {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 6) {
                        ForEach(diagnostics) { diagnostic in
                            Button {
                                select(diagnostic)
                            } label: {
                                HStack(alignment: .top, spacing: 8) {
                                    Image(systemName: diagnostic.severity == .error ? "xmark.circle" : "exclamationmark.triangle")
                                        .foregroundStyle(diagnostic.severity == .error ? Color.red : Color.orange)
                                    Text("Line \(diagnostic.line):\(diagnostic.column)")
                                        .monospacedDigit()
                                        .foregroundStyle(.secondary)
                                    Text(diagnostic.message)
                                        .frame(maxWidth: .infinity, alignment: .leading)
                                }
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                            .help("Jump to this issue in the editor")
                        }
                    }
                    .padding(.vertical, 6)
                }
                .frame(maxHeight: 100)
            } label: {
                let errors = diagnostics.count(where: { $0.severity == .error })
                Text("\(errors) errors, \(diagnostics.count - errors) warnings")
            }
            .font(.caption)
        }
    }
}
