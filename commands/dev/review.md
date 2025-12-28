---
description: Run code review via reviewer agent
---

# Review Command

Run code review on current changes using the reviewer agent.

## Usage

```
/review [issue-id]
```

## Pre-check

First, verify there are changes to review:
```bash
git diff --stat
git diff --cached --stat
```

If **no changes** (both empty):
- Report "No changes to review"
- Stop

## Steps

Invoke the reviewer agent:

```
Task(subagent_type="idle:reviewer", prompt="Review the current changes. $ARGUMENTS")
```

The reviewer agent will:
1. Run `git diff` to see changes
2. Look for project style guides in docs/ or CONTRIBUTING.md
3. Collaborate with Codex for a second opinion
4. Return verdict: LGTM or CHANGES_REQUESTED

## Post-Review (on LGTM)

After a successful review, persist review markers for the stop hook:

```bash
# Get current HEAD SHA
CURRENT_SHA=$(git rev-parse HEAD)

# Update loop state with review marker (if in a loop)
if command -v jwz >/dev/null 2>&1 && [ -d .jwz ]; then
    STATE=$(jwz read "loop:current" 2>/dev/null | tail -1 || true)
    if [ -n "$STATE" ] && echo "$STATE" | jq -e '.stack | length > 0' >/dev/null 2>&1; then
        # Update top frame with last_reviewed_sha
        NOW=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
        RUN_ID=$(echo "$STATE" | jq -r '.run_id')
        NEW_STACK=$(echo "$STATE" | jq --arg sha "$CURRENT_SHA" '.stack[-1].last_reviewed_sha = $sha')
        jwz post "loop:current" -m "{\"schema\":1,\"event\":\"STATE\",\"run_id\":\"$RUN_ID\",\"updated_at\":\"$NOW\",\"stack\":$(echo "$NEW_STACK" | jq -c '.stack')}"
    fi
fi
```

This marker tells the stop hook that the current HEAD has been reviewed.
