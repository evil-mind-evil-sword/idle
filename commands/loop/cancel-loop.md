---
description: Cancel the active loop
---

# Cancel Loop

Stop the current iteration loop gracefully.

## Steps

1. **Check for active loop via jwz**:
   ```bash
   if command -v jwz >/dev/null 2>&1 && [ -d .jwz ]; then
       STATE=$(jwz read "loop:current" 2>/dev/null | tail -1 || true)
       if [ -n "$STATE" ] && echo "$STATE" | jq -e '.stack | length > 0' >/dev/null 2>&1; then
           # Get current loop info
           MODE=$(echo "$STATE" | jq -r '.stack[-1].mode')
           ITER=$(echo "$STATE" | jq -r '.stack[-1].iter')
           ISSUE_ID=$(echo "$STATE" | jq -r '.stack[-1].issue_id // empty')

           echo "Cancelling $MODE loop at iteration $ITER"

           # Pause issue if applicable
           if [ -n "$ISSUE_ID" ]; then
               tissue status "$ISSUE_ID" paused 2>/dev/null || true
               tissue comment "$ISSUE_ID" -m "[cancel] Loop cancelled by user at iteration $ITER" 2>/dev/null || true
           fi

           # Post abort event
           jwz post "loop:current" -m '{"schema":1,"event":"ABORT","reason":"USER_CANCELLED","stack":[]}'
           jwz post "project:$(basename $PWD)" -m "[loop] CANCELLED: User aborted at iteration $ITER"

           echo "Loop cancelled successfully"
       else
           echo "No active loop found in jwz"
       fi
   fi
   ```

2. **Fallback: Check state file**:
   ```bash
   STATE_FILE=".claude/trivial-loop.local.md"
   if [ -f "$STATE_FILE" ]; then
       ITER=$(grep '^iteration:' "$STATE_FILE" | sed 's/iteration: *//')
       echo "Cancelling loop at iteration $ITER (state file)"
       rm -f "$STATE_FILE"
       echo "Loop cancelled successfully"
   fi
   ```

3. **Clean up temp state** (if session ID known):
   ```bash
   if [ -n "$TRIVIAL_SESSION_ID" ]; then
       SID=$(printf '%s' "$TRIVIAL_SESSION_ID" | tr -cd 'a-zA-Z0-9_-')
       [ -n "$SID" ] && rm -rf "/tmp/trivial-$SID"
       unset TRIVIAL_SESSION_ID
   fi
   ```

4. **Summarize** what was accomplished before cancellation

## Alternative Escape Methods

If `/cancel-loop` doesn't work:

1. **Environment variable**: Start new session with loops disabled:
   ```bash
   TRIVIAL_LOOP_DISABLE=1 claude
   ```

2. **Manual reset**: Delete the jwz topic:
   ```bash
   rm -rf .jwz/topics/loop:current/
   ```

3. **Nuclear option**: Delete all jwz state:
   ```bash
   rm -rf .jwz/
   ```
