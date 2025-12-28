---
description: Iterate on a task until complete
---

# Loop Command

Generic iteration loop for any task (no issue tracker).

## Usage

```
/loop <task description>
```

## Limits

- **Max iterations**: 10
- **Stuck threshold**: 3 consecutive failures with no progress

## How It Works

This command uses a **Stop hook** to intercept Claude's exit and force re-entry until the task is complete. Loop state is stored via jwz messaging (with state file fallback).

The hook checks for completion signals (`<loop-done>`) in the output to decide whether to continue or allow exit.

## Setup

Initialize loop state via jwz:
```bash
# Generate unique run ID
RUN_ID="loop-$(date +%s)-$$"

# Ensure jwz is initialized
[ ! -d .jwz ] && jwz init

# Create temp directory for prompt file
STATE_DIR="/tmp/trivial-$RUN_ID"
mkdir -p "$STATE_DIR"

# Store prompt in file (avoids JSON escaping issues)
cat > "$STATE_DIR/prompt.txt" << 'PROMPT'
$ARGUMENTS
PROMPT

# Post initial state to jwz
NOW=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
jwz post "loop:current" -m "{\"schema\":1,\"event\":\"STATE\",\"run_id\":\"$RUN_ID\",\"updated_at\":\"$NOW\",\"stack\":[{\"id\":\"$RUN_ID\",\"mode\":\"loop\",\"iter\":1,\"max\":10,\"prompt_file\":\"$STATE_DIR/prompt.txt\"}]}"

# Announce start
jwz post "project:$(basename $PWD)" -m "[loop] STARTED: $ARGUMENTS"
```

## Workflow

1. Work on the task incrementally
2. Run `/test` after significant changes
3. On success: output `<loop-done>COMPLETE</loop-done>`
4. On failure: analyze, fix, retry (the stop hook will re-inject the prompt)

## Iteration Tracking

The stop hook increments the iteration counter automatically. Check current iteration:
```bash
jwz read "loop:current" | tail -1 | jq -r '.stack[-1].iter'
```

Before each retry:
- `git status` - modified files
- `git log --oneline -5` - what you've tried

## Completion

**Success**:
```
<loop-done>COMPLETE</loop-done>
```

**Max iterations reached**:
```
<loop-done>MAX_ITERATIONS</loop-done>
```
Report what was accomplished and what remains.

**Stuck** (no progress after 3 attempts):
```
<loop-done>STUCK</loop-done>
```
Describe the blocker and ask for user guidance.

## Escape Hatches

If you get stuck in an infinite loop:
1. `/cancel-loop` - Graceful cancellation
2. `TRIVIAL_LOOP_DISABLE=1 claude` - Environment variable bypass
3. Delete `.jwz/` directory - Manual reset
