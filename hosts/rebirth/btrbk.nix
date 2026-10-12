# btrbk receive target for exodus's off-box snapshot replication -- the `btrfs send -p`
# half of exodus's btrfs plan (see hosts/exodus/btrbk.nix). exodus pushes each snapshot
# here over SSH right after taking it; this host runs no timeline of its own, it only
# authorizes the receive.
#
# services.btrbk.sshAccess does all the privileged wiring: it creates the dedicated
# `btrbk` system user, pins exodus's public key to ssh_filter_btrbk.sh as a forced
# command (btrfs-receive ops only, never an interactive shell), and adds the NOPASSWD
# sudo rule that lets that otherwise-unprivileged user run `btrfs receive`. PermitRootLogin
# stays "no" -- the key logs in as `btrbk`, not root. The only sshd concession is admitting
# that account past the shared AllowUsers allowlist, via publicNixos.ssh.extraAllowUsers.
#
# Received subvolumes land under /var/lib/btrbk/exodus, which is on the root btrfs pool so
# `btrfs receive` works. Retention on this copy is driven from the *source*
# (target_preserve in hosts/exodus/btrbk.nix), since exodus owns the whole transaction.
_:

{
  # Admit the service account sshAccess creates; its key is forced-command only.
  publicNixos.ssh.extraAllowUsers = [ "btrbk" ];

  services.btrbk.sshAccess = [
    {
      key = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIB1MUFXY42Zfq2tbL5Z81rkEJRq/YKxUBBf6TrYag5Hh btrbk exodus->rebirth";
      # Receiver roles only: accept an incoming stream (receive), be addressable as a
      # target (target/info), and let the source-driven retention prune old backups here
      # (delete). No send/snapshot -- this host never originates a backup.
      roles = [
        "info"
        "target"
        "receive"
        "delete"
      ];
    }
  ];

  # The directory exodus receives into: just needs to exist on a btrfs filesystem and be
  # owned by the btrbk user; `btrfs receive` creates the per-subvolume children under it.
  systemd.tmpfiles.rules = [
    "d /var/lib/btrbk/exodus 0750 btrbk btrbk -"
  ];
}
