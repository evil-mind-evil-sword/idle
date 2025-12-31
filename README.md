# idle

Long-running loops with quality gates for Claude Code.

idle keeps Claude iterating on your task until it's done—with automatic reviews to catch mistakes before completion.

## Why idle?

Claude Code exits after each response. For complex tasks, you manually re-prompt, lose context to compaction, and hope the work is correct. idle solves three problems:

| Problem | idle solution |
|---------|---------------|
| **Context loss** | PreCompact hook saves recovery anchors before compaction |
| **No quality gates** | alice reviews work at checkpoints and before completion |
| **Single-model bias** | alice consults Codex and Gemini for second opinions |

## Quick Start

Install:

```sh
curl -fsSL https://github.com/evil-mind-evil-sword/idle/releases/latest/download/install.sh | sh
```

Run your first loop:

```sh
/loop Add input validation to all API endpoints
```

idle iterates until the task is complete, with alice reviewing at checkpoints (iterations 3, 6, 9) and before exit.

## How It Works

### The Loop

```
              /loop <task>
                   │
                   ▼
            ┌─────────────┐
        ┌──▶│    work     │
        │   └──────┬──────┘
        │          │
        │          ▼
        │   ┌─────────────┐
        │   │  Stop hook  │──▶ alice reviews at iter 3, 6, 9
        │   └──────┬──────┘    and on COMPLETE/STUCK
        │          │
        │     ┌────┴────┐
        │  block(2)  allow(0)
        │     │         │
        └─────┘         ▼
                      exit
```

The Stop hook reads loop state from `.zawinski/` and decides whether to block exit (code `2`) or allow it (code `0`). Claude keeps iterating until alice approves completion.

### Completion Signals

Signal your status with these exact markers (column 0, no extra characters):

| Signal | Meaning |
|--------|---------|
| `<loop-done>COMPLETE</loop-done>` | Task finished—request alice review |
| `<loop-done>STUCK</loop-done>` | Cannot progress—request alice review |
| `<loop-done>MAX_ITERATIONS</loop-done>` | Hit limit (10 iterations) |

### alice

alice is a read-only adversarial reviewer that runs on Opus. On completion review, alice:

1. Verifies the original task is fully satisfied
2. Uses domain-specific checklists (compilers, OS, math, general software)
3. Consults Codex and Gemini for second opinions on critical findings
4. Creates tissue issues for problems (tagged `alice-review`)
5. Approves only when zero `alice-review` issues remain

alice breaks single-model self-bias by getting external perspectives before letting work through.

## Commands

### `/loop <task>`

Iterate on a task until complete.

```sh
/loop Refactor the authentication module
```

- **Max iterations**: 10
- **Checkpoint reviews**: Every 3 iterations
- **Completion review**: On COMPLETE or STUCK

### `/cancel`

Stop the current loop gracefully.

```sh
/cancel
```

Posts an ABORT event; the Stop hook allows exit on next iteration.

### `/init`

Initialize a project with planning workflow.

```sh
/init
```

Sets up infrastructure, explores the codebase, plans with you, gets alice review, then creates tissue issues for the work.

## Skills

Skills inject domain-specific capabilities into agents.

| Skill | Purpose | When to use |
|-------|---------|-------------|
| **reviewing** | Multi-model second opinions via Codex/Gemini | Validating critical findings, breaking ties |
| **researching** | Cited research with quality gates | Complex research needing source verification |
| **issue-tracking** | Work tracking via tissue | Creating/managing issues, checking ready work |
| **technical-writing** | Multi-layer document review | READMEs, design docs, technical reports |
| **bib-managing** | Bibliography curation with bibval | BibTeX validation against academic databases |

Invoke skills via the Skill tool or by asking alice to use them.

## Configuration

### Escape Hatches

| Method | Effect |
|--------|--------|
| `/cancel` | Graceful loop cancellation |
| `touch .idle-disabled` | Bypass all hooks (remove after) |
| `rm -rf .zawinski/` | Reset all state |

### Observability

```sh
idle status              # Human-readable: mode + iteration
idle status --json       # Raw JSON from loop:current

jwz read loop:current --limit 1   # Current loop state
jwz read loop:anchor --limit 1    # Recovery anchor
```

## CLI Reference

`bin/idle` implements the hooks and provides helper commands:

```
idle session-start       # SessionStart hook (initializes infrastructure)
idle stop                # Stop hook
idle pre-compact         # PreCompact hook

idle init-loop           # Bootstrap loop state (run automatically at session start)
idle status [--json]     # Show loop status
idle doctor              # Diagnose issues
idle version             # Show version

idle emit <topic> <role> <action> [options]
idle issues [ready|show <id>|close <id>] [--json]
```

**Exit codes**: `0` = allow/success, `1` = error, `2` = block (re-enter loop)

## Installation Options

### Recommended: Release Installer

```sh
curl -fsSL https://github.com/evil-mind-evil-sword/idle/releases/latest/download/install.sh | sh
```

Installs the plugin and drops the correct `bin/idle` binary for your OS/arch (Linux and macOS, x86_64 and arm64).

### Manual: Claude Marketplace

```sh
claude plugin marketplace add evil-mind-evil-sword/marketplace
claude plugin marketplace refresh
claude plugin install idle@emes
```

## Dependencies

| Dependency | Purpose | Required |
|------------|---------|----------|
| jwz | Agent messaging | Yes |
| tissue | Issue tracking | No |
| codex | OpenAI second opinions | No (falls back to `claude -p`) |
| gemini | Google third opinions | No |
| bibval | Citation validation | No (for bib-managing skill) |

## Architecture

See [docs/architecture.md](docs/architecture.md) for design philosophy, state schemas, and implementation details.

## License

AGPL-3.0
