# Public game servers, each in its own microVM.
#
# WHY VMs. These are the only things on this box that take traffic from the open
# internet (friends connect by DNS name, so they cannot hide behind the tailnet), and
# they are exactly the kind of software that gets popped: a few hundred community mods
# in one JVM, or a closed-source Windows server under Proton. The box also holds things
# worth having -- a home directory, GitHub credentials, soon a NAS -- so "a sandboxed
# unit" is not enough separation: a systemd sandbox or a container shares the host
# kernel, and one kernel bug turns a game-server RCE into the whole machine. A guest
# kernel behind KVM is a much narrower interface, and what is on the other side of it
# here is deliberately worthless: a guest has its game's files and nothing else.
#
# This file is the game-agnostic layer. A game's own module (./minecraft/host.nix)
# declares `publicGameServers.servers.<name>` with a guest NixOS module; from that this
# file produces the microVM, its network slot, the port forwards, and the `gameserver`
# command.
#
# NETWORK. Each *slot* is a routed point-to-point /30 on its own tap: 10.77.<slot>.1 is
# the host, .2 the guest. No bridge, so guests cannot see each other at layer 2 at all.
# Servers that share a slot share the tap and the address, which is how "only one of
# these may run" is enforced (systemd Conflicts= below, with the tap as the backstop)
# and why players keep one address whichever is up. The firewall rules at the bottom
# give a guest outbound internet and nothing else: not the host, not the LAN, not the
# tailnet, not another guest.
#
# ON/OFF IS STATE, NOT CONFIG. Every server is always *declared*; which ones run is a
# flag file per server under /var/lib/gameservers/enabled, read at boot and changed with
# `gameserver enable|disable <name>` -- no rebuild. `autoStart` only seeds the flags on
# the very first activation. Likewise a rebuild never restarts a running guest
# (restartIfChanged = false): players are not kicked by an unrelated `nh os switch`, and
# a guest picks up its new system the next time it is started (`gameserver restart`).
{
  config,
  inputs,
  lib,
  pkgs,
  ...
}:

let
  cfg = config.publicGameServers;
  operator = (import ../../lib/identity.nix).username;

  stateDir = "/var/lib/gameservers";
  flagDir = "${stateDir}/enabled";

  tap = slot: "vm-gs${toString slot}";
  hostAddr = slot: "10.77.${toString slot}.1";
  guestAddr = slot: "10.77.${toString slot}.2";
  # Locally administered, slot in the last octet.
  mac = slot: "02:00:00:00:77:${lib.fixedWidthString 2 "0" (lib.toHexString slot)}";

  names = lib.attrNames cfg.servers;
  slots = lib.unique (lib.mapAttrsToList (_: srv: srv.slot) cfg.servers);
  # Other servers on the same slot: they cannot run at the same time as `name`.
  rivals = name: lib.filter (n: n != name && cfg.servers.${n}.slot == cfg.servers.${name}.slot) names;

  unit = name: "microvm@${name}.service";

  # One DNAT line per forwarded port. `--dst-type LOCAL` limits it to traffic addressed
  # to this host (any interface: WAN via the router, LAN, tailnet), so it never rewrites
  # traffic merely passing through; `! -i vm-gs+` keeps a guest from reaching itself or
  # a rival through the host's public port.
  dnat =
    proto: srv: port:
    "iptables -t nat -A gs-prerouting ! -i vm-gs+ -p ${proto} -m addrtype --dst-type LOCAL --dport ${toString port} -j DNAT --to-destination ${guestAddr srv.slot}:${toString port}";

  forwards = lib.unique (
    lib.concatLists (
      lib.mapAttrsToList (
        _: srv: map (dnat "tcp" srv) srv.forwardTCP ++ map (dnat "udp" srv) srv.forwardUDP
      ) cfg.servers
    )
  );

  # Destinations a guest may never open a connection to: every private, CGNAT (the
  # tailnet), link-local and multicast range. What is left is the public internet.
  forbidden = [
    "10.0.0.0/8"
    "172.16.0.0/12"
    "192.168.0.0/16"
    "100.64.0.0/10"
    "169.254.0.0/16"
    "224.0.0.0/4"
  ];

  # `gameserver-players <protocol> <host> <port>` -> "online/max". Standard library only.
  playersQuery = pkgs.writeShellScript "gameserver-players" ''
    exec ${pkgs.python3}/bin/python3 ${./gameserver-players.py} "$@"
  '';

  gameserver = pkgs.writeShellApplication {
    name = "gameserver";
    runtimeInputs = with pkgs; [
      coreutils
      systemd
    ];
    text = ''
      names=(${lib.escapeShellArgs names})

      player_query() {
        case "$1" in
          ${lib.concatStrings (
            lib.mapAttrsToList (
              name: srv:
              lib.optionalString (srv.players != null) ''
                ${name}) echo "${srv.players.protocol} ${guestAddr srv.slot} ${toString srv.players.port}" ;;
              ''
            ) cfg.servers
          )}
          *) ;;
        esac
      }

      rivals() {
        case "$1" in
          ${lib.concatStrings (
            lib.mapAttrsToList (name: _: ''
              ${name}) echo ${lib.escapeShellArg (lib.concatStringsSep " " (rivals name))} ;;
            '') cfg.servers
          )}
        esac
      }

      usage() {
        cat <<USAGE
      usage: gameserver list                     boot flag, state and players online
             gameserver enable|disable <name>    start now and at boot / stop and stay off
             gameserver start|stop|restart <name>  this boot only; does not change enable
             gameserver logs <name>              follow the guest's console (server log)

      servers: ''${names[*]}
      USAGE
      }

      known() {
        for n in "''${names[@]}"; do
          [ "$n" = "$1" ] && return 0
        done
        echo "gameserver: no server named '$1' (have: ''${names[*]})" >&2
        return 1
      }

      cmd="''${1:-list}"
      case "$cmd" in
        list | status)
          # PLAYERS asks each running server directly, the way a server browser would.
          # "?" is a server that is up but not answering -- normal while it is still
          # loading -- and "-" is one that is stopped (or has no query configured).
          printf '%-14s %-9s %-11s %s\n' SERVER BOOT STATE PLAYERS
          for n in "''${names[@]}"; do
            if [ -e "${flagDir}/$n" ]; then boot=enabled; else boot=disabled; fi
            state="$(systemctl is-active "microvm@$n.service" || true)"
            players=-
            query="$(player_query "$n")"
            if [ "$state" = active ] && [ -n "$query" ]; then
              # shellcheck disable=SC2086 # three words: protocol, address, port
              players="$(timeout 5 ${playersQuery} $query 2>/dev/null || echo "?")"
            fi
            printf '%-14s %-9s %-11s %s\n' "$n" "$boot" "$state" "$players"
          done
          ;;
        enable)
          known "''${2:?$(usage)}"
          # Rivals share this server's address and tap, so enabling one hands the slot
          # over: the others are disabled, not just stopped, or the next boot would
          # start whichever sorted first.
          for r in $(rivals "$2"); do
            if [ -e "${flagDir}/$r" ]; then
              echo "disabling $r (shares a slot with $2)"
              rm -f "${flagDir}/$r"
            fi
          done
          touch "${flagDir}/$2"
          systemctl start "microvm@$2.service"
          ;;
        disable)
          known "''${2:?$(usage)}"
          rm -f "${flagDir}/$2"
          systemctl stop "microvm@$2.service"
          ;;
        start | stop | restart)
          known "''${2:?$(usage)}"
          systemctl "$cmd" "microvm@$2.service"
          ;;
        logs)
          known "''${2:?$(usage)}"
          exec journalctl -u "microvm@$2.service" -f
          ;;
        -h | --help | help) usage ;;
        *)
          usage >&2
          exit 2
          ;;
      esac
    '';
  };
in
{
  imports = [ inputs.microvm.nixosModules.host ];

  options.publicGameServers.servers = lib.mkOption {
    default = { };
    description = "Public game servers, each run in its own microVM. Keyed by VM name.";
    type = lib.types.attrsOf (
      lib.types.submodule {
        options = {
          slot = lib.mkOption {
            type = lib.types.ints.between 1 250;
            description = ''
              Network slot: the guest is 10.77.<slot>.2 behind tap vm-gs<slot>. Servers
              that share a slot are mutually exclusive.
            '';
          };
          memory = lib.mkOption {
            type = lib.types.ints.positive;
            description = "Guest RAM in MiB, reserved in full while the guest runs.";
          };
          vcpu = lib.mkOption {
            type = lib.types.ints.positive;
            default = 4;
            description = "Guest vCPUs.";
          };
          forwardTCP = lib.mkOption {
            type = lib.types.listOf lib.types.port;
            default = [ ];
            description = "TCP ports forwarded from this host, on every interface, to the guest.";
          };
          forwardUDP = lib.mkOption {
            type = lib.types.listOf lib.types.port;
            default = [ ];
            description = "UDP ports forwarded from this host, on every interface, to the guest.";
          };
          shares = lib.mkOption {
            default = [ ];
            description = ''
              Host directories mounted read-write at the same path inside the guest. This
              is the guest's entire view of the host's disk, so share a game's own
              directory and nothing above it.
            '';
            type = lib.types.listOf lib.types.path;
          };
          volumes = lib.mkOption {
            default = [ ];
            description = ''
              Guest-private disks, for bulky state that must outlive a restart (a guest's
              root is RAM) but that the host has no reason to see into or snapshot --
              a container image store, say. Each is an image file under
              /var/lib/microvms/<name>/, created on first start. Anything worth backing
              up belongs in `shares` instead, on the host's filesystem.
            '';
            type = lib.types.listOf (
              lib.types.submodule {
                options = {
                  image = lib.mkOption {
                    type = lib.types.str;
                    description = "Image file name, relative to the guest's state directory.";
                  };
                  mountPoint = lib.mkOption {
                    type = lib.types.path;
                    description = "Where the guest mounts it.";
                  };
                  size = lib.mkOption {
                    type = lib.types.ints.positive;
                    description = "Size in MiB when first created.";
                  };
                };
              }
            );
          };
          players = lib.mkOption {
            default = null;
            description = ''
              How `gameserver list` asks this server how many players are on it, so
              that "is anyone playing?" has an answer before a restart. Both protocols
              are the public status query a server browser sends; the host makes it
              straight to the guest's address.
            '';
            type = lib.types.nullOr (
              lib.types.submodule {
                options = {
                  protocol = lib.mkOption {
                    type = lib.types.enum [
                      "minecraft"
                      "steam"
                    ];
                    description = "`minecraft`: Server List Ping (TCP). `steam`: A2S_INFO (UDP).";
                  };
                  port = lib.mkOption {
                    type = lib.types.port;
                    description = "Port the server answers the query on, inside the guest.";
                  };
                };
              }
            );
          };
          autoStart = lib.mkOption {
            type = lib.types.bool;
            default = false;
            description = "Seed value for the enable flag on first activation; see `gameserver`.";
          };
          guest = lib.mkOption {
            type = lib.types.deferredModule;
            description = "The NixOS module(s) that make this guest a server for its game.";
          };
        };
      }
    );
  };

  config = lib.mkIf (cfg.servers != { }) {
    assertions = [
      {
        # A shared port forwarded to two addresses would silently go to whichever rule
        # came first.
        assertion = lib.all (
          a:
          lib.all (
            b:
            a.slot == b.slot
            || (
              lib.intersectLists a.forwardTCP b.forwardTCP == [ ]
              && lib.intersectLists a.forwardUDP b.forwardUDP == [ ]
            )
          ) (lib.attrValues cfg.servers)
        ) (lib.attrValues cfg.servers);
        message = "publicGameServers: two servers forward the same port but are on different slots; put them on one slot.";
      }
      {
        # Sharing a slot means "these are alternatives for one address". Two unrelated
        # games landing on one slot by accident would quietly become mutually exclusive.
        assertion = lib.all (
          a:
          lib.all (b: a.slot != b.slot || (a.forwardTCP == b.forwardTCP && a.forwardUDP == b.forwardUDP)) (
            lib.attrValues cfg.servers
          )
        ) (lib.attrValues cfg.servers);
        message = "publicGameServers: servers on the same slot must forward the same ports; give unrelated servers their own slot.";
      }
    ];

    # Despite the name this is the unit's TimeoutSec, so it bounds *stopping* a guest
    # too -- and a stop is a full guest shutdown, inside which a big world gets its own
    # 90 s to save. The default 150 s would SIGKILL qemu too close to that.
    microvm.host.startupTimeout = 300;

    microvm.vms = lib.mapAttrs (name: srv: {
      autostart = false;
      restartIfChanged = false;
      config = {
        imports = [ srv.guest ];

        microvm = {
          hypervisor = "qemu";
          mem = srv.memory;
          inherit (srv) vcpu;
          interfaces = [
            {
              type = "tap";
              id = tap srv.slot;
              mac = mac srv.slot;
            }
          ];
          shares = [
            {
              # The guest's /nix/store is the host's, read-only: no image to build or
              # keep in sync, and nothing in the store is secret.
              tag = "ro-store";
              source = "/nix/store";
              mountPoint = "/nix/.ro-store";
              proto = "virtiofs";
            }
          ]
          ++ lib.imap0 (i: path: {
            tag = "data${toString i}";
            source = path;
            mountPoint = path;
            proto = "virtiofs";
          }) srv.shares;
          volumes = map (v: {
            inherit (v) image mountPoint size;
            autoCreate = true;
            fsType = "ext4";
          }) srv.volumes;
        };

        networking.hostName = name;
        networking.useDHCP = false;
        networking.useNetworkd = true;
        systemd.network.networks."10-uplink" = {
          matchConfig.MACAddress = mac srv.slot;
          address = [ "${guestAddr srv.slot}/30" ];
          gateway = [ (hostAddr srv.slot) ];
          # Public resolvers: the host's own resolver is on the far side of the
          # firewall, on purpose.
          dns = [
            "1.1.1.1"
            "9.9.9.9"
          ];
          networkConfig = {
            IPv6AcceptRA = false;
            LinkLocalAddressing = "no";
          };
        };

        # The guest has no persistent journal and no login, so its console is the only
        # window in. qemu's stdout is the host unit's journal, which makes
        # `gameserver logs <name>` (or journalctl -u microvm@<name>) the server log.
        services.journald.extraConfig = ''
          ForwardToConsole=yes
          MaxLevelConsole=info
        '';

        # No login path into a guest at all -- no password, no key, no sshd. Deliberate:
        # it is rebuilt from this flake, and its console is in the host journal.
        users.mutableUsers = false;
        users.allowNoPasswordLogin = true;
        systemd.services."serial-getty@ttyS0".enable = false;
        system.stateVersion = config.system.stateVersion;
      };
    }) cfg.servers;

    # Same-slot servers exclude each other. Conflicts= stops the rival; the one-way
    # After= makes that stop finish before this start, whichever direction the edge
    # points (systemd orders a stop before a start across any ordering dependency) --
    # needed because both want the same tap.
    systemd.services =
      lib.mapAttrs' (
        name: _:
        lib.nameValuePair "microvm@${name}" {
          overrideStrategy = "asDropin";
          conflicts = map unit (rivals name);
          after = map unit (lib.filter (r: r < name) (rivals name));
        }
      ) cfg.servers
      // {
        gameservers-autostart = {
          description = "Start the game servers that are enabled";
          wantedBy = [ "multi-user.target" ];
          after = [
            "microvms.target"
            "network-online.target"
          ];
          wants = [ "network-online.target" ];
          serviceConfig = {
            Type = "oneshot";
            RemainAfterExit = true;
          };
          path = [
            pkgs.coreutils
            config.systemd.package
          ];
          script = ''
            # The first time each server is seen, and only then, turn its declared default
            # into a flag. After that the flag is the operator's, and a rebuild must not
            # resurrect a server that was disabled by hand. Tracked per server so that one
            # added later still gets its default. A server whose slot already has an
            # enabled occupant is not seeded over it: the operator's choice wins.
            mkdir -p ${stateDir}/seeded
            seed() {
              name="$1" default="$2"
              shift 2
              if [ -e ${stateDir}/seeded/"$name" ]; then return 0; fi
              if [ "$default" = 1 ]; then
                for rival in "$@"; do
                  if [ -e ${flagDir}/"$rival" ]; then default=0; fi
                done
              fi
              if [ "$default" = 1 ]; then
                touch ${flagDir}/"$name"
              fi
              touch ${stateDir}/seeded/"$name"
            }
            ${lib.concatStrings (
              lib.mapAttrsToList (name: srv: ''
                seed ${
                  lib.escapeShellArgs (
                    [
                      name
                      (if srv.autoStart then "1" else "0")
                    ]
                    ++ rivals name
                  )
                }
              '') cfg.servers
            )}
            # The single marker from before seeding was per server.
            rm -f ${stateDir}/.seeded
            for name in ${lib.escapeShellArgs names}; do
              if [ -e ${flagDir}/"$name" ]; then
                systemctl start --no-block "microvm@$name.service"
              fi
            done
          '';
        };
      };

    systemd.tmpfiles.rules = [
      "d ${stateDir} 0755 root root - -"
      # The operator's, so enabling a server needs no privilege beyond the polkit rule
      # below. A flag can only select among servers this file already declares.
      "d ${flagDir} 0755 ${operator} users - -"
    ];

    environment.systemPackages = [ gameserver ];

    # Let the operator start and stop exactly these units without a password prompt --
    # there is no polkit agent to answer one over SSH.
    security.polkit.extraConfig = ''
      polkit.addRule(function (action, subject) {
        var units = ${builtins.toJSON (map unit names)};
        if (
          action.id == "org.freedesktop.systemd1.manage-units" &&
          units.indexOf(action.lookup("unit")) >= 0 &&
          subject.user == "${operator}"
        ) {
          return polkit.Result.YES;
        }
      });
    '';

    # ---- host end of each tap --------------------------------------------------
    # Addressed by systemd-networkd, which is how microvm.nix expects taps to be handled.
    # The host's own uplink is networkd too (./configuration.nix); these links opt out
    # of its definition of "online" below, since a stopped server has no tap at all.
    systemd.network.enable = true;
    systemd.network.networks = lib.listToAttrs (
      map (
        slot:
        lib.nameValuePair "30-gameserver-slot${toString slot}" {
          matchConfig.Name = tap slot;
          address = [ "${hostAddr slot}/30" ];
          linkConfig.RequiredForOnline = "no";
          networkConfig = {
            ConfigureWithoutCarrier = true;
            IPv6AcceptRA = false;
            LinkLocalAddressing = "no";
          };
        }
      ) slots
    );

    boot.kernel.sysctl."net.ipv4.ip_forward" = 1;

    # ---- isolation and forwarding ----------------------------------------------
    # Hand-written rather than networking.nat, for two reasons: nat wants a named
    # external interface, and this box's port names are not something to hard-code;
    # and the rules that matter most here are the *denials*, which nat does not do.
    # Everything lives in gs-* chains so a reload replaces it wholesale.
    #
    #   gs-input    a guest may not talk to the host at all, except to answer a
    #               connection the host opened (the snapshot freeze/thaw request).
    #   gs-forward  a guest may answer anything, and open connections only to the
    #               public internet. Inbound, only forwarded ports reach a guest.
    #   nat         forwarded ports in, masquerade out.
    #
    # Guests are IPv4-only; the ip6tables rules just make sure of it.
    networking.firewall.extraCommands = ''
      gs_reset() {
        iptables -D INPUT -i vm-gs+ -j gs-input 2>/dev/null || true
        iptables -D FORWARD -j gs-forward 2>/dev/null || true
        iptables -t nat -D PREROUTING -j gs-prerouting 2>/dev/null || true
        iptables -t nat -D POSTROUTING -j gs-postrouting 2>/dev/null || true
        for c in gs-input gs-forward; do
          iptables -F "$c" 2>/dev/null || true
          iptables -X "$c" 2>/dev/null || true
        done
        for c in gs-prerouting gs-postrouting; do
          iptables -t nat -F "$c" 2>/dev/null || true
          iptables -t nat -X "$c" 2>/dev/null || true
        done
        ip6tables -D INPUT -i vm-gs+ -j DROP 2>/dev/null || true
        ip6tables -D FORWARD -i vm-gs+ -j DROP 2>/dev/null || true
        ip6tables -D FORWARD -o vm-gs+ -j DROP 2>/dev/null || true
      }
      gs_reset

      iptables -N gs-input
      iptables -A gs-input -m conntrack --ctstate ESTABLISHED,RELATED -j ACCEPT
      iptables -A gs-input -j DROP
      iptables -I INPUT 1 -i vm-gs+ -j gs-input

      iptables -N gs-forward
      iptables -A gs-forward -i vm-gs+ -m conntrack --ctstate ESTABLISHED,RELATED -j ACCEPT
      ${lib.concatMapStrings (net: ''
        iptables -A gs-forward -i vm-gs+ -d ${net} -j DROP
      '') forbidden}
      iptables -A gs-forward -i vm-gs+ -j ACCEPT
      iptables -A gs-forward -o vm-gs+ -m conntrack --ctstate ESTABLISHED,RELATED -j ACCEPT
      iptables -A gs-forward -o vm-gs+ -m conntrack --ctstate DNAT -j ACCEPT
      iptables -A gs-forward -o vm-gs+ -j DROP
      iptables -I FORWARD 1 -j gs-forward

      iptables -t nat -N gs-prerouting
      ${lib.concatMapStrings (rule: ''
        ${rule}
      '') forwards}
      iptables -t nat -I PREROUTING 1 -j gs-prerouting

      iptables -t nat -N gs-postrouting
      iptables -t nat -A gs-postrouting -s 10.77.0.0/16 ! -o vm-gs+ -j MASQUERADE
      iptables -t nat -I POSTROUTING 1 -j gs-postrouting

      ip6tables -I INPUT 1 -i vm-gs+ -j DROP
      ip6tables -I FORWARD 1 -i vm-gs+ -j DROP
      ip6tables -I FORWARD 1 -o vm-gs+ -j DROP
    '';
    networking.firewall.extraStopCommands = ''
      iptables -D INPUT -i vm-gs+ -j gs-input 2>/dev/null || true
      iptables -D FORWARD -j gs-forward 2>/dev/null || true
      iptables -t nat -D PREROUTING -j gs-prerouting 2>/dev/null || true
      iptables -t nat -D POSTROUTING -j gs-postrouting 2>/dev/null || true
      ip6tables -D INPUT -i vm-gs+ -j DROP 2>/dev/null || true
      ip6tables -D FORWARD -i vm-gs+ -j DROP 2>/dev/null || true
      ip6tables -D FORWARD -o vm-gs+ -j DROP 2>/dev/null || true
    '';
  };
}
