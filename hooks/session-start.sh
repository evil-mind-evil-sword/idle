#!/bin/bash
# Session start hook wrapper
# Routes to idle binary for session context injection
exec "${CLAUDE_PLUGIN_ROOT}/bin/idle" session-start
