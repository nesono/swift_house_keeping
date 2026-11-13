import Foundation

/// Shared notification delivery for the CLI and the background LaunchAgent.
public struct NotificationSender: Sendable {
    private let deliver: @Sendable (String, String) throws -> Void

    public init(deliver: @escaping @Sendable (String, String) throws -> Void) {
        self.deliver = deliver
    }

    public func send(title: String, body: String) throws {
        try deliver(title, body)
    }

    public static let system = NotificationSender { title, body in
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
        // Pass user-controlled text as arguments, never as AppleScript source.
        process.arguments = ["-e", """
        on run argv
            display notification (item 2 of argv) with title (item 1 of argv)
        end run
        """, title, body]
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        try process.run()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else {
            throw DeliveryError(status: process.terminationStatus)
        }
    }

    private struct DeliveryError: Error, CustomStringConvertible {
        let status: Int32
        var description: String {
            "Notification delivery exited with status \(status)"
        }
    }
}
