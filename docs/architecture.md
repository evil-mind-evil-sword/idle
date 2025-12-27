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
  "version": "0.3.0",
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

**Read-only agents** (oracle, explorer, librarian):
- Cannot write/edit files
- Bash restricted to specific commands only

**Writer agents** (documenter):
- Can create/edit documentation files
- Cannot modify source code

**Full access** (reviewer, planner):
- Can read, analyze, and potentially suggest edits
- Typically have restricted Bash usage

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
SID="$(date +%s)-$$"
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

- [tissue](https://github.com/femtomc/tissue) - Local issue tracker for `/work`, `/grind`, `/issue`
- [codex](https://github.com/openai/codex) - OpenAI CLI for oracle/reviewer/planner
- [gemini-cli](https://github.com/google-gemini/gemini-cli) - Google CLI for documenter
