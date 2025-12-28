#!/bin/bash
# idle SessionStart hook - minimal agent awareness injection
# Provides workflow guidance without excessive context overhead

# Output agent awareness (2-4 lines only)
cat <<'EOF'
idle agents: idle:reviewer (validate changes), idle:oracle (hard decisions), idle:explorer (codebase search)
Workflow: After code changes -> run /review; When stuck on design -> consult idle:oracle
EOF
