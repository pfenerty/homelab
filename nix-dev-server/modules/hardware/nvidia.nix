# modules/hardware/nvidia.nix — NVIDIA GPU driver configuration.
#
# Even on a headless server (no desktop environment), NixOS loads NVIDIA
# drivers through the X server video driver mechanism. This is just how
# the NixOS module system works — it doesn't mean X11 is running.
{ config, pkgs, ... }:
{
  # Tell NixOS to use the NVIDIA driver (required even without a display server).
  services.xserver.videoDrivers = [ "nvidia" ];

  # Enable OpenGL/Vulkan support (needed for GPU compute, CUDA, etc.).
  # This was renamed from hardware.opengl in recent NixOS versions.
  hardware.graphics.enable = true;

  hardware.nvidia = {
    # Kernel modesetting is required for most modern setups.
    modesetting.enable = true;

    # Use NVIDIA's open-source kernel modules.
    # Recommended for Turing (RTX 20-series) and newer GPUs.
    # Set to false if you have an older GPU (pre-Turing).
    open = true;

    # Disable the NVIDIA settings GUI — not needed on a headless server.
    nvidiaSettings = false;

    # Pin to the stable driver branch. Other options:
    #   nvidiaPackages.beta       — latest beta drivers
    #   nvidiaPackages.production — older, more conservative
    package = config.boot.kernelPackages.nvidiaPackages.stable;
  };
}
