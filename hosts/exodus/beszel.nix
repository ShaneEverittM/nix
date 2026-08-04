# Beszel: a lightweight web dashboard for system metrics *history* (CPU, memory,
# disk, network, temperatures, SMART health), reachable over Tailscale like the
# rest of this box. It replaces the earlier Cockpit experiment: Cockpit's metrics
# history is hardwired to Performance Co-Pilot, which was dropped from nixpkgs, and
# this host only needs at-a-glance monitoring — anything hands-on is done over SSH.
#
# Topology (both run locally on one box):
#   hub   = the PocketBase web UI + datastore, loopback 127.0.0.1:8090.
#   agent = the local collector the hub pulls metrics from, loopback :45876.
#
# The hub reaches the agent over loopback and authenticates with an SSH keypair it
# generates on first run, so nothing here is exposed off-box directly — the only
# path to the UI is the `tailscale serve` reverse proxy below.
{ pkgs, ... }:
{
  services.beszel.hub.enable = true; # host/port default to 127.0.0.1:8090

  services.beszel.agent = {
    enable = true;
    smartmon.enable = true; # disk health + temperatures via smartmontools

    environment = {
      # Bind to loopback only; the hub reaches it locally, so there is no firewall
      # hole (openFirewall stays off). Default would listen on all interfaces.
      LISTEN = "127.0.0.1:45876";

      # The hub's PUBLIC SSH key — it authorizes which hub may connect to this
      # agent. Public-key material, safe to commit, so no secret store is warranted
      # (if you ever switch to Beszel's WebSocket mode, its TOKEN *is* sensitive and
      # belongs in `environmentFile`). The agent refuses to start without a key, so
      # this cannot be left blank. Derived from the keypair the hub generates in its
      # data dir on first run:
      #   run0 ssh-keygen -y -f /var/lib/private/beszel-hub/beszel_data/id_ed25519
      # It is stable across reboots and only changes if the hub data dir is wiped
      # (e.g. a clean reprovision), in which case re-derive and update this line.
      KEY = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIEZrbPENwvxP+3/Cua/N5iXge12kdBfWYvPTaSq8k1tT";
    };
  };

  # Reverse-proxy the Beszel hub onto the tailnet — same declarative pattern the
  # Cockpit setup used. `tailscale serve` state lives in a runtime file, not this
  # flake, so wrap it in a oneshot to re-establish the proxy on a clean reprovision.
  systemd.services.tailscale-serve-beszel = {
    description = "Expose Beszel hub (localhost:8090) over Tailscale HTTPS";
    after = [ "tailscaled.service" ];
    wants = [ "tailscaled.service" ];
    wantedBy = [ "multi-user.target" ];

    # `After=tailscaled.service` is satisfied the moment tailscaled's Type=notify
    # readiness fires, which only means its local API socket is up. `tailscale
    # serve` additionally needs the ipn backend to have completed its control-plane
    # login and reached `Running`; that lands ~1.5s later here, so this oneshot lost
    # the race and died with "unexpected state: NoState" on every boot (a manual
    # restart always worked, which is what made it look intermittent). The wait is
    # generous because this host is on wifi — association and the login round trip
    # can both be slow. On a never-authenticated node the state stays `NeedsLogin`
    # and this fails after the timeout with that state named in the journal, which
    # is the honest signal to go run `tailscale up`.
    preStart = ''
      for _ in $(seq 1 60); do
        state=$(${pkgs.tailscale}/bin/tailscale status --json 2>/dev/null \
          | ${pkgs.jq}/bin/jq -r '.BackendState // empty' 2>/dev/null) || true
        if [ "$state" = "Running" ]; then
          exit 0
        fi
        sleep 1
      done
      echo "tailscaled backend never reached Running (last state: ''${state:-unknown})" >&2
      exit 1
    '';

    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
      ExecStart = "${pkgs.tailscale}/bin/tailscale serve --bg --https=443 http://localhost:8090";
      ExecStop = "${pkgs.tailscale}/bin/tailscale serve --https=443 off";
    };
  };
}
