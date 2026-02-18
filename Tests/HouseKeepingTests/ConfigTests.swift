import Foundation
@testable import HouseKeeping
import Testing

@Test func parseSimpleConfig() throws {
    let yaml = """
    version: 1
    global:
      log_level: info
      log_file: ~/Library/Logs/house_keeping/house_keeping.log
      state_file: ~/.local/share/house_keeping/state.db
    rules:
      - name: test-rule
        trigger:
          type: schedule
          interval: 1h
        watch_paths:
          - /tmp
        conditions:
          all:
            - age_days: { gt: 7 }
        actions:
          - log: "Found {name}"
    """

    let loader = ConfigLoader()
    let config = try loader.parse(yaml)

    #expect(config.version == 1)
    #expect(config.rules.count == 1)
    #expect(config.rules[0].name == "test-rule")
    #expect(config.rules[0].trigger.type == .schedule)
    #expect(config.rules[0].trigger.interval == "1h")
    #expect(config.rules[0].watchPaths == ["/tmp"])
}

@Test func parseFileChangeRule() throws {
    let yaml = """
    version: 1
    global:
      log_level: debug
      log_file: /tmp/test.log
      state_file: /tmp/test.db
    rules:
      - name: watch-rule
        trigger:
          type: file_change
          events: [create, modify]
        watch_paths:
          - /tmp
        conditions:
          all:
            - extension: [pdf, docx]
            - downloaded_from:
                pattern: "linkedin\\\\.com"
        actions:
          - move: /tmp/organized
          - set_tag: Green
    """

    let loader = ConfigLoader()
    let config = try loader.parse(yaml)

    #expect(config.rules[0].trigger.type == .fileChange)
    #expect(config.rules[0].trigger.events == [.create, .modify])
}

@Test func parseComplexConditions() throws {
    let yaml = """
    version: 1
    global:
      log_level: info
      log_file: /tmp/test.log
      state_file: /tmp/test.db
    rules:
      - name: complex-rule
        trigger: { type: schedule, interval: 1d }
        watch_paths: [/tmp]
        conditions:
          all:
            - age_days: { gt: 30 }
            - has_tag: Orange
            - not:
                has_tag: Blue
            - size: { gt: 500MB }
        actions:
          - trash: true
          - notify: { title: "test", body: "Trashed {name}" }
    """

    let loader = ConfigLoader()
    let config = try loader.parse(yaml)
    #expect(config.rules.count == 1)
}

@Test func intervalParsing() {
    #expect(Trigger.parseInterval("1h") == 3600)
    #expect(Trigger.parseInterval("30m") == 1800)
    #expect(Trigger.parseInterval("1d") == 86400)
    #expect(Trigger.parseInterval("30s") == 30)
}

@Test func sizeParsing() {
    #expect(SizeComparison.parseSize("500MB") == 500_000_000)
    #expect(SizeComparison.parseSize("1GB") == 1_000_000_000)
    #expect(SizeComparison.parseSize("10KB") == 10000)
    #expect(SizeComparison.parseSize("1024") == 1024)
}

@Test func comparisonEvaluation() {
    let gt = Comparison(gt: 7)
    #expect(gt.evaluate(10) == true)
    #expect(gt.evaluate(7) == false)
    #expect(gt.evaluate(5) == false)

    let between = Comparison(gt: 5, lt: 10)
    #expect(between.evaluate(7) == true)
    #expect(between.evaluate(5) == false)
    #expect(between.evaluate(10) == false)
}

@Test func sizeComparisonEvaluation() {
    let comp = SizeComparison(gt: "10MB", lt: "500MB")
    #expect(comp.evaluate(100_000_000) == true)
    #expect(comp.evaluate(5_000_000) == false)
    #expect(comp.evaluate(600_000_000) == false)

    let betweenComp = SizeComparison(between: ["10MB", "500MB"])
    #expect(betweenComp.evaluate(100_000_000) == true)
    #expect(betweenComp.evaluate(5_000_000) == false)
}

@Test func pathExpansion() {
    let path = Config.expandPath("~/Downloads")
    #expect(!path.hasPrefix("~"))
    #expect(path.hasSuffix("/Downloads"))
}

@Test func templateExpansion() {
    let executor = ActionExecutor(dryRun: true)
    let metadata = FileMetadata(
        url: URL(fileURLWithPath: "/tmp/test.pdf"),
        path: "/tmp/test.pdf",
        name: "test.pdf",
        ext: "pdf",
        size: 1024,
        creationDate: Date(),
        modificationDate: Date(),
        isDirectory: false,
        tags: ["Red", "Blue"],
        downloadURL: "https://example.com/test.pdf",
        quarantineAgentName: nil,
        isQuarantined: false,
        uti: "com.adobe.pdf",
    )

    let result = executor.expandTemplate(
        "File {name} ext={ext} size={size_human} tags={tags}",
        metadata: metadata,
        ruleName: "test-rule",
    )
    #expect(result.contains("test.pdf"))
    #expect(result.contains("ext=pdf"))
    #expect(result.contains("Red, Blue"))
}
