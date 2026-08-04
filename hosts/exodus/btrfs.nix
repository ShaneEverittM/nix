# btrfs tuning for exodus's single-disk pool (uuid 754b89dd…, subvols /, home, nix).
# The snapshot half of the btrfs plan lives in ./btrbk.nix; this file is the mount-time
# and maintenance half. Everything here is the "uncontroversial" subset -- nothing that
# can lose data, only things that trade a little CPU for less disk and fewer bit-rot
# surprises.
#
# Mount options only bite NEW writes after the next mount, and nixos-rebuild switch does
# NOT remount a live root/home/nix -- so these land on the next *reboot*. Existing extents
# stay as-is until rewritten; the one-shot `btrfs filesystem defragment -czstd -r` (run by
# hand, post-reboot) is what recompresses the data already on disk. See the README / the
# handoff notes for that ritual.
#
# hardware-configuration.nix is generated ("Do not modify this file!"), so we don't touch
# its fileSystems entries -- instead we *add* options here. NixOS merges `fileSystems.<mp>.
# options` (a listOf str) by concatenation across modules, so `subvol=…` from the hardware
# scan and these flags coexist without mkForce.
{ pkgs, ... }:

{
  # zstd (level 3) transparent compression. The store and world are the big wins; text-y
  # config/logs compress well too. Excluded by nature: the Craftoria `world` subvolume is
  # NOCOW (nodatacow implies no compression), so `-r` defragment must skip it or it'd be
  # forced back to CoW -- see the defragment caveat in the handoff notes.
  #
  # discard=async is already the btrfs default on this kernel; it's pinned here so the
  # mechanism that does the actual trimming is visible in the config rather than being an
  # implicit default nothing records. See the trim note below.
  fileSystems."/".options = [
    "compress=zstd"
    "discard=async"
  ];
  fileSystems."/home".options = [
    "compress=zstd"
    "discard=async"
  ];

  # /nix additionally gets noatime: the store is read constantly and nix never consults
  # atime, so relatime's once-a-day atime write is pure churn here. Left /, /home on the
  # default relatime -- a few programs (mail clients, tmpwatch) still read atime there.
  fileSystems."/nix".options = [
    "compress=zstd"
    "discard=async"
    "noatime"
  ];

  # Monthly scrub: walk every extent, verify data+metadata checksums, and (single disk =
  # no redundancy) at least *report* bit rot instead of silently handing back bad blocks.
  # Auto-detects the mounted btrfs filesystems.
  services.btrfs.autoScrub = {
    enable = true;
    interval = "monthly";
  };

  # Trim: BOTH mechanisms, deliberately. They have different shapes --
  #   discard=async  event-driven. Extents freed by a transaction commit are queued to a
  #                  background kthread (not the commit path, unlike the old synchronous
  #                  `discard`, which stalled). Does essentially all the real work here.
  #   fstrim.timer   state-based weekly sweep. Walks the current free set, including the
  #                  *unallocated* device space that isn't part of any chunk.
  #
  # The overlap is large and fstrim's marginal catch is small -- but the async queue lives
  # in memory and does NOT survive unmount, so anything still backlogged at reboot is never
  # discarded by it. fstrim is the backstop for that, and for anything freed under a mount
  # that lacked discard. Cost is sub-second on this filesystem (free space is a handful of
  # huge contiguous ranges, and DSM packs 256 per command), and Deallocate only updates FTL
  # metadata -- it erases no NAND, so trimming more often costs no wear.
  #
  # Set explicitly even though true is the NixOS default: dropping it would leave trim
  # depending entirely on a kernel default that appears nowhere, and if that ever changed
  # the failure is silent -- no error, no log line, just write amplification months later.
  # Redundancy that costs sub-second weekly is the cheap kind. Check the async side with
  #   grep . /sys/fs/btrfs/754b89dd-16eb-4488-8c0c-96b7cf14e5b0/discard/*
  # where discardable_bytes is the live backlog and discard_bytes_saved counts discards
  # correctly skipped because the space got re-allocated first.
  services.fstrim.enable = true;

  # compsize: shows actual on-disk vs. logical size per file/dir -- the way to confirm the
  # compress mount option + defragment actually took.
  environment.systemPackages = [ pkgs.compsize ];
}
