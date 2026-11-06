import Foundation
@testable import HouseKeeping
import os
import Testing

struct ActionNotificationTests {
    private final class Notifications: Sendable {
        let messages = OSAllocatedUnfairLock(initialState: [(String, String)]())
        var sender: NotificationSender {
            NotificationSender { [self] title, body in
                messages.withLock { $0.append((title, body)) }
            }
        }
    }

    private func withFile(_ body: (FileMetadata, URL) throws -> Void) throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let file = directory.appendingPathComponent("report.txt")
        try Data("report".utf8).write(to: file)
        try body(FileIntrospector().inspect(url: file), directory)
    }

    @Test func reportsEachActionAndStopsAfterFailure() throws {
        try withFile { metadata, directory in
            let notifications = Notifications()
            let destination = directory.appendingPathComponent("archive").path
            let results = ActionExecutor(notificationSender: notifications.sender).execute(
                actions: [.copy(destination), .copy(destination), .delete(true)], on: metadata, ruleName: "Archive",
            )
            #expect(results.count == 2)
            #expect(results[0].success)
            #expect(!results[1].success)
            #expect(FileManager.default.fileExists(atPath: metadata.path))
            let messages = notifications.messages.withLock { $0 }
            #expect(messages.count == 2)
            #expect(messages[0].0.contains("Archive"))
            #expect(messages[0].1.contains("report.txt"))
            #expect(messages[0].1.contains(destination))
            #expect(messages[1].0.contains("failed"))
        }
    }

    @Test func dryRunsAndDisabledActionsStaySilent() throws {
        try withFile { metadata, _ in
            let notifications = Notifications()
            let dryResults = ActionExecutor(dryRun: true, notificationSender: notifications.sender).execute(
                actions: [.delete(true), .notify(.init(title: "Test", body: "Test"))], on: metadata, ruleName: "Preview",
            )
            let skippedResults = ActionExecutor(notificationSender: notifications.sender).execute(
                actions: [.trash(false), .delete(false), .removeQuarantine(false)], on: metadata, ruleName: "Disabled",
            )
            #expect(!dryResults.contains { !$0.success })
            #expect(!skippedResults.contains { !$0.success })
            #expect(notifications.messages.withLock { $0.isEmpty })
            #expect(FileManager.default.fileExists(atPath: metadata.path))
        }
    }

    @Test func explicitNotificationIsDeliveredOnceWithExpandedText() throws {
        try withFile { metadata, _ in
            let notifications = Notifications()
            let results = ActionExecutor(notificationSender: notifications.sender).execute(
                actions: [.notify(.init(title: "{rule_name}", body: "\"{name}\"\\\nDone"))], on: metadata, ruleName: "Archive",
            )
            #expect(results[0].success)
            let messages = notifications.messages.withLock { $0 }
            #expect(messages.count == 1)
            #expect(messages[0].0 == "Archive")
            #expect(messages[0].1 == "\"report.txt\"\\\nDone")
        }
    }

    @Test func deliveryFailureDoesNotInterruptFileActions() throws {
        struct Unavailable: Error {}
        try withFile { metadata, directory in
            let sender = NotificationSender { _, _ in throw Unavailable() }
            let results = ActionExecutor(notificationSender: sender).execute(
                actions: [.copy(directory.appendingPathComponent("archive").path), .delete(true)],
                on: metadata, ruleName: "Archive",
            )
            #expect(results.count == 2)
            #expect(!results.contains { !$0.success })
            #expect(!FileManager.default.fileExists(atPath: metadata.path))
            let explicit = ActionExecutor(notificationSender: sender).execute(
                actions: [.notify(.init(title: "Test", body: "Test"))], on: metadata, ruleName: "Archive",
            )
            #expect(!explicit[0].success)
        }
    }
}
