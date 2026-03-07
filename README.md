# NixOS Server Configuration

Flake-based NixOS configuration for a home server used as a remote development environment.

## What's Configured

- **NVIDIA GPU drivers** (Intel CPU + NVIDIA GPU)
- **SSH** with key-only authentication (for Zed remote development)
- **Flox** developer environment manager
- **chezmoi** for dotfile management
- **fail2ban** + firewall for basic security
- **nix-ld** for Zed remote server binary compatibility
- Essential dev tools (git, ripgrep, fd, jq, tmux, etc.)

## Installation

### Prerequisites

- NixOS ISO on a USB drive ([download](https://nixos.org/download/))
- Your SSH public key from your MacBook (`cat ~/.ssh/id_ed25519.pub`)

### Steps

1. **Boot from the NixOS ISO** and connect to the network.

2. **Partition and format your disk.** Example for a single NVMe drive:

   ```bash
   # Partition (adjust /dev/nvme0n1 to your disk)
   parted /dev/nvme0n1 -- mklabel gpt
   parted /dev/nvme0n1 -- mkpart root ext4 512MB 100%
   parted /dev/nvme0n1 -- mkpart ESP fat32 1MB 512MB
   parted /dev/nvme0n1 -- set 2 esp on

   # Format
   mkfs.ext4 -L nixos /dev/nvme0n1p1
   mkfs.fat -F 32 -n boot /dev/nvme0n1p2

   # Mount
   mount /dev/disk/by-label/nixos /mnt
   mkdir -p /mnt/boot
   mount /dev/disk/by-label/boot /mnt/boot
   ```

3. **Generate hardware configuration:**

   ```bash
   nixos-generate-config --root /mnt
   ```

4. **Clone this repo and copy in the hardware config:**

   ```bash
   nix-shell -p git
   git clone <this-repo-url> /mnt/etc/nixos
   cp /mnt/etc/nixos/hosts/server/hardware-configuration.nix /mnt/etc/nixos/hosts/server/hardware-configuration.nix.placeholder
   cp /etc/nixos/hardware-configuration.nix /mnt/etc/nixos/hosts/server/hardware-configuration.nix
   ```

5. **Edit the configuration:**

   ```bash
   # Set your username and SSH public key
   vim /mnt/etc/nixos/modules/users.nix

   # Set your hostname
   vim /mnt/etc/nixos/modules/networking.nix

   # Set your timezone
   vim /mnt/etc/nixos/hosts/server/default.nix
   ```

6. **Install:**

   ```bash
   nixos-install --flake /mnt/etc/nixos#server
   ```

7. **Reboot**, log in, and set up your environment:

   ```bash
   # Change password
   passwd

   # Pull your dotfiles
   chezmoi init <your-github-username>
   chezmoi apply

   # Verify flox
   flox --version
   ```

8. **Connect from your MacBook** with Zed:
   - Open Zed
   - Use `zed ssh://your-user@your-server-ip/path/to/project`

## Day-to-Day Usage

### Rebuild after config changes

```bash
cd /etc/nixos   # or wherever you cloned this repo
sudo nixos-rebuild switch --flake .#server
```

### Add a system package

Edit `modules/packages.nix`, add the package name, then rebuild.

### Open a firewall port

Edit `modules/networking.nix`, add the port to `allowedTCPPorts`, then rebuild.

### Update all packages

```bash
nix flake update    # updates flake.lock to latest versions
sudo nixos-rebuild switch --flake .#server
```

### Use Flox for project environments

```bash
cd ~/my-project
flox init
flox install nodejs python3  # project-specific tools
flox activate                # enter the environment
```

## Repository Structure

```
flake.nix                              # Entry point
hosts/server/
  default.nix                          # Host config (imports all modules)
  hardware-configuration.nix           # Machine-specific (generated)
modules/
  hardware/nvidia.nix                  # NVIDIA drivers
  networking.nix                       # Hostname, firewall
  nix-settings.nix                     # Flakes, caches, GC
  openssh.nix                          # SSH daemon
  packages.nix                         # System-wide packages
  security.nix                         # fail2ban, sudo
  users.nix                            # User accounts + SSH keys
  zed-remote.nix                       # nix-ld for Zed compatibility
```
