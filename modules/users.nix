# modules/users.nix — User accounts.
#
# After first boot, change your password with: passwd
{ pkgs, ... }:
{
  # ========================================
  # TODO: Change "patrick" to your username
  # ========================================
  users.users.patrick = {
    isNormalUser = true;

    # Groups:
    #   wheel          — allows sudo
    #   networkmanager — allows managing network connections
    extraGroups = [ "wheel" "networkmanager" ];

    # Default shell
    shell = pkgs.bash;

    # Temporary password for first login. Change it immediately with `passwd`.
    # Remove this line after setting a real password.
    initialPassword = "changeme";

    # ========================================
    # TODO: Replace with your SSH public key
    # ========================================
    # Get it from your MacBook with: cat ~/.ssh/id_ed25519.pub
    # If you don't have one yet: ssh-keygen -t ed25519
    openssh.authorizedKeys.keys = [
      # "ssh-ed25519 AAAA... your-email@example.com"
    ];
  };
}
