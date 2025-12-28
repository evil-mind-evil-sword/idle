# Event Schema (v0)

This document defines the formal schema for events used in the idle plugin's jwz messaging system. These events drive the state management for loops, issue grinding, and recovery.

> **Note**: The codebase currently uses `schema: 1`. This document formalizes the schema as version 0.

## 1. Schema Version

All events MUST include a `schema` field set to `0`.

## 2. Run ID Format

Format: `<mode>-<timestamp>-<pid>`

- **mode**: The loop mode (`loop`, `grind`, or `issue`)
- **timestamp**: Unix epoch timestamp in seconds
- **pid**: Process ID of the initiating shell

Example: `loop-1703123456-12345`

## 3. Event Types

Four event types are defined:

| Event | Description |
|-------|-------------|
| **STATE** | Current snapshot of the execution stack. Tracks active loop state. |
| **DONE** | Signals that a loop completed its execution lifecycle. |
| **ABORT** | Signals that a loop was cancelled or stopped due to error. |
| **ANCHOR** | Recovery snapshot for context compaction and resumption. |

## 4. Event Structure

### 4.1 STATE Event

**Purpose**: Track active loop state
**Topic**: `loop:current`
**TTL**: 2 hours (state is considered stale after this period)

**Required fields**:

| Field | Type | Description |
|-------|------|-------------|
| `schema` | integer | Schema version (`0`) |
| `event` | string | `"STATE"` |
| `run_id` | string | Unique run identifier |
| `updated_at` | string | ISO 8601 timestamp |
| `stack` | array | Array of StackFrame objects |

### 4.2 DONE Event

**Purpose**: Signal loop completion
**Topic**: `loop:current`

**Required fields**:

| Field | Type | Description |
|-------|------|-------------|
| `schema` | integer | Schema version (`0`) |
| `event` | string | `"DONE"` |
| `reason` | string | One of: `COMPLETE`, `MAX_ITERATIONS`, `NO_MORE_ISSUES`, `MAX_ISSUES` |
| `stack` | array | Always `[]` (empty array) |

### 4.3 ABORT Event

**Purpose**: Signal loop cancellation
**Topic**: `loop:current`

**Required fields**:

| Field | Type | Description |
|-------|------|-------------|
| `schema` | integer | Schema version (`0`) |
| `event` | string | `"ABORT"` |
| `stack` | array | Always `[]` (empty array) |

**Optional fields**:

| Field | Type | Description |
|-------|------|-------------|
| `reason` | string | `USER_CANCELLED` (omitted for internal errors/corruption) |

### 4.4 ANCHOR Event

**Purpose**: Recovery snapshot for context compaction
**Topic**: `loop:anchor`

**Required fields**:

| Field | Type | Description |
|-------|------|-------------|
| `schema` | integer | Schema version (`0`) |
| `goal` | string | Current task description |
| `mode` | string | `loop`, `grind`, or `issue` |
| `iteration` | string | Format: `"current/max"` (e.g., `"3/10"`) |
| `progress` | string | Summary of recent git activity |
| `modified_files` | string | Comma-separated list of modified files |
| `next_step` | string | Resumption instruction |
| `timestamp` | string | ISO 8601 timestamp |

## 5. Stack Frame Structure

The `stack` array contains frame objects representing nested execution contexts. The top of the stack (last element) is the current loop.

### Common Fields (all modes)

| Field | Type | Description |
|-------|------|-------------|
| `id` | string | Unique frame ID |
| `mode` | string | `loop`, `grind`, or `issue` |
| `iter` | integer | Current iteration (1-based) |
| `max` | integer | Maximum iterations allowed |
| `prompt_file` | string | Absolute path to prompt file |

### Additional Fields: `grind` mode

| Field | Type | Description |
|-------|------|-------------|
| `filter` | string | Issue filter query (e.g., `"priority:1"`) |

### Additional Fields: `issue` mode

| Field | Type | Description |
|-------|------|-------------|
| `issue_id` | string | Issue identifier |
| `worktree_path` | string | Absolute path to git worktree |
| `branch` | string | Git branch name |
| `base_ref` | string | Base branch (e.g., `"main"`) |

## 6. Topic Naming

| Topic | Type | Purpose |
|-------|------|---------|
| `loop:current` | last-value | Active loop state |
| `loop:anchor` | append-only | Recovery snapshots |
| `loop:trace` | append-only | Trace events (planned, not yet implemented) |
| `issue:<id>` | append-only | Per-issue discussion |
| `project:<name>` | append-only | Project announcements |
| `agent:<name>` | last-value | Direct agent communication |

## 7. Schema Evolution Rules

1. **Additive changes**: New optional fields may be added without version bump
2. **Removing required fields**: Requires schema version bump
3. **Changing field semantics**: Requires schema version bump
4. **Unknown fields**: Readers MUST ignore unknown fields for forward compatibility

## 8. Examples

### Simple Loop STATE

```json
{
  "schema": 0,
  "event": "STATE",
  "run_id": "loop-1703123456-12345",
  "updated_at": "2024-12-21T10:00:00Z",
  "stack": [
    {
      "id": "loop-1703123456-12345",
      "mode": "loop",
      "iter": 3,
      "max": 10,
      "prompt_file": "/tmp/idle-loop-xxx/prompt.txt"
    }
  ]
}
```

### Nested Grind/Issue STATE

```json
{
  "schema": 0,
  "event": "STATE",
  "run_id": "grind-1703123456-12345",
  "updated_at": "2024-12-21T10:30:00Z",
  "stack": [
    {
      "id": "grind-1703123456-12345",
      "mode": "grind",
      "iter": 3,
      "max": 100,
      "prompt_file": "/tmp/idle-grind-xxx/prompt.txt",
      "filter": "priority:1"
    },
    {
      "id": "issue-auth-123-1703123456",
      "mode": "issue",
      "iter": 2,
      "max": 10,
      "prompt_file": "/tmp/idle-issue-xxx/prompt.txt",
      "issue_id": "auth-123",
      "worktree_path": "/path/to/.worktrees/idle/auth-123",
      "branch": "idle/issue/auth-123",
      "base_ref": "main"
    }
  ]
}
```

### DONE Event

```json
{
  "schema": 0,
  "event": "DONE",
  "reason": "COMPLETE",
  "stack": []
}
```

### ABORT Event (user cancelled)

```json
{
  "schema": 0,
  "event": "ABORT",
  "reason": "USER_CANCELLED",
  "stack": []
}
```

### ABORT Event (internal error)

```json
{
  "schema": 0,
  "event": "ABORT",
  "stack": []
}
```

### ANCHOR Event

```json
{
  "schema": 0,
  "goal": "Working on issue: auth-123",
  "mode": "issue",
  "iteration": "3/10",
  "progress": "Recent commits: abc1234; def5678; ghi9012",
  "modified_files": "src/auth.py, tests/test_auth.py, README.md",
  "next_step": "Continue working on the task. Check git status and loop state.",
  "timestamp": "2024-12-21T10:30:00Z"
}
```
