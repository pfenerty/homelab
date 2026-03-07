# modules/packages.nix — System-wide packages available to all users.
#
# These are tools you want available everywhere on the system.
# For project-specific tools, use Flox environments instead:
#   flox init && flox install python3 nodejs ...
{ pkgs, ... }:
{
  environment.systemPackages = with pkgs; [
    # Version control
    git

    # Dotfile management — pull your existing chezmoi repo after install:
    #   chezmoi init <your-github-username>
    chezmoi

    # Editors (fallback for terminal use)
    vim

    # HTTP tools
    curl
    wget

    # System monitoring
    htop
    btop

    # Terminal multiplexer — useful for persistent sessions over SSH
    tmux

    # Archive tools
    unzip
    zip

    # Search and file tools
    ripgrep   # rg — fast grep alternative
    fd        # fd — fast find alternative
    jq        # JSON processor
    tree      # directory tree viewer

    # Better nix build output
    nix-output-monitor  # use `nom` instead of `nix` for builds
  ];

  # Note: Flox is installed by the flox NixOS module imported in flake.nix,
  # not as a package here. Run `flox --version` to verify after install.
}
