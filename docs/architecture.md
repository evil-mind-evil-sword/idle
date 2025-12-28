# Architecture

trivial is a Claude Code plugin that provides multi-model development agents. This document explains how it works for contributors and advanced users.

## Overview

trivial delegates specialized tasks to different AI models:

```
User → Claude Code → trivial agents/commands
                         ↓
         ┌───────────────┼───────────────┐
         ↓               ↓               ↓
      Haiku          Opus           External
    (fast tasks)   (complex)         Models
                                       ↓
                              ┌────────┴────────┐
                              ↓                 ↓
                           Codex            Gemini
                          (OpenAI)          (Google)
```

- **Haiku agents** (`explorer`, `librarian`): Fast, cheap operations like file search
- **Opus agents** (`oracle`, `reviewer`, `planner`, `documenter`): Complex reasoning tasks
- **External model integration**: Codex for diverse perspectives, Gemini for writing

## Plugin Configuration

### Directory Structure

```
trivial/
├── .claude-plugin/
│   ├── plugin.json      # Plugin metadata
│   └── marketplace.json # Marketplace listing
├── agents/              # Agent definitions
│   ├── explorer.md
│   ├── librarian.md
│   ├── oracle.md
│   ├── documenter.md
│   ├── reviewer.md
│   └── planner.md
├── commands/            # Command definitions
│   ├── dev/
│   │   ├── commit.md
│   │   ├── document.md
│   │   ├── fmt.md
│   │   ├── plan.md
│   │   ├── review.md
│   │   ├── test.md
│   │   └── work.md
│   └── loop/
│       ├── cancel-loop.md
│       ├── grind.md
│       ├── issue.md
│       └── loop.md
└── docs/
    └── architecture.md
```

### plugin.json

Minimal metadata for the plugin:

```json
{
  "name": "trivial",
  "version": "0.4.0",
  "description": "Multi-model development agents...",
  "author": { "name": "femtomc" }
}
```

## Agent Structure

Agents are markdown files with YAML frontmatter:

```markdown
---
name: agent-name
description: When to use this agent
model: haiku | opus
tools: Comma-separated list of allowed tools
---

# Agent persona and instructions

## Constraints
What the agent MUST NOT do

## Workflow
How the agent operates

## Output Format
Expected response structure
```

### Key Frontmatter Fields

| Field | Description |
|-------|-------------|
| `name` | Agent identifier |
| `description` | Shown in Claude Code's agent picker |
| `model` | `haiku` for fast/cheap, `opus` for complex |
| `tools` | Allowed tools (e.g., `Read, Grep, Glob, Bash`) |

### Agent Patterns

**Read-only agents** (oracle, explorer):
- Cannot write/edit files
- Bash restricted to specific commands only

**Artifact writers** (librarian, documenter):
- Can create/edit files in `.claude/plugins/trivial/` (librarian) or docs (documenter)
- Cannot modify source code

**Reviewer** (reviewer):
- Writes review artifacts to `.claude/plugins/trivial/reviewer/`
- Read-only access to source code

**Issue tracker access** (planner):
- Full access to `tissue` commands for issue management
- Read-only access to code and artifacts

## Command Structure

Commands are markdown files that define slash commands:

```markdown
---
description: What the command does
---

# Command Name

## Usage
How to invoke the command

## Workflow
Step-by-step execution

## Output
Expected completion signals
```

Commands are user-invocable via `/trivial:dev:command` or `/trivial:loop:command`.

## Loop State Management

Loop commands (`/loop`, `/grind`, `/issue`) maintain state across iterations:

### Session State

```bash
# Unique session ID prevents conflicts
SID="${TRIVIAL_SESSION_ID:-$(date +%s)-$$}"

# Sanitize: only allow alphanumeric, dash, underscore (prevent path traversal)
SID=$(printf '%s' "$SID" | tr -cd 'a-zA-Z0-9_-')
[[ -z "$SID" ]] && SID="$(date +%s)-$$"

export TRIVIAL_SESSION_ID="$SID"
STATE_DIR="/tmp/trivial-$SID"
mkdir -p "$STATE_DIR"
```

### State Files

| File | Purpose |
|------|---------|
| `$STATE_DIR/mode` | Current mode (`grind`, `issue`, `loop`) |
| `$STATE_DIR/count` | Issues completed (grind) |
| `$STATE_DIR/iter` | Iteration count |
| `$STATE_DIR/context` | Filter/arguments |

### Completion Signals

Commands emit structured signals for loop control:

- `<loop-done>COMPLETE</loop-done>` - Task finished successfully
- `<loop-done>MAX_ITERATIONS</loop-done>` - Hit iteration limit
- `<loop-done>STUCK</loop-done>` - No progress, needs user input
- `<issue-complete>DONE</issue-complete>` - Single issue finished
- `<grind-done>NO_MORE_ISSUES</grind-done>` - Backlog cleared

## External Model Integration

### Codex (OpenAI)

Used by: `oracle`, `reviewer`, `planner`

Pattern: Dialogue-based consultation

```bash
codex exec "You are helping with [TASK].

Context: [RELEVANT CODE/PROBLEM]

Question: [SPECIFIC ASK]"
```

Agents iterate with Codex until reaching consensus or identifying clear disagreement.

### Gemini (Google)

Used by: `documenter`

Pattern: Director-writer relationship

```bash
gemini "You are writing documentation.

TASK: [WHAT TO WRITE]

CONTEXT: [CODE SNIPPETS, ARCHITECTURE]

STRUCTURE: [EXPECTED SECTIONS]"
```

The documenter reviews Gemini's output, sends corrections, and iterates until satisfied.

## Agent Messaging

Agents communicate asynchronously via [zawinski](https://github.com/femtomc/zawinski), a topic-based messaging CLI.

### Topic Naming Convention

| Pattern | Example | Purpose |
|---------|---------|---------|
| `project:<name>` | `project:trivial` | Project-wide announcements |
| `issue:<id>` | `issue:auth-123` | Per-issue discussion |
| `agent:<name>` | `agent:oracle` | Direct agent communication |

### Commands

```bash
# Initialize (once per project)
zawinski init

# Create topic and post
zawinski topic new "issue:auth-123"
zawinski post "issue:auth-123" -m "[planner] STARTED: Breaking down auth feature"

# Read and reply
zawinski read "issue:auth-123"
zawinski reply <msg-id> -m "[oracle] FINDING: Race condition in handler.go:45"

# Search across all messages
zawinski search "security"
```

### Message Format

```
[AGENT] ACTION: description

Examples:
[planner] STARTED: Breaking down auth feature
[oracle] FINDING: Race condition in handler.go:45
[reviewer] BLOCKING: Security issue in token validation
[librarian] RESEARCH: API deprecated in v3
```

### Messaging vs Artifacts

| Use Case | Mechanism | Location |
|----------|-----------|----------|
| Quick status update | Message | `.zawinski/` |
| Research finding (quick) | Message | `.zawinski/` |
| Research finding (full) | Artifact | `.claude/plugins/trivial/{agent}/` |
| Design decision | Artifact + message | Both |

Messages are ephemeral notes; artifacts are durable references.

## Adding New Agents

1. Create `agents/your-agent.md`
2. Define frontmatter (name, description, model, tools)
3. Write clear constraints (what it MUST NOT do)
4. Define the workflow
5. Specify output format

The agent becomes available automatically as `trivial:your-agent`.

## Adding New Commands

1. Create `commands/category/your-command.md`
2. Add frontmatter with description
3. Document usage and workflow
4. Define completion signals if it's a loop command

The command becomes available as `/trivial:category:your-command`.

## Dependencies

### Required

- [tissue](https://github.com/femtomc/tissue) - Local issue tracker for `/work`, `/grind`, `/issue`
- [zawinski](https://github.com/femtomc/zawinski) - Async messaging for agent communication
- [uv](https://github.com/astral-sh/uv) - Python package runner for `scripts/search.py`
- [gh](https://cli.github.com/) - GitHub CLI for librarian agent

### Optional

- [codex](https://github.com/openai/codex) - OpenAI CLI for oracle/reviewer/planner (falls back to `claude -p`)
- [gemini-cli](https://github.com/google-gemini/gemini-cli) - Google CLI for documenter (falls back to `claude -p`)
