# Memory-pressure baseline shared by every host: compressed in-RAM swap so anonymous
# pages become reclaimable, and earlyoom as the userspace backstop that SIGTERMs the
# biggest hog before the kernel livelocks (the in-kernel OOM killer fires too late
# under thrash — exodus once hard-froze exactly this way; a headless box doing the
# same has no console to notice from, so the server wants this even more than the
# desktop). Hosts layer their tuning on top: exodus sets zram algorithm/size/priority,
# a disk-swapfile overflow tier (hosts/exodus/swap.nix), and tighter earlyoom
# thresholds.
_:

{
  zramSwap.enable = true;
  services.earlyoom.enable = true;
}
