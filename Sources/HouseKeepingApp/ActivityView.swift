import AppKit
import HouseKeeping
import SwiftUI

struct ActivityView: View {
    @Bindable var model: AppModel
    @State private var search = ""
    @State private var failuresOnly = false

    private var entries: [ActionLogEntry] {
        model.activity.filter { entry in
            if failuresOnly, entry.success { return false }
            guard !search.isEmpty else { return true }
            return [entry.ruleName, entry.action, entry.filePath, entry.message]
                .contains { $0.localizedCaseInsensitiveContains(search) }
        }
    }

    var body: some View {
        Group {
            if let error = model.activityError {
                ContentUnavailableView("Activity unavailable", systemImage: "exclamationmark.triangle", description: Text(error))
            } else if model.activity.isEmpty {
                ContentUnavailableView(
                    "No activity yet",
                    systemImage: "clock.arrow.circlepath",
                    description: Text("Actions performed by your rules will show up here."),
                )
            } else if entries.isEmpty {
                ContentUnavailableView.search
            } else {
                table
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .safeAreaInset(edge: .top, spacing: 0) { filterBar }
        .task {
            while !Task.isCancelled {
                model.refreshActivity()
                do { try await Task.sleep(for: .seconds(3)) } catch { break }
            }
        }
    }

    private var filterBar: some View {
        VStack(spacing: 0) {
            HStack {
                TextField("Filter by rule, action or file", text: $search)
                    .textFieldStyle(.roundedBorder)
                Toggle("Failures only", isOn: $failuresOnly)
                    .toggleStyle(.checkbox)
            }
            .padding(12)
            Divider()
        }
        .background(.bar)
    }

    private var table: some View {
        Table(entries) {
            TableColumn("") { entry in
                Image(systemName: entry.success ? "checkmark.circle.fill" : "xmark.octagon.fill")
                    .foregroundStyle(entry.success ? Color.green : Color.red)
                    .help(entry.success ? "Succeeded" : "Failed")
            }
            .width(24)
            TableColumn("Time") { entry in
                Text(entry.timestamp.formatted(date: .abbreviated, time: .standard))
            }
            .width(min: 120, ideal: 150)
            TableColumn("Rule") { entry in
                Text(entry.ruleName)
            }
            .width(min: 80, ideal: 140)
            TableColumn("Action") { entry in
                Text(entry.action)
            }
            .width(min: 60, ideal: 90)
            TableColumn("File") { entry in
                Text((entry.filePath as NSString).lastPathComponent)
                    .help(entry.filePath)
                    .contextMenu {
                        Button("Show in Finder") {
                            NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: entry.filePath)])
                        }
                        .disabled(!FileManager.default.fileExists(atPath: entry.filePath))
                        Button("Copy Path") {
                            NSPasteboard.general.clearContents()
                            NSPasteboard.general.setString(entry.filePath, forType: .string)
                        }
                    }
            }
            .width(min: 100, ideal: 200)
            TableColumn("Details") { entry in
                Text(entry.message).help(entry.message)
            }
        }
    }
}
