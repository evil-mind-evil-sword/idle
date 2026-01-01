#!/bin/bash
# idle hooks shared utilities
# Source this file in hooks: source "${BASH_SOURCE%/*}/utils.sh"

# Get project name from git remote or directory basename
get_project_name() {
    local cwd="${1:-.}"
    local name=""

    if command -v git &>/dev/null; then
        name=$(git -C "$cwd" remote get-url origin 2>/dev/null | sed -E 's/.*[:/]([^/]+)\/([^/.]+)(\.git)?$/\2/' || true)
    fi

    if [[ -z "$name" ]]; then
        name=$(basename "$(cd "$cwd" && pwd)")
    fi

    echo "$name"
}

# Get current git branch
get_git_branch() {
    local cwd="${1:-.}"
    git -C "$cwd" branch --show-current 2>/dev/null || echo ""
}

# Get GitHub repo URL from git remote
get_repo_url() {
    local cwd="${1:-.}"
    local remote_url=""

    if command -v git &>/dev/null; then
        remote_url=$(git -C "$cwd" remote get-url origin 2>/dev/null || echo "")
    fi

    if [[ -z "$remote_url" ]]; then
        echo ""
        return
    fi

    # Convert SSH to HTTPS URL
    if [[ "$remote_url" == git@* ]]; then
        remote_url=$(echo "$remote_url" | sed -E 's/git@([^:]+):/https:\/\/\1\//' | sed 's/\.git$//')
    fi

    remote_url="${remote_url%.git}"
    echo "$remote_url"
}

# Post notification to Discord
# Usage: notify "title" "body" [priority] [emoji] [repo_url]
# Priority: 1-2=gray, 3=blue, 4=yellow, 5=red
# Emoji: rocket, speech_balloon, white_check_mark, x, hourglass
notify() {
    local title="$1"
    local body="$2"
    local priority="${3:-3}"
    local emoji="${4:-}"
    local repo_url="${5:-}"

    local webhook="${IDLE_DISCORD_WEBHOOK:-}"
    if [[ -z "$webhook" ]]; then
        return 0
    fi

    # Map priority to color
    local color=5793266  # blue (default)
    case "$priority" in
        5) color=15548997 ;;    # red (urgent)
        4) color=16705372 ;;    # yellow (warning)
        1|2) color=9807270 ;;   # gray (low)
    esac

    # Override color based on emoji
    case "$emoji" in
        white_check_mark) color=5763719 ;;  # green
        x) color=15548997 ;;                 # red
    esac

    # Map emoji tag to actual emoji
    local emoji_char=""
    case "$emoji" in
        rocket) emoji_char="🚀" ;;
        speech_balloon) emoji_char="💬" ;;
        white_check_mark) emoji_char="✅" ;;
        x) emoji_char="❌" ;;
        hourglass) emoji_char="⏳" ;;
    esac

    [[ -n "$emoji_char" ]] && title="$emoji_char $title"

    local timestamp
    timestamp=$(date -u +"%Y-%m-%dT%H:%M:%SZ")

    local payload
    if [[ -n "$repo_url" ]]; then
        payload=$(jq -n \
            --arg title "$title" \
            --arg desc "$body" \
            --argjson color "$color" \
            --arg url "$repo_url" \
            --arg ts "$timestamp" \
            '{embeds: [{title: $title, description: $desc, color: $color, url: $url, timestamp: $ts}]}')
    else
        payload=$(jq -n \
            --arg title "$title" \
            --arg desc "$body" \
            --argjson color "$color" \
            --arg ts "$timestamp" \
            '{embeds: [{title: $title, description: $desc, color: $color, timestamp: $ts}]}')
    fi

    curl -s -X POST -H "Content-Type: application/json" -d "$payload" "$webhook" &>/dev/null &
}

# Format tool availability as checkmarks
format_tool_status() {
    local tool="$1"
    if command -v "$tool" &>/dev/null; then
        echo "✓"
    else
        echo "✗"
    fi
}
