# modules/claude-code.nix — Claude Code AI development environment.
#
# Installs Node.js (required by the Claude Code CLI) and supporting tools.
#
# After rebuilding, install the Claude Code CLI for your user:
#   npm install -g @anthropic-ai/claude-code
#
# Then authenticate:
#   claude
{ pkgs, ... }:
{
  environment.systemPackages = with pkgs; [
    # Node.js runtime — required by the Claude Code CLI
    nodejs_22

    # Native build tools needed by some npm packages
    python3
    gnumake
    gcc
  ];

  # Increase inotify watches — Claude Code watches many files for changes
  boot.kernel.sysctl = {
    "fs.inotify.max_user_watches" = 524288;
  };
}
