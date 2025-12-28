---
description: Work an issue with iteration (retries on failure)
---

# Issue Command

Like `/work`, but with iteration - keep trying until the issue is resolved.

## Usage

```
/issue <issue-id>
```

## Limits

- **Max iterations**: 10
- **Stuck threshold**: 3 consecutive failures with same error

## How It Works

This command uses a **Stop hook** to intercept Claude's exit and force re-entry until the issue is resolved. Loop state is stored via jwz messaging.

When called from `/grind`, this pushes a new frame onto the loop stack. When the issue completes, the frame is popped and grind continues.

## Setup

Initialize loop state via jwz:
```bash
# Generate unique run ID
RUN_ID="issue-$ARGUMENTS-$(date +%s)"

# Ensure jwz is initialized
[ ! -d .jwz ] && jwz init

# Create temp directory for prompt file
STATE_DIR="/tmp/trivial-$RUN_ID"
mkdir -p "$STATE_DIR"

# Store issue context as prompt
tissue show "$ARGUMENTS" > "$STATE_DIR/prompt.txt"

# Check if we're nested inside grind (existing stack)
EXISTING=$(jwz read "loop:current" 2>/dev/null | tail -1 || echo '{"stack":[]}')
EXISTING_STACK=$(echo "$EXISTING" | jq -c '.stack // []')
PARENT_RUN_ID=$(echo "$EXISTING" | jq -r '.run_id // empty')

# Use parent run_id if nested, otherwise our own
ACTIVE_RUN_ID="${PARENT_RUN_ID:-$RUN_ID}"

# Push new frame onto stack
NOW=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
NEW_FRAME="{\"id\":\"$RUN_ID\",\"mode\":\"issue\",\"iter\":1,\"max\":10,\"prompt_file\":\"$STATE_DIR/prompt.txt\",\"issue_id\":\"$ARGUMENTS\"}"
NEW_STACK=$(echo "$EXISTING_STACK" | jq --argjson frame "$NEW_FRAME" '. + [$frame]')

jwz post "loop:current" -m "{\"schema\":1,\"event\":\"STATE\",\"run_id\":\"$ACTIVE_RUN_ID\",\"updated_at\":\"$NOW\",\"stack\":$NEW_STACK}"

# Create/announce on issue topic
jwz topic new "issue:$ARGUMENTS" 2>/dev/null || true
jwz post "issue:$ARGUMENTS" -m "[issue] STARTED: Beginning work on issue"
```

## Workflow

Run `/work $ARGUMENTS` with these additions:

1. **On failure**: Increment iteration count, analyze, retry
2. **On stuck**: After 3 similar failures, pause and escalate
3. **On success**: Output `<loop-done>COMPLETE</loop-done>`
4. **On max iterations**: Stop and report

## Iteration Tracking

The stop hook increments the iteration counter automatically. Check current iteration:
```bash
jwz read "loop:current" | tail -1 | jq -r '.stack[-1].iter'
```

## Messaging

Post status updates during issue work:

```bash
# On iteration start
ITER=$(jwz read "loop:current" | tail -1 | jq -r '.stack[-1].iter')
jwz post "issue:$ARGUMENTS" -m "[issue] ITERATION $ITER: Retrying after failure"

# On stuck
jwz post "issue:$ARGUMENTS" -m "[issue] STUCK: Same error 3 times - needs help"

# On complete
jwz post "issue:$ARGUMENTS" -m "[issue] COMPLETE: Issue resolved"
```

## Iteration Context

Before each retry:
- `git status` - modified files
- `git log --oneline -10` - recent commits
- `tissue show "$ARGUMENTS"` - re-read the issue

## Completion

**Success** (review passes, issue closed):
```
<loop-done>COMPLETE</loop-done>
```

**Max iterations**:
```
<loop-done>MAX_ITERATIONS</loop-done>
```
Pause the issue and summarize progress:
```bash
tissue status "$ARGUMENTS" paused
tissue comment "$ARGUMENTS" -m "[issue] Max iterations reached. Progress: ..."
```

**Stuck** (same error 3 times):
```
<loop-done>STUCK</loop-done>
```
Pause and describe the specific blocker.

## Cleanup

The stop hook handles stack management. When this issue completes:
- If nested in grind: frame is popped, grind continues
- If standalone: loop state is cleared
