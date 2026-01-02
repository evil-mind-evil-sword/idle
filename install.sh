#!/bin/sh
set -e

# idle installer
# Usage: curl -fsSL https://github.com/evil-mind-evil-sword/idle/releases/latest/download/install.sh | sh

echo "Installing idle plugin..."
echo ""

# --- Install dependencies ---

echo "Checking dependencies..."

# Check for jq
if ! command -v jq >/dev/null 2>&1; then
    echo "Installing jq..."
    if command -v brew >/dev/null 2>&1; then
        brew install jq
    elif command -v apt-get >/dev/null 2>&1; then
        sudo apt-get update && sudo apt-get install -y jq
    else
        echo "Error: jq not found. Please install jq manually."
        exit 1
    fi
fi

# Install jwz (zawinski)
if ! command -v jwz >/dev/null 2>&1; then
    echo "Installing jwz (zawinski)..."
    curl -fsSL https://github.com/femtomc/zawinski/releases/latest/download/install.sh | sh
fi

# Install tissue
if ! command -v tissue >/dev/null 2>&1; then
    echo "Installing tissue..."
    curl -fsSL https://github.com/femtomc/tissue/releases/latest/download/install.sh | sh
fi

echo "Dependencies installed."
echo ""

# --- Install plugin via Claude Code ---

if command -v claude >/dev/null 2>&1; then
    echo "Installing idle plugin via Claude Code..."

    # Add marketplace (idempotent)
    claude plugin marketplace add evil-mind-evil-sword/marketplace 2>/dev/null || true

    # Update emes marketplace to get latest versions
    echo "Updating marketplace..."
    claude plugin marketplace update emes 2>/dev/null || true

    # Check if already installed
    if claude plugin list 2>/dev/null | grep -q "idle@emes"; then
        echo "Updating idle plugin..."
        if claude plugin update idle@emes 2>/dev/null; then
            echo "idle plugin updated!"
        else
            # Fallback: reinstall
            claude plugin uninstall idle@emes 2>/dev/null || true
            if claude plugin install idle@emes 2>/dev/null; then
                echo "idle plugin reinstalled!"
            else
                echo "Plugin update failed. Try manually: /plugin update idle@emes"
            fi
        fi
    else
        echo "Installing idle plugin..."
        if claude plugin install idle@emes 2>/dev/null; then
            echo "idle plugin installed!"
        else
            echo "Plugin install failed. Try manually in Claude Code:"
            echo "  /plugin marketplace add evil-mind-evil-sword/marketplace"
            echo "  /plugin install idle@emes"
        fi
    fi
else
    echo "claude CLI not found. Install the plugin manually in Claude Code:"
    echo "  /plugin marketplace add evil-mind-evil-sword/marketplace"
    echo "  /plugin install idle@emes"
fi

echo ""
echo "Installation complete!"
echo ""
echo "The idle plugin is now active. Use #idle to enable review."
echo ""
echo "Dependencies installed:"
echo "  jwz     - Agent messaging"
echo "  tissue  - Issue tracking"
