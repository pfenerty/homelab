# hosts/server/hardware-configuration.nix — Machine-specific hardware settings.
#
# !! IMPORTANT !!
# This is a PLACEHOLDER file. Replace it with the real one generated during
# NixOS installation by running:
#
#   nixos-generate-config --root /mnt
#
# Then copy /mnt/etc/nixos/hardware-configuration.nix to this location.
# The generated file contains your disk UUIDs, filesystem mounts, kernel
# modules, and CPU-specific settings that are unique to your hardware.
#
# This stub exists so the flake can be evaluated before installation.
{ config, lib, pkgs, modulesPath, ... }:
{
  imports = [
    (modulesPath + "/installer/scan/not-detected.nix")
  ];

  # These will be filled in by nixos-generate-config:
  boot.initrd.availableKernelModules = [ "xhci_pci" "ahci" "nvme" "usbhid" "usb_storage" "sd_mod" ];
  boot.kernelModules = [ "kvm-intel" ];

  # Intel CPU microcode updates
  hardware.cpu.intel.updateMicrocode = lib.mkDefault config.hardware.enableRedistributableFirmware;

  # Filesystem mounts — replace these with your actual partitions!
  # After running nixos-generate-config, this section will have your real UUIDs.
  fileSystems."/" = {
    device = "/dev/disk/by-label/nixos";
    fsType = "ext4";
  };

  fileSystems."/boot" = {
    device = "/dev/disk/by-label/boot";
    fsType = "vfat";
    options = [ "fmask=0077" "dmask=0077" ];
  };

  swapDevices = [ ];
}
