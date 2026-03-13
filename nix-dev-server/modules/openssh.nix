# modules/openssh.nix — SSH daemon configuration for remote access.
#
# Zed's remote development connects over SSH using a control master for
# multiplexing. No special server-side config is needed beyond a working
# sshd and your SSH public key in authorized_keys (set in users.nix).
{ ... }:
{
  services.openssh = {
    enable = true;

    settings = {
      # Disable root login — use your regular user + sudo instead.
      PermitRootLogin = "no";

      # Disable password authentication — SSH keys only.
      # This is much more secure against brute-force attacks.
      # Make sure your public key is set in users.nix before disabling this!
      PasswordAuthentication = false;

      # Disable keyboard-interactive auth (another password-based method).
      KbdInteractiveAuthentication = false;

      # No X11 forwarding needed on a headless server.
      X11Forwarding = false;
    };
  };
}
