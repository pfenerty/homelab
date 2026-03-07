# modules/zed-remote.nix — Compatibility for Zed's remote development server.
#
# The problem: NixOS doesn't have a traditional /lib/ld-linux.so dynamic linker.
# When Zed connects over SSH, it uploads a pre-built server binary that expects
# standard Linux dynamic linking — which fails on NixOS by default.
#
# The solution: nix-ld provides a compatibility shim that lets dynamically-linked
# Linux binaries "just work" on NixOS. This is the simplest approach and avoids
# needing to match Zed client/server versions manually.
#
# Learn more: https://github.com/Mic92/nix-ld
{ ... }:
{
  programs.nix-ld.enable = true;

  # nix-ld needs to know which shared libraries to make available.
  # The default set covers most common cases. If Zed or other tools
  # fail with "library not found" errors, add the missing library here.
  # programs.nix-ld.libraries = with pkgs; [
  #   stdenv.cc.cc.lib
  #   zlib
  #   openssl
  # ];
}
