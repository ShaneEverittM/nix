# Declarative `tailscale serve` reverse proxies: one HTTPS port on this node's tailnet
# name per entry, each forwarding to a loopback-only service. Tailnet-only -- this is
# `serve`, not `funnel`, so nothing here is reachable from the public internet.
#
# `tailscale serve` state lives in a runtime file, not this flake, so each proxy is wrapped
# in a oneshot that re-establishes it on boot and on a clean reprovision.
{
  config,
  lib,
  pkgs,
  ...
}:

let
  cfg = config.publicTailscale.serve;
  tailscale = "${pkgs.tailscale}/bin/tailscale";
  flock = "${pkgs.util-linux}/bin/flock";
  lockFile = "/run/tailscale-serve.lock";
in
{
  options.publicTailscale.serve = lib.mkOption {
    default = { };
    description = "Tailnet-only HTTPS reverse proxies, keyed by a short service name.";
    type = lib.types.attrsOf (
      lib.types.submodule {
        options = {
          description = lib.mkOption {
            type = lib.types.str;
            description = "systemd unit description.";
          };
          httpsPort = lib.mkOption {
            # The only ports `tailscale serve` terminates HTTPS on.
            type = lib.types.enum [
              443
              8443
              10000
            ];
            default = 443;
            description = "Port on the tailnet name. One service per port.";
          };
          target = lib.mkOption {
            type = lib.types.str;
            example = "http://localhost:8090";
            description = "Local URL the proxy forwards to.";
          };
        };
      }
    );
  };

  config = {
    assertions = [
      {
        assertion =
          let
            ports = lib.mapAttrsToList (_: s: s.httpsPort) cfg;
          in
          lib.unique ports == ports;
        message = "publicTailscale.serve: two entries share an httpsPort.";
      }
    ];

    systemd.services = lib.mapAttrs' (
      name: srv:
      lib.nameValuePair "tailscale-serve-${name}" {
        inherit (srv) description;
        after = [ "tailscaled.service" ];
        wants = [ "tailscaled.service" ];
        wantedBy = [ "multi-user.target" ];

        # `After=tailscaled.service` is satisfied the moment tailscaled's Type=notify
        # readiness fires, which only means its local API socket is up. `tailscale
        # serve` additionally needs the ipn backend to have completed its control-plane
        # login and reached `Running`; that lands ~1.5s later here, so this oneshot lost
        # the race and died with "unexpected state: NoState" on every boot (a manual
        # restart always worked, which is what made it look intermittent). The wait is
        # generous because it was sized for wifi; on a never-authenticated node the state
        # stays `NeedsLogin` and this fails after the timeout with that state named in
        # the journal, which is the honest signal to go run `tailscale up`.
        preStart = ''
          for _ in $(seq 1 60); do
            state=$(${tailscale} status --json 2>/dev/null \
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
          # Serialised across every serve unit. `tailscale serve` edits one shared
          # config as read-modify-write, and a writer that loses the race does not
          # retry: it exits 1 with "etag mismatch". The units all become ready in the
          # same second (they wait on the same backend state above), so without the
          # lock a boot brings up whichever proxy won and leaves the rest failed.
          ExecStart = "${flock} ${lockFile} ${tailscale} serve --bg --https=${toString srv.httpsPort} ${srv.target}";
          ExecStop = "${flock} ${lockFile} ${tailscale} serve --https=${toString srv.httpsPort} off";
        };
      }
    ) cfg;
  };
}
