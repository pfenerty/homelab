#!/bin/bash
# .claude/hooks/session-start.sh
# Runs at the start of every Claude Code session.
# Only does meaningful work in remote (Claude Code on the web) environments.
set -euo pipefail

if [ "${CLAUDE_CODE_REMOTE:-}" != "true" ]; then
  exit 0
fi

# Verify nix is available and show flake info
if command -v nix &>/dev/null; then
  echo "Nix $(nix --version) available."
  nix flake metadata --no-update-lock-file 2>/dev/null || true
else
  echo "Warning: nix not found in PATH. Install Nix to build this configuration."
fi
