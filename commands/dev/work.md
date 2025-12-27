---
description: Pick an issue and work it to completion
---

# Work Command

Work a single issue to completion.

## Usage

```
/work [issue-id]
```

If no issue-id provided, pick from `tissue ready`.

## Phase 1: Select Issue

1. If issue-id provided, use it. Otherwise:
   - Run `tissue ready` to see unblocked issues
   - If **no issues available**: Report "No ready issues" and stop
   - Pick the highest priority (P1 > P2 > P3 > P4 > P5)
2. Run `tissue show <issue-id>` to read details
3. Run `tissue status <issue-id> in_progress` to claim it

## Phase 2: Implement

1. **Understand** requirements before coding
2. **Explore** existing patterns
3. **Implement** following project conventions

## Phase 3: Review Cycle

Repeat until LGTM:

1. `/test` - ensure tests pass
2. `/fmt` - format code
3. Commit: `git add . && git commit -m "type: description"`
4. `/review <issue-id>` - get code review
5. If CHANGES_REQUESTED: fix and repeat from step 1

## Phase 4: Complete

1. `tissue status <issue-id> closed`
2. `git push`
3. Summarize what was accomplished

## Rules

- Do NOT skip the review cycle
- Do NOT review your own code
- If blocked: `tissue comment <issue-id> -m "..."`

## Available Agents

Delegate with Task tool:
- **reviewer** - Code review (Opus + Codex)
- **oracle** - Deep reasoning on hard problems
- **explorer** - "Where is X?" local searches
- **librarian** - Remote code/docs research
- **documenter** - Technical writing (Opus + Gemini)
