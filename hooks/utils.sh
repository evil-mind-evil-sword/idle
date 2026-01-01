#!/bin/bash
# idle hooks shared utilities
# Source this file in hooks: source "${BASH_SOURCE%/*}/utils.sh"

# Get project name from git remote or directory basename
get_project_name() {
    local cwd="${1:-.}"
    local name=""

    # Try git remote first
    if command -v git &>/dev/null; then
        name=$(git -C "$cwd" remote get-url origin 2>/dev/null | sed -E 's/.*[:/]([^/]+)\/([^/.]+)(\.git)?$/\2/' || true)
    fi

    # Fall back to directory basename
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
    # git@github.com:user/repo.git -> https://github.com/user/repo
    if [[ "$remote_url" == git@* ]]; then
        remote_url=$(echo "$remote_url" | sed -E 's/git@([^:]+):/https:\/\/\1\//' | sed 's/\.git$//')
    fi

    # Clean up .git suffix from HTTPS URLs
    remote_url="${remote_url%.git}"

    echo "$remote_url"
}

# Post to ntfy with rich formatting
# Usage: ntfy_post "title" "body" [priority] [tags] [click_url]
# Priority: 1=min, 2=low, 3=default, 4=high, 5=urgent
# Tags: comma-separated emoji names (e.g., "rocket,white_check_mark")
# Click URL: URL to open when notification is tapped
ntfy_post() {
    local title="$1"
    local body="$2"
    local priority="${3:-3}"
    local tags="${4:-}"
    local click_url="${5:-}"

    # Skip if no topic configured
    local topic="${IDLE_NTFY_TOPIC:-}"
    if [[ -z "$topic" ]]; then
        return 0
    fi

    # Build ntfy URL (support custom server via IDLE_NTFY_SERVER)
    local server="${IDLE_NTFY_SERVER:-https://ntfy.sh}"
    local url="$server/$topic"

    # Build curl args
    local -a args=(
        -s
        -X POST
        -H "Title: $title"
        -H "Priority: $priority"
    )

    if [[ -n "$tags" ]]; then
        args+=(-H "Tags: $tags")
    fi

    if [[ -n "$click_url" ]]; then
        args+=(-H "Click: $click_url")
    fi

    args+=(-d "$body" "$url")

    # Post in background to not block hook
    curl "${args[@]}" &>/dev/null &
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
