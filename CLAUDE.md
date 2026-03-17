# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

A macOS daemon (Swift 6.2, macOS 14+) that watches folders and automatically organizes files based on YAML-configured rules. Rules combine triggers (schedule or FSEvents), conditions (age, size, tags, download source, etc.), and actions (move, tag, trash, notify, etc.).

## Build & Test Commands

```bash
swift build                        # Debug build
swift build -c release             # Release build
swift test                         # Run all tests
swift test --filter ConfigTests    # Run a specific test suite
```

The executable is `house-keeping` (hyphenated); the CLI command name is `house_keeping` (underscored).

## Pre-commit Hooks

Pre-commit runs on every commit: trailing-whitespace, end-of-file-fixer, check-yaml, check-merge-conflict, SwiftLint (`--strict`), and SwiftFormat. Install with `pre-commit install`.

## Linting & Formatting

- **SwiftLint** config: `.swiftlint.yml` — line length warning at 150, error at 200; function body max 80/120; `.build` excluded
- **SwiftFormat** config: default (version 0.59.1)
- Both run automatically via pre-commit hooks

## Architecture

Two SPM targets:

- **`HouseKeeping`** (library) — all core logic, depends on Yams (YAML parsing) and GRDB (SQLite state persistence)
- **`house-keeping`** (executable) — CLI layer using swift-argument-parser, depends on the library

### Library modules (`Sources/HouseKeeping/`)

| Directory | Purpose |
|-----------|---------|
| `Config/` | `ConfigLoader` parses YAML into `ConfigModels` (rules, triggers, conditions, actions) |
| `Engine/` | `RuleEngine` orchestrates rule evaluation; `ConditionEvaluator` matches files; `FileIntrospector` reads metadata (xattrs, Finder tags, quarantine); `Logger` handles logging |
| `Actions/` | `ActionExecutor` runs actions (move, tag, trash, notify, etc.) with template variable expansion |
| `Daemon/` | `DaemonRunner` — main run loop, signal handling, config hot-reload |
| `Scheduler/` | `RuleScheduler` manages schedule-based trigger timing |
| `Watcher/` | `FSEventWatcher` wraps macOS FSEvents API for file-change triggers |
| `State/` | `StateStore` tracks processed files in SQLite via GRDB |

### CLI commands (`Sources/house-keeping/Commands/`)

Each CLI subcommand (daemon, check, list, run, dry-run, status, inspect, install, uninstall) is a separate file implementing `AsyncParsableCommand`.

## Testing

Tests use Swift Testing (`import Testing`, `@Test` functions, `#expect` macros) — not XCTest. Test target: `HouseKeepingTests`.
