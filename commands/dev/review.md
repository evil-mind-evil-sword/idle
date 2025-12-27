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
Task(subagent_type="reviewer", prompt="Review the current changes. Issue: <issue-id or 'uncommitted'>")
```

The reviewer agent will:
1. Run `git diff` to see changes
2. Look for project style guides in docs/ or CONTRIBUTING.md
3. Collaborate with Codex for a second opinion
4. Return verdict: LGTM or CHANGES_REQUESTED
