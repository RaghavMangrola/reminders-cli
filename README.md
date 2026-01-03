# reminders-cli

A fast, LLM-friendly CLI for macOS Reminders using EventKit.

## Why?

AppleScript-based solutions are **slow** (10+ seconds for large lists, often timing out). This Swift CLI uses EventKit directly and completes in **~0.1 seconds**.

Built for use with AI agents (Claude Code, etc.) but works great as a standalone tool.

## Features

- **Fast** - EventKit native, ~0.1s execution
- **JSON output** - `--json` flag for structured parsing
- **Partial matching** - `done "groc"` matches "Buy groceries"
- **Priority support** - 0-9 levels (1-4 high, 5 medium, 6-9 low)
- **Predictable exit codes** - 0=success, 1=error, 2=not found

## Installation

### Requirements

- macOS 12+
- Swift 5.9+ (comes with Xcode Command Line Tools)

### Build from source

```bash
git clone https://github.com/yourusername/reminders-cli.git
cd reminders-cli
swift build -c release
```

### Install globally

```bash
# Option 1: Add to PATH in ~/.zshrc
echo 'export PATH="/path/to/reminders-cli:$PATH"' >> ~/.zshrc

# Option 2: Copy binary to /usr/local/bin
sudo cp .build/release/reminders /usr/local/bin/
```

### Grant Reminders access

On first run, macOS will prompt for Reminders access. Grant it in **System Settings > Privacy & Security > Reminders**.

## Usage

```bash
# List all reminder lists
reminders lists

# List pending reminders
reminders ls
reminders ls -l "Groceries"        # specific list
reminders ls -a                     # include completed
reminders ls -s "milk"              # search

# Add a reminder
reminders add "Buy milk"
reminders add "Call mom" -n "Discuss birthday plans" -l "Personal"
reminders add "Urgent task" -p 1    # high priority

# Complete a reminder (partial match)
reminders done "milk"

# Delete a reminder
reminders delete "milk"

# Show reminder details
reminders show "Call mom"

# JSON output (for scripts/LLMs)
reminders --json ls
reminders --json lists
```

## Options

| Flag | Description |
|------|-------------|
| `--json` | Output in JSON format |
| `-l, --list <name>` | Target list name |
| `-n, --notes <text>` | Add notes to reminder |
| `-d, --due <date>` | Due date (e.g., "1/15/24 5:00 PM") |
| `-p, --priority <0-9>` | Priority level |
| `-a, --all` | Include completed reminders |
| `-s, --search <term>` | Filter by search term |

## JSON Output

All commands support `--json` for structured output:

```bash
$ reminders --json lists
```

```json
{
  "success": true,
  "data": [
    {
      "id": "ABC123",
      "name": "Groceries",
      "color": "#FF5733",
      "pending": 5,
      "total": 23
    }
  ]
}
```

## Exit Codes

| Code | Meaning |
|------|---------|
| 0 | Success |
| 1 | Error (invalid input, permission denied, etc.) |
| 2 | Not found (no matching reminder) |

## Use with Claude Code

Add a slash command in `~/.claude/commands/reminder.md`:

```markdown
Create a reminder using the `reminders` CLI.

Use: reminders add "<title>" -n "<notes>" -l "Claude"

Include:
- What we were working on
- Current status
- Directory: $PWD
- Relevant file paths
```

Then use `/reminder` in any Claude Code session to save context.

## License

MIT
