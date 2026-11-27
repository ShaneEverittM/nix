# Cockpit: the hands-on web console (units and their logs, journal, storage, accounts, a
# terminal), reachable over Tailscale like the rest of this box. Second go at it: the
# first was dropped for Beszel (./beszel.nix) because Cockpit's metrics *history* needs
# Performance Co-Pilot, which nixpkgs removed. That is still true, so the two split the
# job -- Beszel for history and at-a-glance health, Cockpit for poking at the machine.
#
# Topology: cockpit.socket on loopback :9090 only, fronted by a `tailscale serve` HTTPS
# proxy on :10000 (443 is Beszel, 8443 is Sure; this takes the last port serve offers).
# Nothing is opened in the firewall.
#
# Login is PAM: the account's password (`passwd`), not the SSH key. "Administrative
# access" inside the UI escalates through sudo.
{ config, lib, ... }:

let
  port = 9090;
  servePort = 10000;
in
{
  services.cockpit = {
    enable = true;
    inherit port;

    # The stock banner prints "Web console: https://<host>:9090/" into issue + motd,
    # which is exactly the address that does not work here.
    showBanner = false;

    # Cockpit refuses a websocket whose Origin is not on this list, and behind the proxy
    # the browser's origin is the tailnet name, not localhost. Globbed (Origins go
    # through fnmatch) so the tailnet's own name stays out of this public repo.
    allowed-origins = [ "https://${config.networking.hostName}.*.ts.net:${toString servePort}" ];

    settings.WebService = {
      # The proxy terminates TLS and talks plain HTTP over loopback. Without this
      # Cockpit sees an http request carrying an https Origin and rejects it. Trusting
      # the header is safe only because the socket below is loopback-only, so nothing
      # but the proxy can set it.
      ProtocolHeader = "X-Forwarded-Proto";
      ForwardedForHeader = "X-Forwarded-For";
    };
  };

  # The upstream unit listens on every interface, and the NixOS module keeps that. The
  # firewall would stop it anyway, but the header trust above should not hang on a
  # firewall rule. The leading "" clears the packaged ListenStream= so this replaces it
  # rather than adding a second listener.
  systemd.sockets.cockpit.listenStreams = lib.mkForce [
    ""
    "127.0.0.1:${toString port}"
  ];

  publicTailscale.serve.cockpit = {
    description = "Expose Cockpit (127.0.0.1:${toString port}) over Tailscale HTTPS";
    httpsPort = servePort;
    target = "http://127.0.0.1:${toString port}";
  };
}
