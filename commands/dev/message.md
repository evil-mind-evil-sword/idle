---
description: Post or read zawinski messages between agents
---

# Message Command

Quick messaging for agent coordination.

## Usage

```
/message <topic> <message>      # Post to topic
/message read <topic>           # Read topic
/message thread <id>            # Show message thread
/message search <query>         # Full-text search
```

## Examples

```
/message issue:auth-123 "Found the bug - missing null check"
/message project:trivial "Starting v0.5.0 release"
/message read agent:oracle
/message search "security"
```

## Topic Naming

| Pattern | Purpose |
|---------|---------|
| `project:<name>` | Project-wide announcements |
| `issue:<id>` | Per-issue discussion |
| `agent:<name>` | Direct agent communication |

## Workflow

1. Ensure jwz is initialized:
   ```bash
   [ ! -d .jwz ] && jwz init
   ```

2. Parse command arguments:
   - If first arg is `read`: `jwz read <topic>`
   - If first arg is `thread`: `jwz thread <id>`
   - If first arg is `search`: `jwz search <query>`
   - Otherwise: `jwz post <topic> -m "<message>"`

3. Display output

## Message Format

When posting, use the format:
```
[agent] ACTION: description
```

Examples:
- `[planner] STARTED: Breaking down auth feature`
- `[oracle] FINDING: Race condition in handler.go:45`
- `[reviewer] BLOCKING: Security issue in token validation`
