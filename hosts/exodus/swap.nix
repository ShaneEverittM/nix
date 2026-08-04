# Disk swap for exodus: the low-priority *overflow* tier layered under zram.
#
# This is the "genuine overflow capacity" the zram comment in ./configuration.nix flagged
# as deferred. The two swaps are not redundant -- they're a hierarchy keyed on swap
# priority (higher = drained first):
#
#   zram0     prio 100  compressed in-RAM swap. Absorbs the first spike, fast, but every
#                       page it holds still costs real RAM -- it's headroom, not capacity.
#   swapfile  prio  10  disk-backed. Slow, but a *real* second reserve that frees RAM
#                       outright. The graceful-degradation tier: under sustained pressure
#                       the box swaps to disk and gets slow instead of hitting a hard wall
#                       the instant zram saturates.
#
# Both priorities are set explicitly, and both are POSITIVE. Negative priorities cannot be
# requested at all: swapon(2) encodes priority in a 15-bit unsigned field gated by
# SWAP_FLAG_PREFER, so swapon(8) accepts only 0..32767 and the kernel's own auto-assignment
# is what produces the negative values you see in /proc/swaps. This module originally asked
# for prio -10, which util-linux silently dropped -- no error, no journal warning -- leaving
# the kernel to auto-assign -2 (its first auto value: the counter starts at -1 and
# pre-decrements). The tiering still worked by luck, since -2 < 5, but nothing was actually
# being requested. The gap between 100 and 10 leaves room to slot a tier between them.
#
# zram's priority is set in ./configuration.nix rather than defaulted, deliberately: half of
# a documented hierarchy resting on a module default is how the above went unnoticed.
#
# Having a real reserve also un-breaks earlyoom's swap guard: with zram-only, "free swap"
# tracked RAM the compressed store was already eating, so the threshold could gate itself
# off. A disk tier makes free-swap a meaningful signal again. See ./configuration.nix.
#
# btrfs swapfile constraints and how they're met:
#   - NOCOW + no compression + fully allocated (no holes): swap needs a stable physical
#     block map. NixOS's swapDevices creation detects a btrfs target dir and uses
#     `btrfs filesystem mkswapfile`, which sets all three -- so we just declare it below.
#   - never snapshotted: a snapshot would share the extents CoW and break the stable map.
#     btrfs snapshots do NOT cross subvolume boundaries, so the swapfile lives in its own
#     `swap` subvolume -- structurally invisible to any root snapshot and to btrbk (which
#     targets home + the Craftoria world), with no exclusion rule to maintain.
#
# ONE-TIME RITUAL (like the beszel keygen / `tailscale up` steps -- host-local state this
# public flake can't carry). The subvolume must exist before the /swap mount can succeed;
# NixOS creates the swapfile itself on first activation. On a fresh box, before the first
# switch that includes this module:
#   sudo btrfs subvolume create /swap        # top-level (subvolid=5) is mounted at /
# then `nixos-rebuild switch`. The mount + mkswapfile + swapon come up on the next boot.
{
  # Dedicated, never-snapshotted subvolume for the swapfile. noatime because a swapfile has
  # no meaningful atime. Same pool as / (uuid 754b89dd…, see ./btrfs.nix).
  #
  # Deliberately NOT `nodatacow` here, however much it looks like it belongs: btrfs applies
  # compress/datacow per *filesystem*, not per subvolume. / mounts this pool first with
  # `compress=zstd:3` + datacow, so this mount inherits that and silently ignores any
  # contrary option -- confirmed with `findmnt /swap`. Listing it would only imply a
  # guarantee the mount does not provide. The NOCOW that swap genuinely requires comes
  # solely from mkswapfile's per-file +C (`lsattr /swap/swapfile` shows the C flag), and
  # NOCOW is in turn what drops compression + checksums, which swap neither needs nor
  # tolerates. Nothing at the mount layer backstops that.
  fileSystems."/swap" = {
    device = "/dev/disk/by-uuid/754b89dd-16eb-4488-8c0c-96b7cf14e5b0";
    fsType = "btrfs";
    options = [
      "subvol=swap"
      "noatime"
    ];
  };

  # 16 GiB: comfortably larger than RAM (14.5 GiB now, 32 GiB after the planned upgrade),
  # so the overflow window survives the RAM bump without a resize. priority below zram's 100
  # keeps it strictly the second tier -- the kernel only spills here once zram is full.
  # Must stay in 0..32767; see the header on why negatives are silently ignored.
  swapDevices = [
    {
      device = "/swap/swapfile";
      size = 16 * 1024; # MiB
      priority = 10;
    }
  ];
}
