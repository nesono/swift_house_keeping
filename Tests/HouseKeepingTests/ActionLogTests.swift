import Foundation
@testable import HouseKeeping
import Testing

@Test func recordedActionsAreReturnedNewestFirst() throws {
    let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: dir) }
    let store = try StateStore(path: dir.appendingPathComponent("state.db").path)

    try store.recordActions(
        [ActionResult(action: "move", success: true, message: "Move a.txt → /x")],
        filePath: "/in/a.txt",
        ruleName: "Sort",
    )
    try store.recordActions(
        [
            ActionResult(action: "trash", success: true, message: "Trash b (1).txt"),
            ActionResult(action: "log", success: false, message: "Failed: boom"),
        ],
        filePath: "/in/b (1).txt",
        ruleName: "Dupes",
    )

    let entries = try store.recentActions()
    #expect(entries.count == 3)
    #expect(entries.first?.action == "log")
    #expect(entries.first?.success == false)
    #expect(entries.last?.ruleName == "Sort")
    #expect(try store.recentActions(limit: 1).count == 1)
}
