#!/bin/bash
# trivial stop hook - implements self-referential loops via jwz messaging
# Intercepts Claude's exit to force continuation until task complete

set -e

# Read hook input from stdin
INPUT=$(cat)

# Extract session info
TRANSCRIPT_PATH=$(echo "$INPUT" | jq -r '.transcript_path // empty')
CWD=$(echo "$INPUT" | jq -r '.cwd // empty')

# Change to project directory
if [[ -n "$CWD" ]]; then
    cd "$CWD"
fi

# Environment variable escape hatch
if [[ "${TRIVIAL_LOOP_DISABLE:-}" == "1" ]]; then
    exit 0
fi

# State file fallback location
STATE_FILE=".claude/trivial-loop.local.md"

# Try to read loop state from jwz first
STATE=""
if command -v jwz >/dev/null 2>&1 && [[ -d .jwz ]]; then
    # Get the latest message from loop:current topic
    STATE=$(jwz read "loop:current" 2>/dev/null | tail -1 || true)
fi

# Parse state (either from jwz JSON or fallback to state file)
if [[ -n "$STATE" ]] && echo "$STATE" | jq -e '.schema' >/dev/null 2>&1; then
    # jwz JSON state
    STACK_LEN=$(echo "$STATE" | jq -r '.stack | length')

    if [[ "$STACK_LEN" == "0" ]] || [[ -z "$STACK_LEN" ]]; then
        # No active loop
        exit 0
    fi

    # Check for ABORT event
    EVENT=$(echo "$STATE" | jq -r '.event // "STATE"')
    if [[ "$EVENT" == "ABORT" ]]; then
        exit 0
    fi

    # Check staleness (2 hour TTL)
    UPDATED_AT=$(echo "$STATE" | jq -r '.updated_at // empty')
    if [[ -n "$UPDATED_AT" ]]; then
        UPDATED_TS=$(date -j -f "%Y-%m-%dT%H:%M:%S" "${UPDATED_AT%Z}" +%s 2>/dev/null || \
                     date -d "$UPDATED_AT" +%s 2>/dev/null || echo 0)
        NOW_TS=$(date +%s)
        AGE=$((NOW_TS - UPDATED_TS))
        if [[ $AGE -gt 7200 ]]; then
            echo "Warning: Loop state is stale ($AGE seconds old), allowing exit" >&2
            exit 0
        fi
    fi

    # Get top of stack (current loop frame)
    TOP=$(echo "$STATE" | jq -r '.stack[-1]')
    MODE=$(echo "$TOP" | jq -r '.mode')
    ITERATION=$(echo "$TOP" | jq -r '.iter')
    MAX_ITERATIONS=$(echo "$TOP" | jq -r '.max')
    PROMPT_FILE=$(echo "$TOP" | jq -r '.prompt_file // empty')
    RUN_ID=$(echo "$STATE" | jq -r '.run_id')

    USE_JWZ=true
else
    # Fallback to state file
    if [[ ! -f "$STATE_FILE" ]]; then
        exit 0
    fi

    # Parse YAML frontmatter
    parse_yaml_value() {
        local key="$1"
        sed -n '/^---$/,/^---$/p' "$STATE_FILE" | grep "^${key}:" | sed "s/^${key}: *//"
    }

    ACTIVE=$(parse_yaml_value "active")
    if [[ "$ACTIVE" != "true" ]]; then
        rm -f "$STATE_FILE"
        exit 0
    fi

    MODE=$(parse_yaml_value "mode")
    ITERATION=$(parse_yaml_value "iteration")
    MAX_ITERATIONS=$(parse_yaml_value "max_iterations")
    PROMPT_FILE=""

    USE_JWZ=false
fi

# Validate numeric values
if ! [[ "$ITERATION" =~ ^[0-9]+$ ]] || ! [[ "$MAX_ITERATIONS" =~ ^[0-9]+$ ]]; then
    echo "Warning: Corrupted loop state, cleaning up" >&2
    if [[ "$USE_JWZ" == "true" ]]; then
        jwz post "loop:current" -m '{"schema":1,"event":"ABORT","stack":[]}'
    else
        rm -f "$STATE_FILE"
    fi
    exit 0
fi

# Check if max iterations reached
if [[ $ITERATION -ge $MAX_ITERATIONS ]]; then
    if [[ "$USE_JWZ" == "true" ]]; then
        jwz post "loop:current" -m '{"schema":1,"event":"DONE","reason":"MAX_ITERATIONS","stack":[]}'
    else
        rm -f "$STATE_FILE"
    fi
    exit 0
fi

# Read transcript and check for completion signals
COMPLETION_FOUND=false
COMPLETION_REASON=""

if [[ -n "$TRANSCRIPT_PATH" ]] && [[ -f "$TRANSCRIPT_PATH" ]]; then
    # Get last assistant message
    LAST_MESSAGE=$(tail -20 "$TRANSCRIPT_PATH" | \
        jq -r 'select(.type == "assistant") | .message.content[]? | select(.type == "text") | .text' 2>/dev/null | \
        tail -1 || true)

    # Check for completion signals based on mode
    case "$MODE" in
        loop)
            if echo "$LAST_MESSAGE" | grep -q '<loop-done>COMPLETE</loop-done>'; then
                COMPLETION_FOUND=true
                COMPLETION_REASON="COMPLETE"
            elif echo "$LAST_MESSAGE" | grep -q '<loop-done>MAX_ITERATIONS</loop-done>'; then
                COMPLETION_FOUND=true
                COMPLETION_REASON="MAX_ITERATIONS"
            elif echo "$LAST_MESSAGE" | grep -q '<loop-done>STUCK</loop-done>'; then
                COMPLETION_FOUND=true
                COMPLETION_REASON="STUCK"
            fi
            ;;
        issue)
            if echo "$LAST_MESSAGE" | grep -q '<loop-done>COMPLETE</loop-done>'; then
                COMPLETION_FOUND=true
                COMPLETION_REASON="COMPLETE"
            elif echo "$LAST_MESSAGE" | grep -q '<loop-done>MAX_ITERATIONS</loop-done>'; then
                COMPLETION_FOUND=true
                COMPLETION_REASON="MAX_ITERATIONS"
            elif echo "$LAST_MESSAGE" | grep -q '<loop-done>STUCK</loop-done>'; then
                COMPLETION_FOUND=true
                COMPLETION_REASON="STUCK"
            elif echo "$LAST_MESSAGE" | grep -q '<issue-complete>DONE</issue-complete>'; then
                COMPLETION_FOUND=true
                COMPLETION_REASON="COMPLETE"
            fi
            ;;
        grind)
            if echo "$LAST_MESSAGE" | grep -q '<grind-done>NO_MORE_ISSUES</grind-done>'; then
                COMPLETION_FOUND=true
                COMPLETION_REASON="NO_MORE_ISSUES"
            elif echo "$LAST_MESSAGE" | grep -q '<grind-done>MAX_ISSUES</grind-done>'; then
                COMPLETION_FOUND=true
                COMPLETION_REASON="MAX_ISSUES"
            fi
            # For grind, <issue-complete> means pop issue frame, not exit grind
            ;;
    esac
fi

# If completion signal found, clean up and allow exit
if [[ "$COMPLETION_FOUND" == "true" ]]; then
    if [[ "$USE_JWZ" == "true" ]]; then
        # Pop the completed frame from stack
        NEW_STACK=$(echo "$STATE" | jq '.stack[:-1]')
        STACK_LEN=$(echo "$NEW_STACK" | jq 'length')

        if [[ "$STACK_LEN" == "0" ]]; then
            # All loops complete
            jwz post "loop:current" -m "{\"schema\":1,\"event\":\"DONE\",\"reason\":\"$COMPLETION_REASON\",\"stack\":[]}"
        else
            # Pop frame, continue outer loop
            NOW=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
            jwz post "loop:current" -m "{\"schema\":1,\"event\":\"STATE\",\"run_id\":\"$RUN_ID\",\"updated_at\":\"$NOW\",\"stack\":$NEW_STACK}"
            # Don't exit - let outer loop continue
            # Actually, for now we allow exit and let the outer loop re-invoke
        fi
    else
        rm -f "$STATE_FILE"
    fi
    exit 0
fi

# No completion signal found - continue the loop

# Increment iteration counter
NEW_ITERATION=$((ITERATION + 1))
NOW=$(date -u +"%Y-%m-%dT%H:%M:%SZ")

if [[ "$USE_JWZ" == "true" ]]; then
    # Update top of stack with new iteration
    NEW_STACK=$(echo "$STATE" | jq --argjson iter "$NEW_ITERATION" '.stack[-1].iter = $iter')
    jwz post "loop:current" -m "{\"schema\":1,\"event\":\"STATE\",\"run_id\":\"$RUN_ID\",\"updated_at\":\"$NOW\",\"stack\":$(echo "$NEW_STACK" | jq -c '.stack')}"
else
    # Update state file
    TEMP_FILE=$(mktemp)
    sed "s/^iteration: .*/iteration: $NEW_ITERATION/" "$STATE_FILE" > "$TEMP_FILE"
    mv "$TEMP_FILE" "$STATE_FILE"
fi

# Get original prompt
if [[ -n "$PROMPT_FILE" ]] && [[ -f "$PROMPT_FILE" ]]; then
    ORIGINAL_PROMPT=$(cat "$PROMPT_FILE")
elif [[ "$USE_JWZ" != "true" ]] && [[ -f "$STATE_FILE" ]]; then
    # Extract from state file (everything after second ---)
    ORIGINAL_PROMPT=$(sed -n '/^---$/,/^---$/!p' "$STATE_FILE" | tail -n +1)
else
    ORIGINAL_PROMPT="Continue working on the task."
fi

# Escape the prompt for JSON
ESCAPED_PROMPT=$(printf '%s' "$ORIGINAL_PROMPT" | jq -Rs '.')

# Build continuation message
CONTINUE_MSG="[ITERATION $NEW_ITERATION/$MAX_ITERATIONS] $ORIGINAL_PROMPT"

# Output block decision (exit code 2 = block)
cat <<EOF
{
  "decision": "block",
  "reason": "[ITERATION $NEW_ITERATION/$MAX_ITERATIONS] Continue working on the task. Check your progress and either complete the task or keep iterating."
}
EOF

exit 2
