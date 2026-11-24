import Foundation
@testable import HouseKeeping
import Testing

private func makeDir() throws -> URL {
    let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    return dir
}

@Test func originalNameStripsNumericSuffix() {
    #expect(FileIntrospector.originalName(forDuplicateName: "report (1).pdf") == "report.pdf")
    #expect(FileIntrospector.originalName(forDuplicateName: "a b (12).txt") == "a b.txt")
    #expect(FileIntrospector.originalName(forDuplicateName: "README (2)") == "README")
    #expect(FileIntrospector.originalName(forDuplicateName: "report.pdf") == nil)
    #expect(FileIntrospector.originalName(forDuplicateName: "report(1).pdf") == nil)
    #expect(FileIntrospector.originalName(forDuplicateName: "report (x).pdf") == nil)
}

@Test func detectsIdenticalDuplicate() throws {
    let dir = try makeDir()
    defer { try? FileManager.default.removeItem(at: dir) }
    try "same".write(to: dir.appendingPathComponent("a.txt"), atomically: true, encoding: .utf8)
    let copy = dir.appendingPathComponent("a (1).txt")
    try "same".write(to: copy, atomically: true, encoding: .utf8)

    let introspector = FileIntrospector()
    let metadata = try introspector.inspect(url: copy)
    #expect(introspector.isDuplicate(metadata: metadata))
    #expect(ConditionEvaluator().evaluate(.isDuplicate(true), metadata: metadata))
    #expect(!ConditionEvaluator().evaluate(.isDuplicate(false), metadata: metadata))
}

@Test func differentContentIsNotDuplicate() throws {
    let dir = try makeDir()
    defer { try? FileManager.default.removeItem(at: dir) }
    try "one".write(to: dir.appendingPathComponent("a.txt"), atomically: true, encoding: .utf8)
    let copy = dir.appendingPathComponent("a (1).txt")
    try "two".write(to: copy, atomically: true, encoding: .utf8)

    let introspector = FileIntrospector()
    #expect(try !introspector.isDuplicate(metadata: introspector.inspect(url: copy)))
}

@Test func missingOriginalIsNotDuplicate() throws {
    let dir = try makeDir()
    defer { try? FileManager.default.removeItem(at: dir) }
    let copy = dir.appendingPathComponent("a (1).txt")
    try "x".write(to: copy, atomically: true, encoding: .utf8)

    let introspector = FileIntrospector()
    #expect(try !introspector.isDuplicate(metadata: introspector.inspect(url: copy)))
}

@Test func isDuplicateParsesFromYAMLKey() throws {
    let json = Data(#"{"is_duplicate": true}"#.utf8)
    let condition = try JSONDecoder().decode(Condition.self, from: json)
    guard case .isDuplicate(true) = condition else {
        Issue.record("Expected .isDuplicate(true)")
        return
    }
}
