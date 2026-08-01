# Getting etcd off the SD Cards (homelab-bwl)

## Summary

The three RPi4 control-plane nodes each have exactly one disk — a 32 GB SD card
(`mmcblk0`, `mmc` transport). etcd's write-ahead log lives on it, and the SD card cannot
sustain etcd's fsync pattern:

```
wal/wal.go:845      "slow fdatasync"  took=1.317s  expected-duration=1s
etcdserver/raft.go  "leader failed to send out heartbeat on time; took too long,
                     leader is overloaded likely from slow disk"
txn/util.go:93      "apply request took too long" took=4.996s
                     ... /registry/leases/kube-system/kube-scheduler
                     error: "context deadline exceeded"
```

This crash-looped kube-controller-manager and kube-scheduler ~1100 times each over 20 days
(`homelab-8md`). The mitigations applied there — pruning, defrag, apiserver `GOMEMLIMIT`,
and a 45s leader-election renew deadline — stopped the crash loops but did not change fsync
latency. etcd still logs 1.3–3.3s applies under CI load, and ~5% of Lease reads still exceed
2s. Any workload that keeps the Kubernetes default 5s client timeout (e.g. `ocidex-operator`)
will keep tripping until this is fixed.

**There are two ways to fix it.** They differ a lot in risk and effort.

| | A: EPHEMERAL on SSD | B: Full USB boot |
|---|---|---|
| SD card still used | Yes — boot + STATE only (read-mostly) | No, removed entirely |
| etcd fsync goes to | SSD | SSD |
| Talos reinstall | No | Yes, per node |
| EEPROM change | No | Yes, per Pi |
| Officially documented | Yes (`VolumeConfig`) | No — community practice |
| Rollback | Remove the config document, wipe, reboot | Reflash the SD card |

**Option A is recommended.** It solves the actual problem — etcd's WAL fsync — using a
supported Talos config document, without reflashing or touching the bootloader. The SD card
is left holding only `/boot` and `STATE`, which are read-mostly, so SD wear effectively stops
too. Option B is documented below because it is what "replace the SD cards" literally means,
and it is the right choice if you also want the SD cards physically gone.

---

## Hardware

Per node, ×3. The etcd working set is ~46 MB and the whole EPHEMERAL partition is 30 GB, so
**capacity is irrelevant here — latency is everything.** Buy the cheapest *good* drive, not the
biggest.

### 1. SSD — 3 × 120–250 GB SATA

What matters for etcd is sync-write (fsync) latency, not sequential throughput. That rules out
the cheapest DRAM-less QLC drives, which have good benchmark numbers and poor sustained
sync-write behaviour.

- **Good:** Samsung 870 EVO, Crucial MX500, WD Blue 3D — TLC with a DRAM cache.
- **Avoid:** Kingston A400 and similar DRAM-less budget drives. They will work, but sync-write
  latency is exactly the axis they cut cost on, which is the one thing you are buying.

250 GB is typically the price floor for the good drives; there is no benefit to going larger.

### 2. USB 3.0–to–SATA adapter — ×3

**This is the part that goes wrong, not the SSD.** The RPi4 enables UAS (USB Attached SCSI) by
default, and bridge chips with incomplete UAS firmware will hang or silently discard writes
under load — which is filesystem corruption on your etcd volume.

- **Known-good bridges:** ASMedia ASM1153E, ASM1053E, ASM235CM.
- **Known-troublesome:** several JMicron JMS567/JMS578 revisions, ASM1051E.

Concretely: a StarTech USB312SAT3, a Sabrent EC-SSHD, or any enclosure that explicitly states
an ASM1153E/ASM235CM. If you prefer an all-in-one, the Argon ONE M.2 case integrates an
ASM1153E and tidies the cabling, at roughly double the cost.

Two caveats I cannot verify for you: bridge chips are silently revised within the same product
SKU, so a model that was fine last year may not be today; and I have no visibility into current
pricing or availability. Check the chip with `lsusb -t` on any Linux box before committing to
three of them.

### 3. Power — 3 × official Raspberry Pi 15W USB-C PSU (5.1 V / 3 A)

Under-powering is the single most common cause of USB SSD instability on the RPi4. The Pi's USB
ports feed from the same 5 V rail as the SoC. If the Pis are currently on generic phone chargers,
replace them — a marginal PSU that was fine with an SD card will not be fine with an SSD
drawing 2–3 W. Do not use a bus-powered USB hub to share one supply across drives.

### 4. Optional

- A spare SD card, for the EEPROM update step (Option B only).
- A USB-SATA adapter for your workstation, if you want to pre-test the drives.

---

## Option A — Move EPHEMERAL to the SSD (recommended)

`/var/lib/etcd` lives on the `EPHEMERAL` volume, currently `/dev/mmcblk0p6` (30 GB). Talos can
provision `EPHEMERAL` on a different disk via a `VolumeConfig` document with a CEL
`diskSelector`.

**The one catch:** a `VolumeConfig` is only honoured when the volume is provisioned. It has no
effect on an already-provisioned `EPHEMERAL`, so each node's EPHEMERAL must be wiped once for
the new selector to take. That destroys that node's etcd data — which is fine, because the
member leaves the cluster cleanly and re-replicates from the other two. **One node at a time,
verifying quorum between each.**

### A0. Pin the install disk first (do this before attaching any SSD)

The generated config currently carries the `talosctl gen config` default:

```yaml
machine:
  install:
    disk: /dev/sda        # does not exist on the RPi4s today
```

Once you plug in a USB SSD it *will* become `/dev/sda`. With `wipe: false` on already-installed
nodes this is inert, but it is a live trap for any future reinstall. Pin it explicitly in
`talos/patches/controlplane.yaml`:

```yaml
machine:
    install:
        # RPi4s boot from the SD card; the USB SSD carries EPHEMERAL only (homelab-bwl).
        # Without this, install.disk defaults to /dev/sda, which becomes the SSD once attached.
        disk: /dev/mmcblk0
```

Then `make generate && make validate`, and apply with `make repatch-rpi-0N` per node.

### A1. Attach the SSD and confirm how Talos sees it

Plug the SSD into a **blue (USB 3.0)** port. Then:

```bash
cd talos-cluster
T=talos/clusterconfig/talosconfig
talosctl --talosconfig $T -e 192.168.1.101 -n 192.168.1.101 get disks
```

You want a row with `TRANSPORT=usb` and the expected size. Note the exact values — the CEL
match in the next step is written against them. If the drive does not appear, or appears and
then vanishes under load, stop and resolve that first (see *UAS quirks* below).

### A2. Add the VolumeConfig

Talos machine config is multi-document. Append to `talos/patches/controlplane.yaml`:

```yaml
---
apiVersion: v1alpha1
kind: VolumeConfig
name: EPHEMERAL
provisioning:
    # /var/lib/etcd lives here. On the SD card, etcd WAL fdatasync exceeded 1.3s and
    # crash-looped every leader-electing controller in the cluster (homelab-8md).
    # `!system_disk` keeps this off the SD card even if transport naming changes.
    diskSelector:
        match: "!system_disk && disk.transport == 'usb'"
    grow: true
    minSize: 10GiB
```

Regenerate and validate:

```bash
make generate
make validate
```

`make validate` will catch a malformed CEL expression or a bad document — do not skip it.

### A3. Migrate one node, verify, repeat

Start with a **follower**, never the etcd leader. Check who leads:

```bash
talosctl --talosconfig $T -e 192.168.1.101 \
  -n 192.168.1.101,192.168.1.102,192.168.1.103 etcd status
```

For each node in turn (follower, follower, then leader):

```bash
# 1. Apply the config containing the new VolumeConfig
make repatch-rpi-01

# 2. Wipe EPHEMERAL so the new diskSelector is honoured.
#    --graceful (default) cordons/drains the node and leaves etcd cleanly first.
#    --system-labels-to-wipe wipes ONLY that label; STATE, META, BOOT and EFI survive,
#    so the machine config is preserved and the node comes back on its own.
talosctl --talosconfig $T -e 192.168.1.101 -n 192.168.1.101 \
  reset --graceful --system-labels-to-wipe EPHEMERAL --reboot

# 3. Wait for it to come back and rejoin
talosctl --talosconfig $T -e 192.168.1.101 -n 192.168.1.101 get volumestatus | grep EPHEMERAL
#    LOCATION should now be /dev/sda (the SSD), not /dev/mmcblk0p6

kubectl get nodes
talosctl --talosconfig $T -e 192.168.1.102 \
  -n 192.168.1.101,192.168.1.102,192.168.1.103 etcd status
```

**Do not proceed to the next node until all three etcd members report the same RAFT INDEX and
a single agreed LEADER.** Re-replicating 46 MB is quick, but the node is a non-voting liability
until it has caught up. If anything looks wrong, stop — two healthy members still hold quorum,
three broken ones do not.

Repeat for `rpi-02` and `rpi-03`.

---

## Option B — Full USB boot (physically replace the SD cards)

Note up front: **Talos's official RPi documentation covers SD card installation only.** USB boot
on the RPi4 works and is widely used, but you are off the documented path, and a failed boot
means physical access to each Pi. Option A gets the same etcd benefit without this exposure.

### B1. Update each Pi's EEPROM to boot from USB

This needs Raspberry Pi OS on a spare SD card, once per Pi:

1. Write the *Raspberry Pi Bootloader* EEPROM-update image to a spare SD card with Raspberry Pi
   Imager (Misc utility images → Bootloader → USB Boot). Boot the Pi from it; it flashes and
   halts.
2. Or, from a full Raspberry Pi OS install:
   ```bash
   sudo rpi-eeprom-update -a
   sudo -E rpi-eeprom-config --edit
   # set: BOOT_ORDER=0xf14      # 4=USB mass storage, 1=SD, f=retry
   sudo reboot
   ```

`0xf14` is read right-to-left: try USB first, fall back to SD, then retry forever. Keeping SD as
a fallback is deliberate — it is your recovery path.

### B2. Flash Talos to the SSD

Use the **same Image Factory schematic the cluster already runs**, so the overlay and Talos
version match. From `talos-cluster/Makefile`: `TALOS_VERSION := v1.13.4`, `SCHEMATIC :=
ee21ef4a…` (verified: the plain `siderolabs/sbc-raspberrypi` / `rpi_generic` overlay, no
extensions, no customization).

```bash
SCHEMATIC=ee21ef4a5ef808a9b7484cc0dda0f25075021691c8c09a276591eedb638ea1f9
curl -LO "https://factory.talos.dev/image/$SCHEMATIC/v1.13.4/metal-arm64.raw.xz"

# Identify the target carefully — this is destructive and unrecoverable if aimed wrong.
xz -d metal-arm64.raw.xz
sudo dd if=metal-arm64.raw of=/dev/sdX bs=4M status=progress conv=fsync
```

### B3. Bring each node up, one at a time

1. `talosctl --talosconfig $T -n <node> reset --graceful` so it leaves etcd cleanly.
2. Power off, remove the SD card, attach the SSD, power on. It boots into maintenance mode.
3. `make apply-rpi-01 NODE_DHCP_IP=<maintenance IP>` (see the Makefile header for this flow).
4. Wait for it to rejoin, verify `etcd status` shows three members in sync, and only then move on.

Also apply the `install.disk` change from step A0 — with the SD card gone, `/dev/sda` is correct
for these nodes, but pin it rather than relying on the default.

---

## UAS quirks — if the drive misbehaves

Symptoms: the disk disappears under load, resets repeatedly, or throws I/O errors in
`talosctl dmesg`. This is the bridge chip's UAS implementation, not the SSD.

Get the USB vendor:product ID from `talosctl -n <node> dmesg | grep -i usb`, then disable UAS for
that device. On Talos this is a **kernel argument**, which means a new Image Factory schematic —
you cannot set it at runtime:

```yaml
# schematic.yaml
overlay:
  image: siderolabs/sbc-raspberrypi
  name: rpi_generic
customization:
  extraKernelArgs:
    - usb-storage.quirks=174c:55aa:u      # replace with your VID:PID
```

```bash
curl -X POST --data-binary @schematic.yaml https://factory.talos.dev/schematics
```

Update `SCHEMATIC` in the Makefile with the returned ID. Disabling UAS costs throughput but is
still far faster than the SD card — and correctness beats speed for etcd.

---

## Verification

Baselines from `homelab-8md`, measured 2026-08-01 after the software mitigations but before any
storage change:

| Check | Command | Now (SD) | Target (SSD) |
|---|---|---|---|
| WAL fsync | `talosctl -n <node> logs etcd \| grep -c "slow fdatasync"` | recurring | **zero** |
| Slow applies | `talosctl -n <node> logs etcd \| grep "took too long"` | 1.3–3.3s | < 500 ms |
| Lease GET p-max | 40 sequential `kubectl get lease` | 3494 ms, 5% over 2s | no sample over 2s |
| EPHEMERAL location | `talosctl -n <node> get volumestatus \| grep EPHEMERAL` | `/dev/mmcblk0p6` | `/dev/sda` |
| Controller restarts | `kubectl get pods -n kube-system` | 0 (held by 45s deadline) | 0 |

Once WAL fsync warnings are gone, consider reverting the widened leader-election deadlines in
`talos/patches/controlplane.yaml` back toward defaults — they are a workaround for slow storage,
and at 60s/45s/10s a genuinely wedged controller takes a full minute to fail over. The apiserver
`GOMEMLIMIT`/`GOGC` settings should stay; they are appropriate for a 3.7 GB node regardless.

`ocidex-operator-dev` should also stop crash-looping without needing its lease timings widened
(see `ocidex-vh6`).

## Rollback

- **Option A:** delete the `VolumeConfig` document, `make generate`, `make repatch-rpi-0N`, then
  `talosctl reset --graceful --system-labels-to-wipe EPHEMERAL --reboot`. EPHEMERAL returns to
  the SD card. One node at a time.
- **Option B:** reflash the SD card with the same schematic and re-apply the node config. The
  `BOOT_ORDER=0xf14` fallback means a Pi with no bootable USB attached boots from SD on its own.

## References

- [Talos VolumeConfig reference](https://docs.siderolabs.com/talos/v1.13/reference/configuration/block/volumeconfig/)
- [Talos disk management](https://docs.siderolabs.com/talos/v1.13/configure-your-talos-cluster/storage-and-disk-management/disk-management/common/)
- [Talos Raspberry Pi series](https://docs.siderolabs.com/talos/v1.13/platform-specific-installations/single-board-computers/rpi_generic)
- [siderolabs/talos#9394 — placing EPHEMERAL on another disk](https://github.com/siderolabs/talos/issues/9394) (source of the working `!system_disk` match)
- [RPi forums — USB3 SSD speed/UAS sticky](https://forums.raspberrypi.com/viewtopic.php?t=245931)
- [James A. Chambers — RPi4 USB boot config guide](https://jamesachambers.com/raspberry-pi-4-usb-boot-config-guide-for-ssd-flash-drives/)
