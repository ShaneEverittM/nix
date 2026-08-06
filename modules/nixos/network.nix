# Network discovery + tailnet, shared by every host. The interface stack itself is
# per-host (exodus: NetworkManager; rebirth: wpa_supplicant) and stays in each
# hosts/<name>/configuration.nix.
{ ... }:

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
}
