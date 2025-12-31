#!/bin/bash
# Smoke test for idle loop workflow
# Run this manually in a test repository with tissue set up

set -e

echo "=== Idle Loop Smoke Test ==="
echo ""
echo "Prerequisites:"
echo "  - tissue installed and configured"
echo "  - jwz (zawinski) installed"
echo "  - In a git repository"
echo ""

# Check prerequisites
check_prereq() {
    if ! command -v "$1" >/dev/null 2>&1; then
        echo "✗ Missing: $1"
        return 1
    else
        echo "✓ Found: $1"
        return 0
    fi
}

echo "--- Checking Prerequisites ---"
check_prereq git || exit 1
check_prereq tissue || exit 1
check_prereq jwz || exit 1
check_prereq jq || exit 1

if ! git rev-parse --git-dir >/dev/null 2>&1; then
    echo "✗ Not in a git repository"
    exit 1
fi
echo "✓ In git repository: $(git rev-parse --show-toplevel)"

echo ""
echo "--- Test Steps (run manually in Claude) ---"
echo ""
echo "1. Create a test issue:"
echo "   tissue new 'smoke-test-issue' -m 'Test issue for loop smoke test'"
echo ""
echo "2. Start working the issue (issue mode):"
echo "   /loop"
echo "   # Should pick up the issue, create worktree"
echo ""
echo "3. Make a change in the worktree:"
echo "   echo 'test' > test-file.txt"
echo "   git add test-file.txt"
echo "   git commit -m 'Test commit'"
echo ""
echo "4. Signal completion:"
echo "   <loop-done>COMPLETE</loop-done>"
echo ""
echo "5. Alice review is triggered automatically."
echo "   # If approved, changes auto-land to main"
echo ""
echo "6. Verify:"
echo "   git log --oneline -3"
echo "   # Should show the 'Test commit' on main"
echo "   tissue list"
echo "   # Issue should be closed"
echo ""
echo "7. Cleanup (if needed):"
echo "   git reset --hard HEAD~1  # Remove test commit"
echo ""
echo "--- Task Mode Test ---"
echo ""
echo "1. Run a task loop:"
echo "   /loop Add a comment to README.md"
echo ""
echo "2. Make the change and signal completion:"
echo "   <loop-done>COMPLETE</loop-done>"
echo ""
echo "3. Alice reviews. If approved, loop exits."
echo ""
echo "--- Escape Hatches ---"
echo ""
echo "A. Cancel active loop:"
echo "   /cancel"
echo ""
echo "B. File-based bypass:"
echo "   touch .idle-disabled"
echo "   # Hooks bypassed"
echo "   rm .idle-disabled"
echo ""
echo "C. Full reset:"
echo "   rm -rf .jwz/"
echo "   # All loop state cleared"
echo ""
