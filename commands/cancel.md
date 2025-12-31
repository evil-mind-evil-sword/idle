---
description: Cancel the active loop
---

# /cancel

Stop the current loop gracefully.

## What It Does

1. Posts an `ABORT` event to `loop:current` in jwz
2. The Stop hook sees the abort state and allows exit

## Usage

```
/cancel
```

## Alternative Methods

If `/cancel` doesn't work:

| Method | Command |
|--------|---------|
| File bypass | `touch .idle-disabled` (remove after) |
| Manual abort | `jwz post "loop:current" -m '{"schema":1,"event":"ABORT","stack":[]}'` |
| Full reset | `rm -rf .zawinski/` |
