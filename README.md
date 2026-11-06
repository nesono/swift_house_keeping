# house_keeping

A macOS daemon that watches folders and automatically organizes files based on configurable rules. Define triggers (file events or schedules), conditions (age, size, tags, download source, etc.), and actions (move, tag, trash, notify) — all in a single YAML config file.

## Requirements

- macOS 14+
- Swift 6.2+

## Installation

To build a macOS installer package from this checkout (requires Swift 6.2+):

```bash
bash scripts/build-pkg.sh
```

Double-click the resulting `.pkg` in Finder. It installs **House Keeping.app** in
`/Applications` and the command-line tool at `/usr/local/bin/house_keeping`.
Open **House Keeping** to edit your rules and enable **Start at login**, or follow
the CLI Quick Start below.

## macOS App

The app has two screens:

- **Rules** — a plain YAML editor with validation, Save (⌘S), Reload, and a copyable
  example rule. Validation (⌘K) uses the same checks as the CLI. Saving preserves
  comments and formatting, and the running daemon reloads the configuration.
- **Settings** — start the daemon at login, choose System/Light/Dark appearance,
  adjust editor text size, reveal the configuration in Finder, and open the log.

On first launch, the editor starts with an empty configuration. Save it to create
`~/.config/house_keeping/config.yaml`. If a LaunchAgent already uses a custom config,
the app opens that file instead. The configuration path is shown in Settings.
Unsaved drafts survive closing the app; **Save** applies them. If the file changes
externally, saving is blocked: copy your edits, reload, and merge them as needed.

**Start at login** starts the background daemon immediately and at future logins.
Turning it off stops and removes the LaunchAgent. The app can be closed while the
daemon continues running. macOS background-item controls are in System Settings →
General → Login Items & Extensions.

Build and open the app without installing a package:

```bash
bash scripts/build-app.sh
open ".build/House Keeping.app"
```

The app bundle includes the CLI helper and an offline configuration reference in
the Help menu. Builds are ad-hoc signed by default; set `CODESIGN_IDENTITY` to use
your signing identity. For local debug builds, use `CONFIGURATION=debug`.

### CLI-only Installation

Alternatively, build and install the binary directly:

```bash
# Clone and build
git clone <repo-url> && cd house_keeping
swift build -c release

# Copy to PATH
sudo install -d /usr/local/bin
sudo install -m 755 .build/release/house-keeping /usr/local/bin/house_keeping
```

## Quick Start

1. Create a config file at `~/.config/house_keeping/config.yaml`:

```yaml
version: 1

global:
  log_level: info
  log_file: ~/Library/Logs/house_keeping/house_keeping.log
  state_file: ~/.local/share/house_keeping/state.db

rules:
  - name: flag-stale-downloads
    description: "Tag files older than 7 days with Orange"
    trigger:
      type: schedule
      interval: 1h
    watch_paths:
      - ~/Downloads
    conditions:
      all:
        - age_days: { gt: 7 }
        - not: { has_tag: Orange }
    actions:
      - set_tag: Orange
      - log: "Flagged {name} as stale ({age_days}d old)"
```

2. Validate your config:

```bash
house_keeping check --verbose
```

3. Preview what would happen:

```bash
house_keeping dry-run
```

4. Run the daemon:

```bash
house_keeping daemon --foreground
```

## CLI Reference

| Command | Description |
|---------|-------------|
| `house_keeping daemon [--foreground] [--config PATH]` | Run the daemon |
| `house_keeping check [--config PATH] [--verbose]` | Validate config |
| `house_keeping list [--enabled\|--disabled] [--format table\|json]` | List rules |
| `house_keeping run RULE [--dry-run] [--force] [--file PATH]` | Execute a single rule |
| `house_keeping dry-run [RULE]` | Preview all changes without applying them |
| `house_keeping status [--json]` | Show daemon status and stats |
| `house_keeping inspect PATH [--json\|--tags\|--source]` | Inspect file metadata |
| `house_keeping install [--config PATH]` | Install as launchd agent (start on login) |
| `house_keeping uninstall [--purge]` | Remove launchd agent |

All commands accept `--config PATH` to use a non-default config file.

## Configuration

### Action notifications

House Keeping automatically sends a macOS notification after each action in the
daemon or a manual `run`, showing the rule, filename, action, and result. Failed
actions also produce a notification. Dry runs and disabled actions (`trash: false`,
`delete: false`, and `remove_quarantine: false`) do not send notifications.
An explicit `notify` action sends its custom message once, without an additional
automatic notification.

Notifications use macOS's `osascript` notification support, including for CLI-only
installations. Allow notifications for **Script Editor** in System Settings →
Notifications if prompted; Focus and notification settings can suppress banners.
Automatic notification delivery errors are logged and do not interrupt file actions.

See the [configuration reference](docs/llm-config-reference.md) for a standalone
guide you can also provide to an LLM when generating rules.

### Triggers

**Schedule** — runs periodically:

```yaml
trigger:
  type: schedule
  interval: 1h        # Supports: 30s, 15m, 1h, 1d
```

**File change** — fires on filesystem events (via FSEvents):

```yaml
trigger:
  type: file_change
  events: [create]     # Options: create, modify, delete, rename
```

### Conditions

Conditions are combined using `all` (AND), `any` (OR), `none` (NOR), and `not`:

```yaml
conditions:
  all:
    - age_days: { gt: 7 }
    - any:
        - extension: [pdf, docx]
        - name_matches: "^report_.*"
    - not: { has_tag: Blue }
```

#### Available conditions

**File age** (based on creation date):

```yaml
- age_days: { gt: 7 }
- age_hours: { lt: 12 }
- age_modified_days: { gt: 7 }       # Based on modification date
```

**File size:**

```yaml
- size: { gt: 500MB }
- size: { between: [10MB, 500MB] }   # Supports B, KB, MB, GB, TB
```

**Name and extension:**

```yaml
- extension: [pdf, docx]             # Single value or list
- extension: zip
- name_matches: "^CV_.*"             # Regex
- path_matches: ".*\\.tmp$"
```

**Finder tags:**

```yaml
- has_tag: Orange
- has_tag: Blue
- tag_count: { gt: 0 }
```

**Download source** (reads the `kMDItemWhereFroms` xattr):

```yaml
- downloaded_from: { pattern: "linkedin\\.com" }   # Regex match on URL
- downloaded_from: { domain: "github.com" }         # Simple domain match
```

**Quarantine:**

```yaml
- is_quarantined: true
- quarantine_agent: "Chrome"
```

**Content search** (text files only):

```yaml
- content_matches: { pattern: "CONFIDENTIAL", max_size: 5MB }
```

**File type:**

```yaml
- is_directory: false
- uti: "com.adobe.pdf"
```

**Comparisons** support: `gt`, `lt`, `gte`, `lte`, `eq`.

### Actions

Actions run in order. If any action fails, execution stops.

**Finder tags:**

```yaml
- set_tag: Orange
- remove_tag: Red
- clear_tags: true
- set_color_label: 6          # 0-7
```

**File operations:**

```yaml
- move: ~/Documents/Archive/
- copy: ~/Backup/
- trash: true
- delete: true                 # Permanent — use with caution
- rename: { pattern: "^old_(.*)", replacement: "new_$1" }
```

**Notifications and logging:**

```yaml
- notify: { title: "house_keeping", body: "Trashed {name}" }
- log: "Processed {name} (age: {age_days}d)"
```

**External scripts:**

```yaml
- run_script: "/path/to/script.sh {path}"
```

Scripts receive environment variables `HK_FILE_PATH`, `HK_FILE_NAME`, and `HK_RULE_NAME`.

**Quarantine:**

```yaml
- remove_quarantine: true
```

### Template Variables

Use these in `log`, `notify`, `move`, `run_script`, and other string-valued actions:

| Variable | Description |
|----------|-------------|
| `{path}` | Full file path |
| `{name}` | File name with extension |
| `{ext}` | File extension |
| `{size_human}` | Human-readable size (e.g. "4.2 MB") |
| `{age_days}` | Age in days since creation |
| `{tags}` | Comma-separated Finder tags |
| `{download_url}` | Original download URL |
| `{rule_name}` | Name of the rule being executed |
| `{date}` | Current date (YYYY-MM-DD) |

## Example Rules

### Trash old large downloads

```yaml
- name: trash-old-large-downloads
  trigger: { type: schedule, interval: 1d }
  watch_paths: [~/Downloads]
  conditions:
    all:
      - age_days: { gt: 30 }
      - size: { gt: 100MB }
      - not: { has_tag: Blue }
  actions:
    - trash: true
    - notify: { title: "house_keeping", body: "Trashed {name} ({size_human})" }
```

### Organize downloads by source

```yaml
- name: organize-linkedin
  trigger: { type: file_change, events: [create] }
  watch_paths: [~/Downloads]
  conditions:
    all:
      - extension: [pdf, docx]
      - downloaded_from: { pattern: "linkedin\\.com" }
  actions:
    - move: ~/Documents/CVs/
    - set_tag: Green

- name: organize-github-releases
  trigger: { type: file_change, events: [create] }
  watch_paths: [~/Downloads]
  conditions:
    all:
      - downloaded_from: { domain: "github.com" }
      - extension: [zip, tar.gz, dmg]
  actions:
    - move: ~/Downloads/GitHub/
    - log: "Sorted {name} from GitHub"
```

### Flag screenshots for review

```yaml
- name: flag-old-screenshots
  trigger: { type: schedule, interval: 6h }
  watch_paths: [~/Desktop]
  conditions:
    all:
      - name_matches: "^Screenshot.*"
      - age_days: { gt: 3 }
      - not: { has_tag: Orange }
  actions:
    - set_tag: Orange
```

## Running as a Launch Agent

To start the daemon automatically on login:

```bash
house_keeping install
```

This creates a launchd plist at `~/Library/LaunchAgents/com.house-keeping.agent.plist`.

To remove it:

```bash
house_keeping uninstall          # Remove agent only
house_keeping uninstall --purge  # Also remove config, state DB, and logs
```

## File Locations

| Purpose | Path |
|---------|------|
| Config | `~/.config/house_keeping/config.yaml` |
| State DB | `~/.local/share/house_keeping/state.db` |
| Logs | `~/Library/Logs/house_keeping/house_keeping.log` |
| LaunchAgent | `~/Library/LaunchAgents/com.house-keeping.agent.plist` |
| PID file | `$TMPDIR/house_keeping.pid` |

## Inspecting Files

Use `inspect` to see what metadata house_keeping can read for a file — useful when writing conditions:

```
$ house_keeping inspect ~/Downloads/report.pdf

File: report.pdf
Path: /Users/you/Downloads/report.pdf
Size: 319 KB (319187 bytes)
Type: File
UTI:  com.adobe.pdf
Created:  2026-01-28 12:53:21 +0000
Modified: 2026-01-28 12:53:21 +0000
Age: 20.1 days

Tags: none
Quarantined: yes
Quarantine Agent: Chrome
Download URL: https://example.com/report.pdf
```

## Tips

- Use `dry-run` liberally before enabling destructive rules (`trash`, `delete`).
- Tag files Blue to protect them — then add `not: { has_tag: Blue }` to your cleanup rules.
- The daemon hot-reloads the config file when it changes — no restart needed.
- Set `log_level: debug` in the config to troubleshoot rule matching.
- Use `--force` with `run` to execute a disabled rule without editing the config.

## Development Checks

```bash
swift test
swift build -c release
python3 scripts/test-daemon.py .build/release/house-keeping
```

The subprocess regression test requires Python 3 and a stopped daemon (use
`house_keeping uninstall` first if the LaunchAgent is installed). It uses temporary
config, state, logs, and watched files to verify daemon startup, scheduled and
file-change rules, live reload after an atomic config save, and clean shutdown with
both SIGINT and SIGTERM, including PID file cleanup.

## License

MIT
