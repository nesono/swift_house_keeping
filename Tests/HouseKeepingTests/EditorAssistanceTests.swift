import Foundation
@testable import HouseKeeping
import Testing

private let editorFixture = """
version: 1
global:
  log_level: info
  log_file: ~/Library/Logs/house_keeping/house_keeping.log
  state_file: ~/.local/share/house_keeping/state.db
rules:
  - name: example
    enabled: false
    trigger: { type: schedule, interval: 1h }
    watch_paths: [/]
    conditions: { all: [] }
    actions:
      - log: "Found {name}"

"""

private func highlighted(_ text: String, _ kind: SyntaxToken.Kind) -> [String] {
    YAMLSyntax.tokens(in: text).filter { $0.kind == kind }.map { (text as NSString).substring(with: $0.range) }
}

@Test func yamlHighlightingDistinguishesKeysLiteralsAndComments() {
    let text = "version: 1\nenabled: false # a comment\ntrigger: { type: schedule, interval: 1h }\n"
    #expect(highlighted(text, .key) == ["version", "enabled", "trigger", "type", "interval"])
    #expect(highlighted(text, .number) == ["1"])
    #expect(highlighted(text, .literal) == ["false"])
    #expect(highlighted(text, .comment) == ["# a comment"])
    #expect(highlighted(text, .string).contains("1h"))
}

@Test func yamlQuotesCommentsAndPlainApostrophesDoNotLeakHighlighting() {
    let text = "\"name\": \"😀 # not a comment\"\nlog: Joe's file\nenabled: true\n# 'not a string'\n"
    #expect(highlighted(text, .key) == ["\"name\"", "log", "enabled"])
    #expect(highlighted(text, .string).contains("\"😀 # not a comment\""))
    #expect(highlighted(text, .literal) == ["true"])
    #expect(highlighted(text, .comment) == ["# 'not a string'"])
}

@Test func yamlBlockScalarsKeepContentAsText() {
    let text = "log: |\n  # text, not a comment\n  enabled: false\nname: next\n"
    #expect(highlighted(text, .key) == ["log", "name"])
    #expect(highlighted(text, .comment).isEmpty)
    #expect(highlighted(text, .literal).isEmpty)
    #expect(highlighted(text, .string).contains { $0.contains("enabled: false") })
}

@Test func yamlHighlightingWorksWithIncompleteQuotesAndUnicode() {
    let text = "name: \"😀 unfinished\n"
    let tokens = YAMLSyntax.tokens(in: text)
    #expect(tokens.contains { $0.kind == .key })
    #expect(highlighted(text, .string) == ["\"😀 unfinished\n"])
    #expect(tokens.allSatisfy { Range($0.range, in: text) != nil })
}

@Test func editorAcceptsValidConfigurationWithoutDiagnostics() {
    #expect(ConfigDiagnostics.analyze(editorFixture).isEmpty)
    #expect(ConfigDiagnostics.analyze(ConfigDocument.starter).isEmpty)
}

@Test func editorReportsSyntaxErrorAtItsSourceLocation() {
    let text = editorFixture + "invalid: [}\n"
    let issues = ConfigDiagnostics.analyze(text)
    #expect(issues.count == 1)
    #expect(issues.first?.severity == .error)
    #expect(issues.first?.line == 14)
    #expect(issues.first?.column == 11)
}

@Test func editorReportsMissingAndMistypedProperties() {
    let missing = editorFixture.replacingOccurrences(of: "    trigger: { type: schedule, interval: 1h }\n", with: "")
    #expect(ConfigDiagnostics.analyze(missing).contains { $0.message.contains("Missing key 'trigger'") })
    let invalid = editorFixture.replacingOccurrences(of: "enabled: false", with: "enabled: perhaps")
    let issue = ConfigDiagnostics.analyze(invalid).first
    #expect(issue?.line == 8)
    #expect(issue?.severity == .error)
    if let issue {
        #expect((invalid as NSString).substring(with: issue.range) == "perhaps")
    }
}

@Test func editorSharesCLIValidationAndLocatesIntervals() throws {
    let text = editorFixture.replacingOccurrences(of: "interval: 1h", with: "interval: tomorrow")
    let config = try ConfigLoader().parse(text)
    let errors = ConfigLoader().validate(config)
    let issues = ConfigDiagnostics.analyze(text)
    #expect(issues.map(\.message) == errors)
    #expect(issues.first?.line == 9)
    #expect(issues.first.map { (text as NSString).substring(with: $0.range) } == "tomorrow")
}

@Test func editorSuggestsUnknownKeysInNestedMappings() {
    let text = editorFixture.replacingOccurrences(of: "interval:", with: "intervl:")
        .replacingOccurrences(of: "- log:", with: "- loog:")
    let issues = ConfigDiagnostics.analyze(text)
    #expect(issues.contains { $0.message == "Unknown key 'intervl'. Did you mean 'interval'?" && $0.line == 9 })
    #expect(issues.contains { $0.message == "Unknown key 'loog'. Did you mean 'log'?" && $0.line == 13 })
}

@Test func editorFindsUnknownKeysEvenWhenConfigurationDecodes() {
    let text = editorFixture.replacingOccurrences(of: "enabled: false", with: "enabled: false\n    enabld: true")
    let issues = ConfigDiagnostics.analyze(text)
    #expect(issues.count == 1)
    #expect(issues.first?.severity == .warning)
    #expect(issues.first?.message.contains("'enabled'") == true)
}

@Test func editorReportsDuplicateMappingKeys() {
    let text = editorFixture.replacingOccurrences(of: "enabled: false", with: "enabled: false\n    enabled: true")
    #expect(ConfigDiagnostics.analyze(text).contains { $0.message.contains("Duplicate key 'enabled'") })
}

@Test func editorDiagnosticOffsetsHandleEmojiAndCRLF() {
    // Use a complete flow mapping to locate a decoding failure after a non-BMP scalar.
    let flow = "version: 1\r\nglobal: {log_level: info, log_file: /dev/null, state_file: /dev/null}\r\n"
        + "rules: [{ name: \"😀 café\", enabled: perhaps }]\r\n"
    let issues = ConfigDiagnostics.analyze(flow)
    #expect(issues.first?.line == 3)
    #expect(issues.first.map { (flow as NSString).substring(with: $0.range) } == "perhaps")
}

@Test func editorReportsMissingWatchDirectoriesWithoutWritingFiles() {
    let path = "/nonexistent-house-keeping-\(UUID().uuidString)"
    let text = editorFixture.replacingOccurrences(of: "watch_paths: [/", with: "watch_paths: [\(path)")
    let issues = ConfigDiagnostics.analyze(text)
    #expect(issues.contains { $0.message.contains("watch path does not exist") && $0.line == 10 })
}

@Test func emptyAndEndOfFileDiagnosticsHaveValidRanges() {
    for text in ["", "rules: [", "\n# comment\n"] {
        let diagnostics = ConfigDiagnostics.analyze(text)
        #expect(!diagnostics.isEmpty)
        #expect(diagnostics.allSatisfy { NSMaxRange($0.range) <= (text as NSString).length })
    }
}
