# modules/security.nix — Basic server hardening.
{ ... }:
{
  # fail2ban monitors log files for repeated failed login attempts
  # and temporarily bans offending IP addresses via the firewall.
  services.fail2ban = {
    enable = true;
    maxretry = 5;          # Ban after 5 failed attempts
    bantime = "1h";        # Ban duration
    bantime-increment = {
      enable = true;       # Each subsequent ban gets longer
    };
  };

  # Require password for sudo (wheel group members can use sudo).
  security.sudo.wheelNeedsPassword = true;
}
