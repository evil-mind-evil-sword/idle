---
description: Continuously work through the issue tracker
---

# Grind Command

Run `/issue` in a loop over all matching issues.

## Usage

```
/grind [filter]
```

Filter examples: `repl`, `epic:slop2-abc`, `priority:1`

## Limits

- **Max issues per session**: 100
- **Per-issue limit**: Inherited from `/issue` (10 iterations)
- **Max review iterations per issue**: 3

## How It Works

This command uses a **Stop hook** to intercept Claude's exit and force re-entry until all issues are processed. Loop state is stored via jwz messaging.

Grind pushes a frame onto the loop stack. When it calls `/issue`, that pushes another frame. When issue completes, its frame is popped and grind continues.

## Setup

Initialize loop state via jwz:
```bash
# Generate unique run ID
RUN_ID="grind-$(date +%s)-$$"

# Ensure jwz is initialized
[ ! -d .jwz ] && jwz init

# Create temp directory for prompt/state
STATE_DIR="/tmp/trivial-$RUN_ID"
mkdir -p "$STATE_DIR"

# Store filter as prompt
echo "$ARGUMENTS" > "$STATE_DIR/prompt.txt"
echo "0" > "$STATE_DIR/count"

# Post initial state to jwz
NOW=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
jwz post "loop:current" -m "{\"schema\":1,\"event\":\"STATE\",\"run_id\":\"$RUN_ID\",\"updated_at\":\"$NOW\",\"stack\":[{\"id\":\"$RUN_ID\",\"mode\":\"grind\",\"iter\":1,\"max\":100,\"prompt_file\":\"$STATE_DIR/prompt.txt\",\"filter\":\"$ARGUMENTS\"}]}"

# Announce session start
jwz post "project:$(basename $PWD)" -m "[grind] STARTED: Session $RUN_ID with filter: $ARGUMENTS"
```

## Messaging

Post status updates during grind:

```bash
# On issue start
jwz post "issue:$ISSUE_ID" -m "[grind] WORKING: Starting issue"

# On issue complete
jwz post "issue:$ISSUE_ID" -m "[grind] DONE: Completed - see commit $(git rev-parse --short HEAD)"

# On grind complete
COUNT=$(cat "$STATE_DIR/count")
jwz post "project:$(basename $PWD)" -m "[grind] COMPLETE: $COUNT issues processed"
```

## Workflow

Repeat until limit or no issues:

1. **Check limits**:
   ```bash
   COUNT=$(cat "$STATE_DIR/count")
   if [ "$COUNT" -ge 100 ]; then
     jwz post "project:$(basename $PWD)" -m "[grind] DONE: Hit max issues limit"
     echo "<grind-done>MAX_ISSUES</grind-done>"
     exit
   fi
   ```

2. **Find next issue**:
   - `tissue ready --json`
   - Filter by context (tag, epic, priority) if provided
   - Pick highest priority match (P1 > P2 > P3)
   - If none remain: `<grind-done>NO_MORE_ISSUES</grind-done>`

3. **Work it**: Run `/issue <issue-id>`

4. **Review loop** (max 3 iterations):
   ```bash
   echo "0" > "$STATE_DIR/review_iter"
   ```

   a. Run `/review` to check code quality via the reviewer agent

   b. If **LGTM**: Exit review loop, continue to step 5

   c. If **CHANGES_REQUESTED**:
      - Increment review iteration count
      - If count >= 3:
        - Create new issue(s) for remaining problems via `tissue new`
        - Tag with `review-followup` and link to original issue
        - Exit review loop, continue to step 5
      - Fix the requested changes
      - Go back to step 4a

5. **Track**:
   ```bash
   echo "$((COUNT + 1))" > "$STATE_DIR/count"
   ```

6. **On completion**: Output `<issue-complete>DONE</issue-complete>`

7. **Continue**: Go to step 1

## Pause Conditions

If `/issue` returns STUCK or MAX_ITERATIONS:
- Issue is already paused by `/issue`
- Continue to next issue

## Completion

**All done**:
```
<grind-done>NO_MORE_ISSUES</grind-done>
```

**Session limit**:
```
<grind-done>MAX_ISSUES</grind-done>
```
Report: X issues completed, Y remaining.

**User cancelled**: `/cancel-loop`

## Escape Hatches

If you get stuck in an infinite loop:
1. `/cancel-loop` - Graceful cancellation
2. `TRIVIAL_LOOP_DISABLE=1 claude` - Environment variable bypass
3. Delete `.jwz/` directory - Manual reset
