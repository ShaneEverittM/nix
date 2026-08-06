# Network discovery + tailnet, shared by every host. The interface stack itself is
# per-host (exodus: NetworkManager; rebirth: wpa_supplicant) and stays in each
# hosts/<name>/configuration.nix.
_:

{
  # mDNS: advertise/resolve `*.local` on the LAN so each box answers to
  # `<hostname>.local` without a static IP. nssmdns4 wires mDNS into nsswitch so it
  # resolves other `.local` hosts too; openFirewall opens UDP 5353.
  services.avahi = {
    enable = true;
    nssmdns4 = true;
    openFirewall = true;
    publish = {
      enable = true;
      addresses = true;
    };
  };

  # Tailscale: stable MagicDNS name + reachability from any tailnet device, LAN or
  # remote, over WireGuard. Enabling installs tailscaled + the CLI; join the tailnet
  # once with an interactive `tailscale up` (no key in this public repo).
  services.tailscale.enable = true;

  # systemd-resolved, so Tailscale configures split DNS over D-Bus (tailnet domains →
  # 100.100.100.100, everything else → the DHCP resolver) instead of capturing and
  # overwriting /etc/resolv.conf. Shared, not per-host: both boxes are on Wi-Fi and
  # run tailscaled, so the boot race this ends is generic — with plain openresolv,
  # tailscaled can capture resolv.conf before the DHCP nameserver lands and end up
  # with an empty upstream list, blackholing every non-tailnet query (first observed
  # on rebirth post-`tailscale up`: MagicDNS names resolved, nothing else did).
  # NetworkManager on exodus detects resolved and pushes DNS to it natively.
  services.resolved.enable = true;
}
