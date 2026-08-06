# btrbk: local timeline snapshots of the irreproducible data on exodus. Scoped, per the
# btrfs plan, to the things that can't just be re-downloaded:
#   - home  : SSH keys, uncommitted branches, dotfiles not yet in this flake.
#   - each Minecraft world subvolume (see ./minecraft), which a modpack/version bump can
#     destroy one-way. The static pack trees are deliberately NOT snapshotted -- they're
#     re-downloadable from CurseForge. A pack that is currently stopped is still
#     snapshotted; only `snapshotWorld = false` takes one out.
#
# Snapshots are not recursive, so each world is listed *separately* from home even though
# they live inside it -- without those lines the worlds would be silently skipped, which is
# the whole point of giving them their own subvolumes. The worlds are NOCOW: the first
# write to each block after a snapshot is forced back to CoW, so weekly (not a tight timer)
# keeps that cost small.
#
# Snapshots are named `<pack>-world.<timestamp>` (see snapshot_name below). Craftoria's
# pre-existing snapshots are from when it was the only pack and are named plain `world.*`;
# they are still valid, readable snapshots, but btrbk no longer manages or expires them --
# nothing matches that name any more. Delete them by hand (`btrfs subvolume delete
# /.snapshots/world.*`) once the new timeline has enough depth to be worth keeping instead.
#
# ./minecraft adds ExecStartPre/ExecStopPost to the btrbk-local unit this generates, one
# freeze/thaw pair per server, to quiesce them (save-off + save-all flush) around the run --
# otherwise the world snapshots are only crash-consistent. Look there before debugging a
# btrbk-local failure, and note that it runs for the manual `systemctl start btrbk-local`
# too.
#
# NOT snapshotted: /nix (snapshots would pin store paths and defeat nix-collect-garbage)
# and / (subvolid=5, not snapshottable). Both are already separate subvolumes, so this is
# free.
#
# Snapshots on one disk are not a backup. The off-box `btrfs send -p` half of the plan is
# deferred until there's a target host -- add a `target` under the volume then.
#
# The mount-time/maintenance half (compression, autoScrub, fstrim) lives in the shared
# modules/nixos/btrfs.nix; zram in the shared memory.nix + this host's tuning.
{ config, lib, ... }:

{
  # .snapshots as its own subvolume on the top-level (subvolid=5, mounted at /), which is
  # itself never snapshotted -- keeps the snapshot tree out of the home timeline. `v`
  # makes a subvolume on btrfs, and only acts when the path doesn't already exist.
  systemd.tmpfiles.rules = [
    "v /.snapshots 0755 root root -"
  ];

  services.btrbk.instances.local = {
    onCalendar = "weekly";
    settings = {
      # Keep at least 2 days, then thin to weeklies for a month and monthlies for half a
      # year.
      snapshot_preserve_min = "2d";
      snapshot_preserve = "4w 6m";
      volume."/" = {
        snapshot_dir = ".snapshots";
        # The world paths come off the module rather than being restated here: btrbk needs
        # the volume-relative form, and `worldSubvolume` is the read-only option in
        # ./minecraft/service.nix that derives it from the same serverDir the unit runs in,
        # so the two cannot drift. The module's tmpfiles rules also guarantee each of these
        # exists before the first run -- btrbk fails the *whole* run, home included, on a
        # subvolume that isn't there.
        subvolume = {
          "home" = { };
        }
        // lib.mapAttrs' (
          name: srv:
          lib.nameValuePair srv.worldSubvolume {
            # snapshot_name is REQUIRED once there is more than one pack. It defaults to the
            # source subvolume's basename, and every pack's world subvolume is called
            # `world` -- so the default would put two different worlds in one snapshot_dir
            # under one name. btrbk would disambiguate them positionally with its `_N`
            # collision suffix (`world.<ts>` and `world.<ts>_1`, with no stable indication of
            # which pack is which), and, worse, it identifies a subvolume's snapshot set by
            # snapshot_name + snapshot_dir -- so each pack's retention pass would treat the
            # other pack's snapshots as its own series and thin them accordingly.
            snapshot_name = "${name}-world";
          }
        ) (lib.filterAttrs (_: srv: srv.snapshotWorld) config.publicMinecraft.servers);
      };
    };
  };
}
