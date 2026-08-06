# btrbk: local timeline snapshots of the irreproducible data on exodus. Scoped, per the
# btrfs plan, to the two things that can't just be re-downloaded:
#   - home  : SSH keys, uncommitted branches, dotfiles not yet in this flake.
#   - the Craftoria 2 world subvolume (see ./craftoria.nix), which a modpack/version
#     bump can destroy one-way. The static pack tree under craftoria2/ is deliberately
#     NOT snapshotted -- it's re-downloadable from CurseForge.
#
# Snapshots are not recursive, so the world is listed *separately* from home even though
# it lives inside it -- without that line the world would be silently skipped, which is
# the whole point of giving it its own subvolume. The world is NOCOW: the first write to
# each block after a snapshot is forced back to CoW, so weekly (not a tight timer) keeps
# that cost small.
#
# ./craftoria.nix adds ExecStartPre/ExecStopPost to the btrbk-local unit this generates,
# to quiesce the Minecraft server (save-off + save-all flush) around the run -- otherwise
# the world snapshot is only crash-consistent. Look there before debugging a btrbk-local
# failure, and note that it runs for the manual `systemctl start btrbk-local` too.
#
# NOT snapshotted: /nix (snapshots would pin store paths and defeat nix-collect-garbage)
# and / (subvolid=5, not snapshottable). Both are already separate subvolumes, so this is
# free.
#
# Snapshots on one disk are not a backup. The off-box `btrfs send -p` half of the plan is
# deferred until there's a target host -- add a `target` under the volume then.
#
# Deliberately out of scope here (the plan's non-Minecraft btrfs items): compression
# mount options, autoScrub, and the fstrim disable. zram already lives in
# configuration.nix.
{
  # .snapshots as its own subvolume on the top-level (subvolid=5, mounted at /), which is
  # itself never snapshotted -- keeps the snapshot tree out of the home timeline. `v`
  # makes a subvolume on btrfs, and only acts when the path doesn't already exist.
  # (The world subvolume path below is shared with craftoria.nix via
  # ./craftoria-paths.nix, so the two files cannot drift apart.)
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
        subvolume = {
          "home" = { };
          ${(import ./craftoria-paths.nix).worldSubvolume} = { };
        };
      };
    };
  };
}
