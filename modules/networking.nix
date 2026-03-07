# modules/networking.nix — Hostname, firewall, and network settings.
{ ... }:
{
  # Set your machine's hostname. Change this to whatever you like.
  networking.hostName = "nix-server";

  # Use NetworkManager for network configuration.
  # It's simpler than systemd-networkd and works well for single-machine setups.
  networking.networkmanager.enable = true;

  # NixOS firewall is enabled by default with a deny-all policy.
  # Only ports listed here will accept incoming connections.
  networking.firewall = {
    enable = true;
    allowedTCPPorts = [
      22  # SSH (required for Zed remote access)
    ];
    # Add more ports as needed, e.g.:
    # allowedTCPPorts = [ 22 80 443 8080 ];
  };
}
