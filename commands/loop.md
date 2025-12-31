---
description: Iterate on a task until complete
---

# /loop

Iterate on a task until it's complete.

## Usage

```
/loop <task description>
```

## Example

```sh
/loop Add input validation to API endpoints
```

Iterates on the task until complete.

- **Max iterations**: 10
- **Checkpoint reviews**: Every 3 iterations (alice)
- **Completion review**: On COMPLETE/STUCK signals (alice)

## Bootstrap (first run)

The loop is driven by state in `.zawinski/` on topic `loop:current`. If there is no active loop state yet, initialize it once before iterating:

```bash
# Initialize jwz store if needed
[ -d .zawinski ] || jwz init

# Ensure the topic exists (jwz won't auto-create topics on post)
jwz topic new loop:current --quiet >/dev/null 2>&1 || true

# If no active loop is present, seed loop:current with an initial STATE
RUN_ID="loop-$(date -u +%s)"
UPDATED_AT="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
jwz post loop:current -m "{\"schema\":1,\"event\":\"STATE\",\"run_id\":\"$RUN_ID\",\"updated_at\":\"$UPDATED_AT\",\"stack\":[{\"id\":\"$RUN_ID\",\"mode\":\"loop\",\"iter\":0,\"max\":10,\"prompt_file\":\"\",\"reviewed\":false,\"checkpoint_reviewed\":false}]}"
```

If a loop is already active, do **not** overwrite it — just continue working.

## Completion Signals

Signal completion status in your response:

| Signal | Meaning |
|--------|---------|
| `<loop-done>COMPLETE</loop-done>` | Task finished successfully |
| `<loop-done>STUCK</loop-done>` | Cannot make progress |
| `<loop-done>MAX_ITERATIONS</loop-done>` | Hit iteration limit |

## Alice Review

When you signal `COMPLETE` or `STUCK`, the Stop hook:
1. Blocks exit
2. Requests alice review
3. Alice analyzes your work using domain-specific checklists
4. Creates tissue issues for problems (tagged `alice-review`)
5. If approved (no issues) → exit. If not → continue.

This ensures quality before completion.

## Checkpoint Reviews

Every 3 iterations, alice performs a checkpoint review to:
- Check progress against the original task
- Identify issues early
- Provide guidance for next steps

## Escape Hatches

```sh
/cancel                  # Graceful cancellation
touch .idle-disabled     # Bypass hooks
rm -rf .zawinski/        # Reset all jwz state
```
