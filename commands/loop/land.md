---
description: Land completed issue work (merge worktree branch)
---

# Land Command

Merge a completed issue's worktree branch into the base branch and clean up.

## Usage

```
/land <issue-id>
```

## Prerequisites

Before landing:
1. Issue work is complete (tests pass, reviewed)
2. Worktree has no uncommitted changes
3. Main branch is clean

## Workflow

1. **Validate worktree exists**:
   ```bash
   REPO_ROOT=$(git rev-parse --show-toplevel)
   SAFE_ID=$(printf '%s' "$ARGUMENTS" | tr -cd 'a-zA-Z0-9_-')
   if [[ -z "$SAFE_ID" ]]; then
       echo "Error: Invalid issue ID"
       exit 1
   fi
   BRANCH="trivial/issue/$SAFE_ID"
   WORKTREE_PATH="$REPO_ROOT/.worktrees/trivial/$SAFE_ID"

   if ! git worktree list | grep -qF -- "$WORKTREE_PATH"; then
       echo "Error: No worktree found for issue $ARGUMENTS"
       exit 1
   fi
   ```

2. **Check worktree is clean** (both staged and unstaged):
   ```bash
   if ! git -C "$WORKTREE_PATH" diff --quiet || ! git -C "$WORKTREE_PATH" diff --cached --quiet; then
       echo "Error: Worktree has uncommitted changes"
       git -C "$WORKTREE_PATH" status --short
       exit 1
   fi
   ```

3. **Check worktree has commits**:
   ```bash
   BASE_REF=$(git -C "$WORKTREE_PATH" merge-base HEAD @{upstream} 2>/dev/null || \
              git -C "$WORKTREE_PATH" merge-base HEAD main 2>/dev/null || \
              git -C "$WORKTREE_PATH" merge-base HEAD master)

   COMMITS=$(git -C "$WORKTREE_PATH" rev-list --count "$BASE_REF"..HEAD)
   if [[ "$COMMITS" == "0" ]]; then
       echo "Warning: No commits to land"
   fi
   ```

4. **Check main branch is clean** (both staged and unstaged):
   ```bash
   if ! git diff --quiet || ! git diff --cached --quiet; then
       echo "Error: Main worktree has uncommitted changes"
       git status --short
       exit 1
   fi
   ```

5. **Attempt fast-forward merge**:
   ```bash
   git fetch origin
   git checkout main  # or master

   if git merge --ff-only "$BRANCH"; then
       echo "Fast-forward merge successful"
   else
       echo "Cannot fast-forward. Options:"
       echo "  1. Rebase: git -C $WORKTREE_PATH rebase main"
       echo "  2. Squash: git merge --squash $BRANCH"
       echo "  3. Merge commit: git merge $BRANCH"
       exit 1
   fi
   ```

6. **Push changes**:
   ```bash
   git push origin main
   ```

7. **Clean up worktree and branch**:
   ```bash
   git worktree remove "$WORKTREE_PATH"
   git branch -d "$BRANCH"
   ```

8. **Update tissue**:
   ```bash
   tissue status "$ARGUMENTS" closed
   tissue comment "$ARGUMENTS" -m "[land] Merged to main and cleaned up"
   ```

9. **Post to jwz**:
   ```bash
   jwz post "issue:$ARGUMENTS" -m "[land] MERGED: Issue landed successfully"
   jwz post "project:$(basename $REPO_ROOT)" -m "[land] Issue $ARGUMENTS merged to main"
   ```

## Merge Strategies

If fast-forward fails, you have options:

### Rebase (recommended for clean history)
```bash
cd "$WORKTREE_PATH"
git rebase main
# Resolve any conflicts
cd "$REPO_ROOT"
/land $ARGUMENTS  # Try again
```

### Squash (for messy commit history)
```bash
git merge --squash "$BRANCH"
git commit -m "feat: $ARGUMENTS - description"
```

### Merge commit (preserve full history)
```bash
git merge "$BRANCH" -m "Merge $BRANCH"
```

## Error Handling

| Error | Resolution |
|-------|------------|
| Worktree not found | Check issue ID, run `/worktree list` |
| Uncommitted changes | Commit or stash in worktree first |
| Cannot fast-forward | Rebase worktree or use squash/merge commit |
| Push rejected | Pull and resolve conflicts first |

## Flags

- `--squash` - Use squash merge instead of fast-forward
- `--force` - Skip dirty worktree check (dangerous)
- `--no-push` - Merge locally but don't push
- `--keep-branch` - Don't delete the branch after merge
