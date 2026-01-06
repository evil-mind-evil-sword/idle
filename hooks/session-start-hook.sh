#!/bin/bash
# idle SessionStart hook
# Injects context about the idle system into the main agent
#
# Output: JSON with context field for injection
# Exit 0 always

# Ensure we always output valid JSON, even on error
trap 'echo "{\"hookSpecificOutput\": {\"hookEventName\": \"SessionStart\", \"additionalContext\": \"idle: hook error\"}}"; exit 0' ERR

set -uo pipefail

# Read hook input from stdin
INPUT=$(cat || echo '{}')

CWD=$(echo "$INPUT" | jq -r '.cwd // "."')
SESSION_ID=$(echo "$INPUT" | jq -r '.session_id // "default"')

cd "$CWD"

# Self-healing: create ~/.claude/idle/ stores as global defaults
# Users can override with TISSUE_STORE/JWZ_STORE env vars
IDLE_DIR="${HOME}/.claude/idle"
IDLE_TISSUE_STORE="$IDLE_DIR/.tissue"
IDLE_JWZ_STORE="$IDLE_DIR/.jwz"

# Create idle directory structure
mkdir -p "$IDLE_DIR" 2>/dev/null || true

# Auto-initialize tissue store if not already present
if command -v tissue &>/dev/null && [[ ! -d "$IDLE_TISSUE_STORE" ]]; then
    tissue --store "$IDLE_TISSUE_STORE" init >/dev/null 2>&1 || true
fi

# Auto-initialize jwz store if not already present
if command -v jwz &>/dev/null && [[ ! -d "$IDLE_JWZ_STORE" ]]; then
    jwz --store "$IDLE_JWZ_STORE" init >/dev/null 2>&1 || true
fi

# Set environment variables for this process AND session persistence
# Only set if user hasn't already set their own (respects user overrides)
if [[ -z "${TISSUE_STORE:-}" && -d "$IDLE_TISSUE_STORE" ]]; then
    export TISSUE_STORE="$IDLE_TISSUE_STORE"
fi
if [[ -z "${JWZ_STORE:-}" && -d "$IDLE_JWZ_STORE" ]]; then
    export JWZ_STORE="$IDLE_JWZ_STORE"
fi

# Persist to CLAUDE_ENV_FILE only if we're using the default idle stores
# (Don't overwrite user's custom store paths)
if [[ -n "${CLAUDE_ENV_FILE:-}" ]]; then
    # Only persist if we actually set it to the default (not user override)
    if [[ "${TISSUE_STORE:-}" == "$IDLE_TISSUE_STORE" ]] && ! grep -q "TISSUE_STORE=" "$CLAUDE_ENV_FILE" 2>/dev/null; then
        echo "export TISSUE_STORE=\"$IDLE_TISSUE_STORE\"" >> "$CLAUDE_ENV_FILE"
    fi
    if [[ "${JWZ_STORE:-}" == "$IDLE_JWZ_STORE" ]] && ! grep -q "JWZ_STORE=" "$CLAUDE_ENV_FILE" 2>/dev/null; then
        echo "export JWZ_STORE=\"$IDLE_JWZ_STORE\"" >> "$CLAUDE_ENV_FILE"
    fi
fi

# Health check results
HEALTH_ISSUES=""

# Check tool availability and health
CODEX_AVAILABLE="false"
CODEX_STATUS="not installed"
GEMINI_AVAILABLE="false"
GEMINI_STATUS="not installed"
TISSUE_AVAILABLE="false"
TISSUE_STATUS="not installed"
JWZ_AVAILABLE="false"
JWZ_STATUS="not installed"

# Codex check
if command -v codex &>/dev/null; then
    CODEX_AVAILABLE="true"
    CODEX_STATUS="ok"
fi

# Gemini check
if command -v gemini &>/dev/null; then
    GEMINI_AVAILABLE="true"
    GEMINI_STATUS="ok"
fi

# Tissue check - verify both command and store
# Temporarily disable ERR trap for health checks (we expect some to fail)
trap - ERR
if command -v tissue &>/dev/null; then
    TISSUE_OUTPUT=$(tissue list 2>&1)
    TISSUE_EXIT=$?
    if [[ $TISSUE_EXIT -eq 0 ]]; then
        TISSUE_AVAILABLE="true"
        TISSUE_STATUS="ok"
    elif echo "$TISSUE_OUTPUT" | grep -q "No tissue store found"; then
        TISSUE_STATUS="no store (run 'tissue init')"
        HEALTH_ISSUES="${HEALTH_ISSUES}tissue: No store found in $CWD or ancestors. Run 'tissue init' to create one."$'\n'
    else
        # Generic failure - include first line of error
        TISSUE_ERROR=$(echo "$TISSUE_OUTPUT" | head -1)
        TISSUE_STATUS="error"
        HEALTH_ISSUES="${HEALTH_ISSUES}tissue: $TISSUE_ERROR"$'\n'
    fi
else
    HEALTH_ISSUES="${HEALTH_ISSUES}tissue: Command not found. Install from github.com/evil-mind-evil-sword/tissue"$'\n'
fi

# Jwz check - verify both command and store
if command -v jwz &>/dev/null; then
    JWZ_OUTPUT=$(jwz topic list 2>&1)
    JWZ_EXIT=$?
    if [[ $JWZ_EXIT -eq 0 ]]; then
        JWZ_AVAILABLE="true"
        JWZ_STATUS="ok"
    elif echo "$JWZ_OUTPUT" | grep -qi "no.*store\|store.*not found"; then
        JWZ_STATUS="no store (run 'jwz init')"
        HEALTH_ISSUES="${HEALTH_ISSUES}jwz: No store found in $CWD or ancestors. Run 'jwz init' to create one."$'\n'
    else
        # Generic failure - include first line of error
        JWZ_ERROR=$(echo "$JWZ_OUTPUT" | head -1)
        JWZ_STATUS="error"
        HEALTH_ISSUES="${HEALTH_ISSUES}jwz: $JWZ_ERROR"$'\n'
    fi
else
    HEALTH_ISSUES="${HEALTH_ISSUES}jwz: Command not found. Install from github.com/evil-mind-evil-sword/zawinski"$'\n'
fi
# Re-enable ERR trap
trap 'echo "{\"hookSpecificOutput\": {\"hookEventName\": \"SessionStart\", \"additionalContext\": \"idle: hook error\"}}"; exit 0' ERR

# Build available skills list
SKILLS=""
PLUGIN_ROOT="${CLAUDE_PLUGIN_ROOT:-}"
if [[ -n "$PLUGIN_ROOT" ]]; then
    for skill_file in "$PLUGIN_ROOT"/skills/*/SKILL.md; do
        if [[ -f "$skill_file" ]]; then
            skill_name=$(basename "$(dirname "$skill_file")")
            if [[ -n "$SKILLS" ]]; then
                SKILLS="$SKILLS, $skill_name"
            else
                SKILLS="$skill_name"
            fi
        fi
    done
fi

# Build context message for agent
CONTEXT="## idle Plugin Active

You are running with the **idle** plugin.

### Tool Health

| Tool | Status | Purpose |
|------|--------|---------|
| tissue | $TISSUE_STATUS | Issue tracking (\`tissue list\`, \`tissue new\`) |
| jwz | $JWZ_STATUS | Agent messaging (\`jwz read\`, \`jwz post\`) |
| codex | $CODEX_STATUS | External model queries |
| gemini | $GEMINI_STATUS | External model queries |

### Available Skills

$([ -n "$SKILLS" ] && echo "$SKILLS" || echo "None detected")

### Session

Session ID: \`$SESSION_ID\`
"

# Emit session_start trace event
if [[ "$JWZ_AVAILABLE" = "true" ]]; then
    TRACE_TOPIC="trace:$SESSION_ID"
    TIMESTAMP=$(date -u +"%Y-%m-%dT%H:%M:%SZ")

    jwz topic new "$TRACE_TOPIC" >/dev/null 2>&1 || true

    TRACE_EVENT=$(jq -n \
        --arg event_type "session_start" \
        --arg ts "$TIMESTAMP" \
        '{event_type: $event_type, timestamp: $ts}')

    jwz post "$TRACE_TOPIC" -m "$TRACE_EVENT" >/dev/null 2>&1 || true
fi

# Output JSON with context and optional systemMessage for health issues
if [[ -n "$HEALTH_ISSUES" ]]; then
    # Format health issues for display (use printf for actual newlines)
    SYSTEM_MSG=$(printf "idle health check failed:\n%s" "$HEALTH_ISSUES")
    jq -n \
        --arg context "$CONTEXT" \
        --arg msg "$SYSTEM_MSG" \
        '{hookSpecificOutput: {hookEventName: "SessionStart", additionalContext: $context}, systemMessage: $msg}'
else
    jq -n \
        --arg context "$CONTEXT" \
        '{hookSpecificOutput: {hookEventName: "SessionStart", additionalContext: $context}}'
fi

exit 0
