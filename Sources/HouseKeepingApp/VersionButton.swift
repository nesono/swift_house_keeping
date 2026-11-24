import AppKit
import SwiftUI

struct VersionButton: View {
    let version: String
    var prefix = ""
    @State private var copied = false

    var body: some View {
        Button {
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(version, forType: .string)
            copied = true
        } label: {
            Label(copied ? "Copied" : "\(prefix)\(version)", systemImage: copied ? "checkmark" : "doc.on.doc")
                .labelStyle(.titleAndIcon)
        }
        .buttonStyle(.link)
        .help("Copy version number")
        .task(id: copied) {
            guard copied else { return }
            do { try await Task.sleep(for: .seconds(1.5)) } catch { return }
            copied = false
        }
    }
}
