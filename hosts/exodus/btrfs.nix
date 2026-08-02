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
  fileSystems."/".options = [ "compress=zstd" ];
  fileSystems."/home".options = [ "compress=zstd" ];

  # /nix additionally gets noatime: the store is read constantly and nix never consults
  # atime, so relatime's once-a-day atime write is pure churn here. Left /, /home on the
  # default relatime -- a few programs (mail clients, tmpwatch) still read atime there.
  fileSystems."/nix".options = [
    "compress=zstd"
    "noatime"
  ];

  # Monthly scrub: walk every extent, verify data+metadata checksums, and (single disk =
  # no redundancy) at least *report* bit rot instead of silently handing back bad blocks.
  # Auto-detects the mounted btrfs filesystems.
  services.btrfs.autoScrub = {
    enable = true;
    interval = "monthly";
  };

  # compsize: shows actual on-disk vs. logical size per file/dir -- the way to confirm the
  # compress mount option + defragment actually took.
  environment.systemPackages = [ pkgs.compsize ];
}
