---
description: Work an issue with iteration (retries on failure)
---

# Issue Command

Like `/work`, but with iteration - keep trying until the issue is resolved. Each issue gets its own Git worktree for clean isolation.

## Usage

```
/issue <issue-id>
```

## Limits

- **Max iterations**: 10
- **Stuck threshold**: 3 consecutive failures with same error

## How It Works

This command:
1. Creates a Git worktree for the issue (branch: `idle/issue/<id>`)
2. Uses a **Stop hook** to intercept exit and force re-entry until resolved
3. Stores loop state via jwz messaging (including worktree path)

When called from `/grind`, this pushes a new frame onto the loop stack.

## Setup

Initialize worktree and loop state:
```bash
# Generate IDs
RUN_ID="issue-$ARGUMENTS-$(date +%s)"
ISSUE_ID="$ARGUMENTS"
REPO_ROOT=$(git rev-parse --show-toplevel)

# Validate issue exists
if ! tissue show "$ISSUE_ID" >/dev/null 2>&1; then
    echo "Error: Issue $ISSUE_ID not found"
    exit 1
fi

# Change to repo root for git operations
cd "$REPO_ROOT"

# Ensure jwz is initialized
[ ! -d .jwz ] && jwz init

# Resolve base ref (config > origin/HEAD > main > master > HEAD)
BASE_REF=""
BASE_REF=$(git config idle.baseRef 2>/dev/null) || true
if [[ -z "$BASE_REF" ]]; then
    BASE_REF=$(git symbolic-ref refs/remotes/origin/HEAD 2>/dev/null | sed 's|refs/remotes/||') || true
fi
if [[ -z "$BASE_REF" ]] && git show-ref --verify refs/heads/main >/dev/null 2>&1; then
    BASE_REF="main"
fi
if [[ -z "$BASE_REF" ]] && git show-ref --verify refs/heads/master >/dev/null 2>&1; then
    BASE_REF="master"
fi
if [[ -z "$BASE_REF" ]]; then
    BASE_REF="HEAD"
fi

# Sanitize issue ID for branch name
SAFE_ID=$(printf '%s' "$ISSUE_ID" | tr -cd 'a-zA-Z0-9_-')
if [[ -z "$SAFE_ID" ]]; then
    echo "Error: Issue ID '$ISSUE_ID' contains no valid characters"
    exit 1
fi
BRANCH="idle/issue/$SAFE_ID"
WORKTREE_PATH="$REPO_ROOT/.worktrees/idle/$SAFE_ID"

# Ensure .worktrees/ is gitignored
if ! grep -q '^\.worktrees/' "$REPO_ROOT/.gitignore" 2>/dev/null; then
    echo ".worktrees/" >> "$REPO_ROOT/.gitignore"
fi

# Check if worktree already exists
if git worktree list | grep -qF "$WORKTREE_PATH"; then
    # Verify path/branch consistency (catches case-insensitive filesystem collisions)
    EXISTING_REF=$(git -C "$WORKTREE_PATH" symbolic-ref -q HEAD 2>/dev/null || echo "DETACHED")
    if [[ "$EXISTING_REF" != "refs/heads/$BRANCH" ]]; then
        echo "Error: Worktree path collision - $WORKTREE_PATH exists but is on $EXISTING_REF, not $BRANCH"
        echo "This may be a case-insensitive filesystem collision (e.g., 'ABC' vs 'abc')."
        exit 1
    fi
    echo "Reusing existing worktree at $WORKTREE_PATH"
else
    # Create worktree with new branch
    mkdir -p "$(dirname "$WORKTREE_PATH")"
    git worktree add -b "$BRANCH" "$WORKTREE_PATH" "$BASE_REF" 2>/dev/null || \
    git worktree add "$WORKTREE_PATH" "$BRANCH"  # Branch already exists

    # Initialize submodules in worktree (if any exist)
    if [[ -f "$REPO_ROOT/.gitmodules" ]]; then
        echo "Initializing submodules in worktree..."
        git -C "$WORKTREE_PATH" submodule update --init --recursive
    fi
fi

# Create temp directory for prompt file
STATE_DIR="/tmp/idle-$RUN_ID"
mkdir -p "$STATE_DIR"
tissue show "$ISSUE_ID" > "$STATE_DIR/prompt.txt"

# Check if we're nested inside grind (existing stack)
EXISTING=$(jwz read "loop:current" 2>/dev/null | tail -1)
if [[ -z "$EXISTING" ]] || ! echo "$EXISTING" | jq -e . >/dev/null 2>&1; then
    EXISTING='{"stack":[]}'
fi
EXISTING_STACK=$(echo "$EXISTING" | jq -c '.stack // []')
PARENT_RUN_ID=$(echo "$EXISTING" | jq -r '.run_id // empty')
ACTIVE_RUN_ID="${PARENT_RUN_ID:-$RUN_ID}"

# Push new frame onto stack (includes worktree info)
NOW=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
NEW_FRAME=$(jq -n \
    --arg id "$RUN_ID" \
    --arg issue_id "$ISSUE_ID" \
    --arg prompt_file "$STATE_DIR/prompt.txt" \
    --arg worktree_path "$WORKTREE_PATH" \
    --arg branch "$BRANCH" \
    --arg base_ref "$BASE_REF" \
    '{
        id: $id,
        mode: "issue",
        iter: 1,
        max: 10,
        prompt_file: $prompt_file,
        issue_id: $issue_id,
        worktree_path: $worktree_path,
        branch: $branch,
        base_ref: $base_ref
    }')
NEW_STACK=$(echo "$EXISTING_STACK" | jq --argjson frame "$NEW_FRAME" '. + [$frame]')

jwz post "loop:current" -m "{\"schema\":1,\"event\":\"STATE\",\"run_id\":\"$ACTIVE_RUN_ID\",\"updated_at\":\"$NOW\",\"stack\":$NEW_STACK}"

# Announce on issue topic
jwz topic new "issue:$ISSUE_ID" 2>/dev/null || true
jwz post "issue:$ISSUE_ID" -m "[issue] STARTED: Working in $WORKTREE_PATH on branch $BRANCH"
```

## Worktree Context

All file operations must use the worktree path:
- **Read/Write/Edit**: Use absolute paths under `$WORKTREE_PATH`
- **Bash**: Prefix commands with `cd "$WORKTREE_PATH" && ...`
- **tissue commands**: Run from main repo (not worktree)

The stop hook injects worktree context on each iteration.

## Workflow

1. Read the issue: `tissue show "$ISSUE_ID"`
2. Implement the fix in the worktree
3. On failure: analyze, retry (stop hook re-injects)
4. On success: output `<loop-done>COMPLETE</loop-done>`
5. Land with `/land $ISSUE_ID` when ready

## Iteration Tracking

The stop hook increments iteration automatically. Check current:
```bash
jwz read "loop:current" | tail -1 | jq -r '.stack[-1].iter'
```

## Messaging

```bash
# On iteration
ITER=$(jwz read "loop:current" | tail -1 | jq -r '.stack[-1].iter')
jwz post "issue:$ISSUE_ID" -m "[issue] ITERATION $ITER: Retrying after failure"

# On complete
jwz post "issue:$ISSUE_ID" -m "[issue] COMPLETE: Ready to land"
```

## Definition of Done

Before emitting a completion signal, you MUST:

1. **If files were changed**: Run `/review` and address feedback
2. **If `/review` returns CHANGES_REQUESTED**: Fix issues, re-run `/review` (max 3 iterations)
3. **If skipping review**: State the reason explicitly (e.g., "documentation-only change")

The stop hook tracks review state. If you try to complete without review, you'll be reminded.

**When stuck on design decisions**: Consult `idle:oracle` before making architectural choices.

## Completion

**Success**:
```
<loop-done>COMPLETE</loop-done>
```
The worktree remains for review. Use `/land $ISSUE_ID` to merge.

**Max iterations**:
```
<loop-done>MAX_ITERATIONS</loop-done>
```
Pause the issue:
```bash
tissue status "$ISSUE_ID" paused
tissue comment "$ISSUE_ID" -m "[issue] Max iterations. Worktree at $WORKTREE_PATH"
```

**Stuck**:
```
<loop-done>STUCK</loop-done>
```
Pause and describe the blocker.

## Cleanup

The worktree persists after completion for review. To clean up:
- `/land $ISSUE_ID` - Merge and remove worktree
- `/worktree remove $ISSUE_ID` - Remove without merging
