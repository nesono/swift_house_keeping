# house_keeping Configuration Reference

You are helping a user create a YAML configuration file for **house_keeping**, a macOS daemon that watches folders and automatically organizes files based on rules.

The config file lives at `~/.config/house_keeping/config.yaml`.

## Config Structure

Every config file has exactly this top-level shape:

```yaml
version: 1

global:
  log_level: info                                          # debug | info | warning | error
  log_file: ~/Library/Logs/house_keeping/house_keeping.log # path to log file
  state_file: ~/.local/share/house_keeping/state.db        # path to SQLite state DB

rules:
  - name: rule-name
    # ... rule definition (see below)
```

- `version` must always be `1`.
- The `global` section can be omitted to use defaults. If provided, include all three fields shown above.

## Rule Definition

Each rule in the `rules` list has these fields:

```yaml
- name: rule-name              # Required. Unique kebab-case identifier.
  description: "Human text"    # Optional.
  enabled: true                # Optional, default true.
  priority: 50                 # Optional, default 50. Lower = runs first.
  recursive: false             # Optional, default false. Scan subdirectories.
  trigger: { ... }             # Required. When the rule fires.
  watch_paths:                 # Required. At least one directory path.
    - ~/Downloads
  conditions:                  # Required. Which files match.
    all: [ ... ]
  actions:                     # Required. At least one action.
    - log: "matched {name}"
```

## Triggers

A rule has exactly one trigger. There are two types:

### Schedule trigger

Runs periodically on a timer.

```yaml
trigger:
  type: schedule
  interval: 1h       # Required. Supports: 30s, 15m, 2h, 1d
```

### File-change trigger

Fires on filesystem events (via macOS FSEvents).

```yaml
trigger:
  type: file_change
  events: [create, modify]  # Required. Options: create, modify, delete, rename
```

## Conditions

Conditions decide which files in the watch paths a rule applies to. The top-level conditions key must contain exactly one logical combinator (`all`, `any`, `none`, or `not`).

### Logical combinators

| Key | Meaning | Expects |
|-----|---------|---------|
| `all` | AND — every child must match | list of conditions |
| `any` | OR — at least one child must match | list of conditions |
| `none` | NOR — no child may match | list of conditions |
| `not` | negates a single condition | one condition |

Combinators nest freely:

```yaml
conditions:
  all:
    - age_days: { gt: 7 }
    - any:
        - extension: [pdf, docx]
        - name_matches: "^report_.*"
    - not: { has_tag: Blue }
```

### Leaf conditions

#### File age (based on creation date)

```yaml
- age_days: { gt: 7 }
- age_hours: { lt: 12 }
```

#### File age (based on modification date)

```yaml
- age_modified_days: { gt: 30 }
```

#### File size

```yaml
- size: { gt: 500MB }
- size: { lt: 10KB }
- size: { between: [10MB, 500MB] }
```

Size units: `B`, `KB`, `MB`, `GB`, `TB` (decimal, not binary — 1 KB = 1000 bytes).

#### File name and extension

```yaml
- extension: pdf                    # single value
- extension: [pdf, docx, xlsx]      # list of values
- name_matches: "^Screenshot.*"     # regex against file name
- path_matches: ".*\\.tmp$"         # regex against full path
```

#### Finder tags

```yaml
- has_tag: Orange
- tag_count: { gt: 0 }
```

Tag names are macOS Finder tag names (e.g., Red, Orange, Yellow, Green, Blue, Purple, Gray, or any custom tag name).

#### Download source (reads the kMDItemWhereFroms xattr)

```yaml
- downloaded_from: { domain: "github.com" }            # simple domain match
- downloaded_from: { pattern: "linkedin\\.com" }       # regex match on URL
```

#### Quarantine

```yaml
- is_quarantined: true
- quarantine_agent: "Chrome"
```

#### Content search (text files and PDFs)

Searches file content via regex. Works with plain text (UTF-8), PDFs (via text extraction), and other document types indexed by Spotlight (docx, rtf, Pages, etc.).

```yaml
- content_matches: { pattern: "CONFIDENTIAL" }
- content_matches: { pattern: "SSN:\\s*\\d{3}-\\d{2}-\\d{4}", max_size: 10MB }
```

`max_size` defaults to 5MB if omitted. Files larger than `max_size` are skipped.

#### File type

```yaml
- is_directory: false
- uti: "com.adobe.pdf"
```

### Comparison operators

Numeric conditions (`age_days`, `age_hours`, `age_modified_days`, `tag_count`) and size conditions all use the same comparison operators:

| Operator | Meaning |
|----------|---------|
| `gt` | greater than |
| `lt` | less than |
| `gte` | greater than or equal |
| `lte` | less than or equal |
| `eq` | equal to |

Multiple operators combine as AND:

```yaml
- age_days: { gt: 7, lt: 30 }  # between 7 and 30 days old
```

Size conditions additionally support `between: [low, high]`.

## Actions

Actions run in order. If any action fails, remaining actions for that file are skipped.

### Finder tags

```yaml
- set_tag: Orange
- remove_tag: Red
- clear_tags: true
- set_color_label: 6          # 0–7
```

### File operations

```yaml
- move: ~/Documents/Archive/
- copy: ~/Backup/
- trash: true
- delete: true                 # permanent deletion — use with caution
- rename: { pattern: "^old_(.*)", replacement: "new_$1" }
```

`move` and `copy` accept directory paths. Tilde (`~`) is expanded.

### Notifications and logging

```yaml
- notify: { title: "house_keeping", body: "Trashed {name}" }
- log: "Processed {name} (age: {age_days}d)"
```

### External scripts

```yaml
- run_script: "/path/to/script.sh {path}"
```

Scripts also receive environment variables: `HK_FILE_PATH`, `HK_FILE_NAME`, `HK_RULE_NAME`.

### Quarantine

```yaml
- remove_quarantine: true
```

## Template Variables

These placeholders expand in string values for `log`, `notify`, `move`, `copy`, `run_script`, and `rename`:

| Variable | Description |
|----------|-------------|
| `{path}` | Full file path |
| `{name}` | File name with extension |
| `{ext}` | File extension |
| `{size_human}` | Human-readable size (e.g., "4.2 MB") |
| `{age_days}` | Age in days since creation |
| `{tags}` | Comma-separated Finder tags |
| `{download_url}` | Original download URL |
| `{rule_name}` | Name of the executing rule |
| `{date}` | Current date (YYYY-MM-DD) |

## Validation Rules

The config is validated on load. Common errors:

- `version` must be `1`
- Rule names must be non-empty and unique
- `watch_paths` must be non-empty and point to existing directories
- `actions` must be non-empty
- `schedule` triggers require `interval`
- `file_change` triggers require `events`

## Complete Example

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
        - is_directory: false
    actions:
      - set_tag: Orange
      - log: "Flagged {name} as stale ({age_days}d old)"

  - name: trash-old-large-downloads
    description: "Trash large files older than 30 days"
    trigger:
      type: schedule
      interval: 1d
    watch_paths:
      - ~/Downloads
    conditions:
      all:
        - age_days: { gt: 30 }
        - size: { gt: 100MB }
        - not: { has_tag: Blue }
    actions:
      - trash: true
      - notify: { title: "house_keeping", body: "Trashed {name} ({size_human})" }

  - name: organize-cvs-from-linkedin
    description: "Move LinkedIn PDFs to CVs folder"
    trigger:
      type: file_change
      events: [create]
    watch_paths:
      - ~/Downloads
    conditions:
      all:
        - extension: [pdf, docx]
        - downloaded_from: { pattern: "linkedin\\.com" }
    actions:
      - move: ~/Documents/CVs/
      - set_tag: Green
      - log: "Sorted {name} from LinkedIn"

  - name: flag-confidential-documents
    description: "Tag documents containing sensitive content"
    trigger:
      type: schedule
      interval: 6h
    watch_paths:
      - ~/Documents
    recursive: true
    conditions:
      all:
        - any:
            - extension: [pdf, txt, md]
            - uti: "com.adobe.pdf"
        - content_matches: { pattern: "CONFIDENTIAL|SECRET", max_size: 10MB }
        - not: { has_tag: Red }
    actions:
      - set_tag: Red
      - notify: { title: "house_keeping", body: "Flagged {name} as confidential" }
```

## Tips for Generating Configs

- Always start with `version: 1`.
- Use `all` as the default top-level combinator for conditions — users generally want AND logic.
- Prefer `schedule` triggers for cleanup/organization tasks, `file_change` for sorting new downloads.
- Add `not: { has_tag: Blue }` to destructive rules so users can protect files by tagging them Blue.
- Add `not: { has_tag: <action_tag> }` to tagging rules to avoid reprocessing.
- Use `dry-run` friendly actions (`log`, `set_tag`) when the user is exploring; suggest they run `house_keeping dry-run` to preview.
- Use `is_directory: false` to avoid accidentally matching directories.
- Quote regex patterns that contain YAML-special characters (`:`, `{`, `}`, `[`, `]`, `#`).
- Escape backslashes in regex: a literal `\.` in regex must be `\\.` in YAML.
- Ask the user what folders they want to watch and what outcome they want — don't assume paths.
