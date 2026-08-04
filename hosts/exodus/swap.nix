# Disk swap for exodus: the low-priority *overflow* tier layered under zram.
#
# This is the "genuine overflow capacity" the zram comment in ./configuration.nix flagged
# as deferred. The two swaps are not redundant -- they're a hierarchy keyed on swap
# priority (higher = drained first):
#
#   zram0     prio  5   compressed in-RAM swap. Absorbs the first spike, fast, but every
#                       page it holds still costs real RAM -- it's headroom, not capacity.
#   swapfile  prio -10  disk-backed. Slow, but a *real* second reserve that frees RAM
#                       outright. The graceful-degradation tier: under sustained pressure
#                       the box swaps to disk and gets slow instead of hitting a hard wall
#                       the instant zram saturates.
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
  # Dedicated, never-snapshotted subvolume for the swapfile. nodatacow at the mount makes
  # every file here NOCOW (belt-and-suspenders with mkswapfile's per-file +C); it also
  # drops compression + checksums, which swap neither needs nor tolerates. noatime because
  # a swapfile has no meaningful atime. Same pool as / (uuid 754b89dd…, see ./btrfs.nix).
  fileSystems."/swap" = {
    device = "/dev/disk/by-uuid/754b89dd-16eb-4488-8c0c-96b7cf14e5b0";
    fsType = "btrfs";
    options = [
      "subvol=swap"
      "nodatacow"
      "noatime"
    ];
  };

  # 16 GiB: comfortably larger than RAM (14.5 GiB now, 32 GiB after the planned upgrade),
  # so the overflow window survives the RAM bump without a resize. priority below zram's 5
  # keeps it strictly the second tier -- the kernel only spills here once zram is full.
  swapDevices = [
    {
      device = "/swap/swapfile";
      size = 16 * 1024; # MiB
      priority = -10;
    }
  ];
}
