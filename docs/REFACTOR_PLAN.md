# Refactor: Bash Hooks to Zig CLI

**Status**: RESEARCH COMPLETE
**Date**: 2024-12-30
**Confidence**: HIGH

## Executive Summary

Refactor idle's 5 bash hooks (~1026 lines) into a unified Zig CLI tool (`idle-hook`) that links zawinski and tissue as libraries. The existing `tui/` directory already implements ~50% of the core logic.

## Current State Analysis

### Bash Hooks (1026 lines total)

| Hook | Lines | Complexity | Function |
|------|-------|------------|----------|
| stop-hook.sh | 724 | HIGH | Core loop mechanism, review gates, auto-land, pick-next-issue |
| subagent-stop-hook.sh | 147 | MEDIUM | Alice second-opinion gate |
| pre-tool-use-hook.sh | 74 | LOW | Safety guardrails (dangerous git/rm patterns) |
| pre-compact-hook.sh | 72 | LOW | Recovery anchors before compaction |
| session-start-hook.sh | 9 | TRIVIAL | Agent awareness injection |

### Existing Zig Code (tui/)

| File | Lines | Reusable Components |
|------|-------|---------------------|
| state_machine.zig | 399 | State, EventType, Mode, CompletionReason, StackFrame, LoopState, Decision, EvalResult, StateMachine |
| event_parser.zig | 394 | parseEvent, ParsedEvent, parseIso8601, parseStack |
| hook.zig | 309 | HookInput, HookOutput, run() - partial stop hook implementation |
| replay.zig | 308 | TraceEvent, parseTraceEvent, replayTrace (debugging) |
| status.zig | 346 | printJson, runTui - status display |

**Key Finding**: The existing Zig code already implements:
- Full state machine logic
- JSON event parsing
- Basic stop hook flow (but shells out to `jwz` CLI)
- Status display

### Library Integration Patterns

Both zawinski and tissue follow the same pattern:
1. Export a module via `build.zig` with `b.addModule("name", ...)`
2. Provide `src/root.zig` as the public API
3. Key types: `Store`, `StoreError`, domain objects

**zawinski exports**:
- `store.Store` - messaging store with `open()`, `post()`, `read()`, `getTopic()`
- `store.Topic`, `store.Message`, `store.Sender`
- `ids.Generator` - ULID generation
- `git.getMeta()` - git context capture

**tissue exports**:
- `store.Store` - issue store with `open()`, `getIssue()`, `listReady()`
- `store.Issue`, `store.Comment`, `store.Dep`
- `ids.Generator` - ULID generation

## Architecture

### CLI Structure

```
idle-hook <command> [options]
  stop           Stop hook (core loop)
  subagent-stop  Subagent stop hook (alice gate)
  pre-tool-use   Pre-tool-use hook (safety)
  pre-compact    Pre-compact hook (recovery)
  session-start  Session start hook (awareness)
  status         Display loop status (JSON or TUI)
```

### Module Structure

```
idle/
  hook-cli/                    # New Zig CLI
    build.zig                  # Links zawinski, tissue
    src/
      main.zig                 # CLI entry, argument parsing
      hooks/
        stop.zig               # Stop hook (largest)
        subagent_stop.zig      # Alice gate
        pre_tool_use.zig       # Safety checks
        pre_compact.zig        # Recovery anchors
        session_start.zig      # Agent awareness
      lib/
        state_machine.zig      # (moved from tui/)
        event_parser.zig       # (moved from tui/)
        transcript.zig         # Transcript parsing
        review_gate.zig        # Review status checking
        auto_land.zig          # Git merge/push logic
        safety.zig             # Dangerous command patterns
```

### Data Flow

```
Hook Input (stdin JSON)
         |
         v
   +-------------+
   | idle-hook   |----> zawinski.Store (read/write loop state)
   | <command>   |----> tissue.Store (issue status)
   +-------------+----> git operations (worktree, merge)
         |
         v
Hook Output (stdout JSON + exit code)
```

## Implementation Plan

### Phase 1: Foundation (Day 1)

1. **Create build.zig with library linking**
   ```zig
   const zawinski_dep = b.dependency("zawinski", .{ ... });
   const tissue_dep = b.dependency("tissue", .{ ... });
   exe.root_module.addImport("zawinski", zawinski_dep.module("zawinski"));
   exe.root_module.addImport("tissue", tissue_dep.module("tissue"));
   ```

2. **Move and adapt existing tui/ code**
   - Copy state_machine.zig, event_parser.zig
   - Remove shell-out to `jwz`, use library directly

3. **Implement main.zig CLI skeleton**
   - Argument parsing for subcommands
   - Stdin JSON reading
   - Exit code handling

### Phase 2: Simple Hooks (Day 1-2)

4. **session_start.zig** (trivial)
   - Just print 2 lines to stdout

5. **pre_tool_use.zig** (low complexity)
   - Parse tool_input JSON
   - Pattern match dangerous commands
   - Return block decision if matched

6. **pre_compact.zig** (low complexity)
   - Read loop state via zawinski library
   - Build anchor JSON with git context
   - Post to loop:anchor topic

### Phase 3: Subagent Hook (Day 2)

7. **subagent_stop.zig** (medium complexity)
   - Parse transcript (NDJSON)
   - Check for alice patterns in last message
   - Check for second opinion markers
   - Return block decision if missing

### Phase 4: Stop Hook Core (Day 3-4)

8. **stop.zig** - Core logic
   - Read hook input
   - Check escape hatches (.idle-disabled)
   - Read state from zawinski
   - Evaluate state machine
   - Detect completion signals from transcript
   - Output decision JSON

9. **review_gate.zig** - Review checks
   - Parse review messages from jwz
   - Check SHA alignment
   - Count review iterations
   - Handle escalation logic

10. **auto_land.zig** - Git operations
    - Fast-forward verification
    - Worktree cleanup
    - Branch deletion
    - Push to remote
    - Update tissue status

11. **pick_next.zig** - Issue picker
    - Call tissue.store.listReady()
    - Create worktree
    - Initialize submodules
    - Update loop state

### Phase 5: Integration (Day 4-5)

12. **Build system integration**
    - Add to hook-cli/build.zig
    - Cross-compile targets (darwin-x86_64, darwin-aarch64, linux-x86_64)
    - Release builds

13. **Thin bash wrappers**
    ```bash
    #!/bin/bash
    exec "${CLAUDE_PLUGIN_ROOT}/bin/idle-hook" stop
    ```

14. **Update hooks.json**
    - Point to wrapper scripts
    - Same command structure, new backend

15. **Testing**
    - Port existing tests from tui/
    - Add integration tests
    - Test hook I/O contract

### Phase 6: Distribution (Day 5)

16. **Binary distribution**
    - GitHub releases workflow (like tissue/zawinski)
    - install.sh script update
    - Bundle binary with plugin

## Hook I/O Contract

### Stop Hook

**Input** (stdin JSON):
```json
{
  "transcript_path": "/path/to/transcript.jsonl",
  "cwd": "/path/to/project"
}
```

**Output** (stdout JSON):
```json
{
  "decision": "block" | "allow",
  "reason": "human-readable explanation"
}
```

**Exit codes**:
- 0: Allow exit
- 2: Block exit (inject reason)
- Other: Show stderr, allow exit

### PreToolUse Hook

**Input** (stdin JSON):
```json
{
  "tool_name": "Bash",
  "tool_input": {"command": "git push --force main"}
}
```

**Output** (stdout JSON):
```json
{
  "decision": "block",
  "reason": "SAFETY: Force push to main is blocked"
}
```

### SubagentStop Hook

**Input** (stdin JSON):
```json
{
  "agent_id": "alice",
  "agent_transcript_path": "/path/to/agent_transcript.jsonl",
  "cwd": "/path/to/project"
}
```

**Output**: Block if alice without second opinion

### PreCompact Hook

**Input** (stdin JSON):
```json
{
  "cwd": "/path/to/project"
}
```

**Output**: Print recovery pointer to stdout

### SessionStart Hook

**Input**: None
**Output**: Print agent awareness lines

## Risk Assessment

| Risk | Mitigation |
|------|------------|
| Git operations fail | Same logic as bash, add error handling |
| Library API mismatch | Both libraries are internal, can adapt |
| Performance regression | Zig binary will be faster than bash+jq |
| Missing edge cases | Bash code is the spec, port 1:1 |

## Success Criteria

1. All hooks pass existing test suite
2. No behavior change from bash version
3. Binary size < 5MB (sqlite linked statically)
4. Startup time < 50ms
5. No bash shelling out for core operations

## Dependencies

- zawinski (sibling package)
- tissue (sibling package)
- Zig 0.14+ (for build system features)

## Estimated Effort

| Phase | Effort | Risk |
|-------|--------|------|
| Foundation | 4h | Low |
| Simple Hooks | 2h | Low |
| Subagent Hook | 3h | Medium |
| Stop Hook Core | 8h | Medium |
| Integration | 4h | Low |
| Distribution | 2h | Low |
| **Total** | **23h** | Medium |

## Open Questions

1. **Monorepo vs separate repo?** - Recommend keeping in idle/hook-cli since it's tightly coupled
2. **Ship single binary or per-hook?** - Single binary with subcommands (cleaner)
3. **Build during plugin install?** - Ship pre-built binaries (like tissue/jwz)
