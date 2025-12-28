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

## Session State

```bash
# Inherit or generate session ID
SID="${TRIVIAL_SESSION_ID:-$(date +%s)-$$}"

# Sanitize: only allow alphanumeric, dash, underscore (prevent path traversal)
SID=$(printf '%s' "$SID" | tr -cd 'a-zA-Z0-9_-')
[[ -z "$SID" ]] && SID="$(date +%s)-$$"

export TRIVIAL_SESSION_ID="$SID"
STATE_DIR="/tmp/trivial-$SID"
mkdir -p "$STATE_DIR"
```

## Setup

```bash
echo "$ARGUMENTS" > "$STATE_DIR/issue"
echo "0" > "$STATE_DIR/iter"

# Initialize messaging and announce
[ ! -d .jwz ] && jwz init
jwz topic new "issue:$ARGUMENTS" 2>/dev/null || true
jwz post "issue:$ARGUMENTS" -m "[issue] STARTED: Beginning work on issue"
```

## Messaging

Post status updates during issue work:

```bash
# On iteration start
jwz post "issue:$ARGUMENTS" -m "[issue] ITERATION $ITER: Retrying after failure"

# On stuck
jwz post "issue:$ARGUMENTS" -m "[issue] STUCK: Same error 3 times - needs help"

# On complete
jwz post "issue:$ARGUMENTS" -m "[issue] COMPLETE: Issue resolved"
```

## Workflow

Run `/work $ARGUMENTS` with these additions:

1. **On failure**: Increment iteration count, analyze, retry
2. **On stuck**: After 3 similar failures, pause and escalate
3. **On success**: Output `<loop-done>COMPLETE</loop-done>`
4. **On max iterations**: Stop and report

## Iteration Tracking

```bash
ITER=$(($(cat "$STATE_DIR/iter") + 1))
echo "$ITER" > "$STATE_DIR/iter"
if [ "$ITER" -ge 10 ]; then
  echo "<loop-done>MAX_ITERATIONS</loop-done>"
  exit
fi
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

```bash
rm -f "$STATE_DIR/iter" "$STATE_DIR/issue"
# Don't remove STATE_DIR if called from /grind
```
