# flake.nix — The entry point for this NixOS configuration.
#
# A flake has two main sections:
#   - inputs:  External dependencies (other flakes, nixpkgs, etc.)
#   - outputs: What this flake produces (in our case, a NixOS system configuration)
#
# To learn more about flakes: https://nixos.wiki/wiki/Flakes
{
  description = "NixOS server configuration";

  # --- Inputs ---
  # These are the external dependencies our configuration needs.
  # Nix will fetch and lock these to specific revisions in flake.lock.
  inputs = {
    # nixpkgs is the main Nix package repository. We pin to the stable release.
    # You can switch to "nixos-unstable" for bleeding-edge packages.
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-25.05";

    # Flox — developer environment manager built on Nix.
    # This provides a NixOS module that installs and configures Flox system-wide.
    flox.url = "github:flox/flox";
  };

  # Tell Nix to trust the Flox binary cache so it can download pre-built packages
  # instead of compiling everything from source.
  nixConfig = {
    extra-substituters = [
      "https://cache.flox.dev"
    ];
    extra-trusted-public-keys = [
      "flox-cache-public-1:7F4OyH7ZCnFhcze3fJdfyXYLQw/aV7GEed86nQ7IsOs="
    ];
  };

  # --- Outputs ---
  # This function receives all resolved inputs and produces our NixOS configuration.
  # `self` refers to this flake itself.
  outputs = { self, nixpkgs, flox, ... }: {

    # Define a NixOS system called "server".
    # Build it with: sudo nixos-rebuild switch --flake .#server
    nixosConfigurations.server = nixpkgs.lib.nixosSystem {
      system = "x86_64-linux";

      # specialArgs passes extra arguments to all imported modules.
      # This lets modules access flake inputs if needed.
      specialArgs = { inherit self flox; };

      modules = [
        # Our host-specific configuration (imports all other modules)
        ./hosts/server/default.nix

        # Flox NixOS module — installs and configures Flox system-wide
        flox.nixosModules.flox
      ];
    };
  };
}
