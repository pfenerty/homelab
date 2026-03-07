# modules/nix-settings.nix — Nix daemon settings, flakes, and binary caches.
#
# This module configures the Nix package manager itself (not the OS).
# It enables flakes, sets up binary caches for faster builds, and
# configures automatic garbage collection to save disk space.
{ pkgs, ... }:
{
  # Enable flakes and the new `nix` CLI (e.g., `nix build`, `nix develop`).
  # These are still marked "experimental" but are widely used and stable in practice.
  nix.settings.experimental-features = [ "nix-command" "flakes" ];

  # Allow members of the "wheel" group to use binary caches and other
  # privileged Nix operations without being root.
  nix.settings.trusted-users = [ "root" "@wheel" ];

  # Binary caches (substituters) let Nix download pre-built packages instead
  # of compiling from source. The default cache is cache.nixos.org.
  # We add the Flox cache here so flox packages are also pre-built.
  nix.settings.substituters = [
    "https://cache.nixos.org/"
    "https://cache.flox.dev"
  ];
  nix.settings.trusted-public-keys = [
    "cache.nixos.org-1:6NCHdD59X431o0gWypbMrAURkbJ16ZPMQFGspcDShjY="
    "flox-cache-public-1:7F4OyH7ZCnFhcze3fJdfyXYLQw/aV7GEed86nQ7IsOs="
  ];

  # Automatically clean up old Nix store paths to free disk space.
  # Runs weekly and deletes anything older than 30 days.
  nix.gc = {
    automatic = true;
    dates = "weekly";
    options = "--delete-older-than 30d";
  };

  # Allow installation of packages with unfree licenses (e.g., NVIDIA drivers).
  nixpkgs.config.allowUnfree = true;
}
