# btrfs tuning shared by every host — both boxes have the same single-disk layout
# (btrfs pool with /, home, nix; root is the top level, subvolid=5). The snapshot half
# lives per-host (exodus: hosts/exodus/btrbk.nix); this is the mount-time and
# maintenance half. Everything here is the "uncontroversial" subset — nothing that can
# lose data, only things that trade a little CPU for less disk and fewer bit-rot
# surprises. On a single disk with no redundancy the monthly scrub can only *report*
# rot, not repair data (metadata is DUP and self-heals) — early warning, not
# redundancy.
#
# Mount options only bite NEW writes after the next mount, and nixos-rebuild switch
# does NOT remount a live root/home/nix — so these land on the next *reboot*. Existing
# extents stay as-is until rewritten; a one-shot `btrfs filesystem defragment -czstd
# -r` (run by hand, post-reboot) recompresses data already on disk. `compsize` shows
# on-disk vs logical size to confirm it took. NOCOW subvolumes are never compressed by
# nature, and `-r` defragment must SKIP them or they're forced back to CoW — on exodus
# that's the Craftoria world (see hosts/exodus/craftoria.nix).
#
# hardware-configuration.nix is generated ("Do not modify this file!"), so we don't
# touch its fileSystems entries — instead we *add* options here. NixOS merges
# `fileSystems.<mp>.options` (a listOf str) by concatenation across modules, so
# `subvol=…` from the hardware scan and these flags coexist without mkForce.
{
  config,
  lib,
  pkgs,
  ...
}:

let
  cfg = config.publicNixos.btrfs;
in
{
  # Per-host compression level. Plain "zstd" is level 3 — the right default for both
  # boxes today. The knob exists for rebirth's weaker, thermally-constrained laptop
  # CPU: if compression cost ever shows up there, set "zstd:1" (much lighter, keeps
  # most of the ratio) without forking the module.
  options.publicNixos.btrfs.compression = lib.mkOption {
    type = lib.types.str;
    default = "zstd";
    example = "zstd:1";
    description = "btrfs compress= mount value applied to the pool mounts.";
  };

  config = {
    # zstd transparent compression; the store is the big win, text-y config/logs
    # compress well too.
    #
    # discard=async is already the btrfs default on this kernel; it's pinned here so
    # the mechanism that does the actual trimming is visible in the config rather than
    # being an implicit default nothing records. See the trim note below.
    fileSystems."/".options = [
      "compress=${cfg.compression}"
      "discard=async"
    ];
    fileSystems."/home".options = [
      "compress=${cfg.compression}"
      "discard=async"
    ];

    # /nix additionally gets noatime: the store is read constantly and nix never
    # consults atime, so relatime's once-a-day atime write is pure churn here. /, /home
    # stay on the default relatime — a few programs (mail clients, tmpwatch) still read
    # atime there.
    fileSystems."/nix".options = [
      "compress=${cfg.compression}"
      "discard=async"
      "noatime"
    ];

    # Monthly scrub: walk every extent, verify data+metadata checksums, and (single
    # disk = no redundancy) at least *report* bit rot instead of silently handing back
    # bad blocks. Auto-detects the mounted btrfs filesystems. Cost is a bounded
    # tens-of-minutes read, once a month, niced by the service.
    services.btrfs.autoScrub = {
      enable = true;
      interval = "monthly";
    };

    # Trim: BOTH mechanisms, deliberately. They have different shapes —
    #   discard=async  event-driven. Extents freed by a transaction commit are queued
    #                  to a background kthread (not the commit path, unlike the old
    #                  synchronous `discard`, which stalled). Does essentially all the
    #                  real work here.
    #   fstrim.timer   state-based weekly sweep. Walks the current free set, including
    #                  the *unallocated* device space that isn't part of any chunk.
    #
    # The overlap is large and fstrim's marginal catch is small — but the async queue
    # lives in memory and does NOT survive unmount, so anything still backlogged at
    # reboot is never discarded by it. fstrim is the backstop for that, and for
    # anything freed under a mount that lacked discard. Cost is sub-second (free space
    # is a handful of huge contiguous ranges, and DSM packs 256 per command), and
    # Deallocate only updates FTL metadata — it erases no NAND, so trimming more often
    # costs no wear.
    #
    # Set explicitly even though true is the NixOS default: dropping it would leave
    # trim depending entirely on a kernel default that appears nowhere, and if that
    # ever changed the failure is silent — no error, no log line, just write
    # amplification months later. Redundancy that costs sub-second weekly is the cheap
    # kind. Check the async side with
    #   grep . /sys/fs/btrfs/<pool-uuid>/discard/*
    # where discardable_bytes is the live backlog and discard_bytes_saved counts
    # discards correctly skipped because the space got re-allocated first.
    services.fstrim.enable = true;

    # compsize: shows actual on-disk vs. logical size per file/dir — the way to
    # confirm the compress mount option + defragment actually took.
    environment.systemPackages = [ pkgs.compsize ];
  };
}
