# Modded Minecraft servers, served natively by systemd — one unit per pack, generated
# from `publicMinecraft.servers.<name>`. Instances live in ./default.nix.
#
# Lineage: this is hosts/exodus/craftoria.nix generalized. That file was itself carried
# over from vaulthunters.nix (console FIFO + RCON + sandboxing) and promoted from a user
# unit to a system service. The tuning comments below that reference real crashes
# (perf_event_open SIGSYS, AF_NETLINK, THP vs G1) were earned across all three packs and
# are loader-agnostic hazards, which is exactly why they belong in the shared module now
# rather than being copy-pasted per pack.
#
# Packs are installed by hand into `serverDir` — typically via the pack's ServerStarter
# (server-setup-config.yaml / startserver.sh), which runs the loader installer with
# --installServer. Both NeoForge and Forge drop the same argfile layout, differing only in
# the vendor path segment, so `loaderPath` is all the launcher needs to adapt.
#
# The worlds are not greenfield (or won't be for long), which is why the readiness work
# below leans on *clean* SIGTERM saves, and why the world subvolumes and quiesced btrfs
# snapshots (see ../btrbk.nix) matter.
#
# Hang protection is deliberately NOT done here: Minecraft ships its own watchdog
# (max-tick-time in server.properties, 60s), which monitors the same main server thread a
# systemd WatchdogSec would and is strictly better at it -- it fires sooner and writes a
# crash report naming the wedged thread, where SIGABRT from systemd gives you a core at
# best. It kills the JVM, so Restart=on-failure already picks up the pieces. A second
# watchdog here would only ever be the slower, blinder of the two. The preflight asserts
# max-tick-time is still enabled, because server.properties is not managed by Nix.
{
  config,
  lib,
  pkgs,
  ...
}:

let
  cfg = config.publicMinecraft;

  # `config` here is the *submodule's* own config, not the host's — that is what lets
  # worldSubvolume below derive from a sibling option.
  serverOpts =
    { config, ... }:
    {
      options = {
        description = lib.mkOption {
          type = lib.types.str;
          example = "Minecraft server (Craftoria 2, NeoForge 26.1.2.76)";
          description = "systemd unit description — name the pack and its loader version.";
        };

        # The live server directory: pack files, mods, libraries, config, world, logs,
        # user_jvm_args.txt, server.properties, eula.txt. Populate it by running the pack's
        # ServerStarter here, or by running the loader installer directly into it. The
        # preflight fails the start until the loader argfile is in place.
        serverDir = lib.mkOption {
          type = lib.types.str;
          description = ''
            Absolute path to the installed pack. The directory itself is created (owner
            `user`) by tmpfiles; populating it with the pack is a manual step.

            Every ancestor must already exist and be owned by `user` (or by root the whole
            way down): systemd-tmpfiles refuses an "unsafe path transition" from a
            user-owned directory into a root-owned one, and it fails the entire
            tmpfiles run when it hits one -- not just this line.
          '';
        };

        jre = lib.mkOption {
          type = lib.types.package;
          example = lib.literalExpression "pkgs.jdk21_headless";
          description = ''
            The JRE this pack requires — check the pack README, a mismatch is a hard
            failure at class-load time. Headless, from the system closure, so a desktop
            JDK upgrade can't move it.
          '';
        };

        user = lib.mkOption {
          type = lib.types.str;
          default = "shane";
          description = "Account that owns the world/config/log files and runs the JVM.";
        };

        # Minecraft Java. A listener on the normal INPUT path, so the NixOS firewall
        # genuinely governs it. It must match server-port in server.properties, which the
        # preflight asserts. Packs are allowed to SHARE a port (see ./default.nix): when
        # only one may run at a time anyway, sharing means the second start dies loudly on
        # "Failed to bind" instead of quietly succeeding and eating the RAM.
        port = lib.mkOption {
          type = lib.types.port;
          default = 25565;
          description = "server-port, opened in the firewall.";
        };

        # RCON is deliberately NOT opened in the firewall: loopback only. Keep it that way
        # — the password sits in plaintext in server.properties.
        rconPort = lib.mkOption {
          type = lib.types.port;
          default = 25575;
          description = ''
            rcon.port. Loopback only, and it must match server.properties — the preflight
            fails otherwise. Packs sharing a port is supported; `<name>-console` refuses to
            talk to a port its own unit isn't holding, so a shared port cannot become
            cross-talk.
          '';
        };

        loaderPath = lib.mkOption {
          type = lib.types.str;
          default = "net/neoforged/neoforge";
          example = "net/minecraftforge/forge";
          description = ''
            Vendor path under `libraries/` holding `<version>/unix_args.txt`. Globbed at
            runtime rather than version-pinned, so a pack update that bumps the loader
            needs no nix edit.
          '';
        };

        autoStart = lib.mkOption {
          type = lib.types.bool;
          default = true;
          description = ''
            Whether the unit is wantedBy multi-user.target. A modded server's heap is
            large enough that on a memory-constrained host only one pack can be resident
            at a time; the others are started by hand.
          '';
        };

        snapshotWorld = lib.mkOption {
          type = lib.types.bool;
          default = true;
          description = ''
            Include this world in the btrbk timeline (../btrbk.nix) and quiesce it around
            each run. Only turn this off for a world you would not miss — the static pack
            tree is never snapshotted either way, being re-downloadable from CurseForge.
          '';
        };

        worldSubvolume = lib.mkOption {
          type = lib.types.str;
          readOnly = true;
          default = builtins.substring 1 (-1) config.serverDir + "/world";
          defaultText = lib.literalMD "`serverDir` minus its leading slash, plus `/world`";
          description = ''
            The world subvolume in the volume-relative form btrbk wants. Read-only: it is
            the seam that keeps ../btrbk.nix from drifting away from serverDir.
          '';
        };
      };
    };

  # Everything a single server needs: five wrapper scripts, a socket unit and a service
  # unit. `rec` because the launcher forks the readiness reporter, and both the reporter
  # and the snapshot hooks drive the console.
  build = name: srv: rec {
    inherit (srv) serverDir;

    argfileGlob = "${serverDir}/libraries/${srv.loaderPath}/*/unix_args.txt";

    # Locate the loader argfile at runtime instead of pinning its version (see
    # loaderPath). Execs java as the final step so the JVM stays PID 1 of the unit --
    # signals reach it directly and StandardInput=socket's fd is inherited.
    launcher = pkgs.writeShellApplication {
      name = "${name}-launch";
      runtimeInputs = [ srv.jre ];
      text = ''
        cd "${serverDir}" || exit 1
        shopt -s nullglob
        matches=( ${argfileGlob} )
        if [ "''${#matches[@]}" -eq 0 ]; then
          echo "no unix_args.txt under ${serverDir}/libraries/${srv.loaderPath}/*/ -- run the server installer" >&2
          exit 1
        fi
        # Fork the readiness reporter as a cgroup SIBLING before the exec: the `&` child is
        # already a separate process when `exec` replaces this shell with java, so java keeps
        # the unit's main PID (signals reach it directly, StandardInput=socket's fd is
        # inherited) while the reporter sends READY=1 on its behalf under Type=notify +
        # NotifyAccess=all. It exits as soon as the server answers, leaving java alone in the
        # cgroup. If it were to die before that, the unit never reports ready and fails at
        # TimeoutStartSec -- the server itself keeps running until systemd tears it down.
        ${ready}/bin/${name}-ready &

        # Memory/GC tuning stays in user_jvm_args.txt, under your control (set -Xmx/-Xms
        # there, per what the pack recommends).
        exec java @user_jvm_args.txt "@''${matches[0]}" nogui
      '';
    };

    # Asserts what NixOS can't guarantee before the JVM starts: an accepted EULA, a
    # writable server dir, that the pack was actually installed (loader argfile present),
    # and -- with more than one pack on the host -- that this server's ports are the ones
    # this unit thinks they are. THP stays a cheap belt-and-suspenders check.
    preflight = pkgs.writeShellApplication {
      name = "${name}-preflight";
      runtimeInputs = with pkgs; [
        coreutils
        gnugrep
        gnused
      ];
      bashOptions = [
        "nounset"
        "pipefail"
      ];
      text = ''
        fails=0
        bad()  { printf '  [FAIL] %s\n' "$1"; fails=$((fails+1)); }
        warn() { printf '  [warn] %s\n' "$1"; }
        good() { printf '  [ ok ] %s\n' "$1"; }

        props="${serverDir}/server.properties"
        # tail -n1 (not head) so a closed pipe can't SIGPIPE sed into a pipefail exit.
        getprop() { sed -n "s/^$1=//p" "$props" 2>/dev/null | tr -d '\r' | tail -n1; }

        echo "${name} preflight"

        thp=/sys/kernel/mm/transparent_hugepage/enabled
        if [ -r "$thp" ]; then
          cur=$(sed -n 's/.*\[\(.*\)\].*/\1/p' "$thp")
          if [ "$cur" = "always" ]; then
            bad "THP is 'always' -- G1 can corrupt its mark bitmaps. systemd.tmpfiles should force madvise."
          else
            good "THP = $cur"
          fi
        else
          warn "cannot read $thp"
        fi

        if grep -qi '^eula=true' "${serverDir}/eula.txt" 2>/dev/null; then
          good "EULA accepted"
        else
          bad "eula=true missing from ${serverDir}/eula.txt"
        fi

        if [ -w "${serverDir}" ]; then
          good "server dir writable"
        else
          bad "${serverDir} missing or not writable"
        fi

        shopt -s nullglob
        matches=( ${argfileGlob} )
        if [ "''${#matches[@]}" -gt 0 ]; then
          good "loader installed ($(basename "$(dirname "''${matches[0]}")"))"
        else
          bad "no unix_args.txt under libraries/${srv.loaderPath} -- install the server pack + run its installer"
        fi

        # java @user_jvm_args.txt fails hard if the file is absent, and it's where -Xmx
        # lives -- a modded pack won't run on the default heap anyway. ServerStarter does
        # not create it (the loader installer would), so check for it explicitly.
        if [ -r "${serverDir}/user_jvm_args.txt" ]; then
          good "user_jvm_args.txt present"
        else
          bad "no ${serverDir}/user_jvm_args.txt -- create it with your -Xmx/-Xms (the launcher reads it)"
        fi

        # RCON is load-bearing, not just for the console: the Type=notify readiness edge
        # drives off `${name}-console list` (RCON runs on the main server thread, so a reply
        # means the server is genuinely ticking). Without it the unit would never reach READY
        # and would fail at TimeoutStartSec 20 minutes later -- assert it here so the failure
        # is fast and legible instead.
        rcon_pw=$(getprop rcon.password)
        if [ "$(getprop enable-rcon)" = "true" ] && [ -n "$rcon_pw" ]; then
          good "RCON enabled (readiness probe)"
        else
          bad "RCON not usable in $props -- need enable-rcon=true and a non-empty rcon.password (the readiness probe requires it)"
        fi

        # Port agreement between this out-of-store file and the module. server.properties is
        # regenerated by the server, so a pack update or a fresh install can move these back
        # to the pack's defaults underneath us. Both are hard fails:
        #   - server-port: the firewall opens only the declared port, so a drifted one is a
        #     server nobody outside the box can reach, with no error anywhere.
        #   - rcon.port: everything automated here (readiness probe, btrbk save-off/save-on)
        #     dials the DECLARED port. If the server is actually listening elsewhere, the
        #     unit never reaches READY and dies at TimeoutStartSec 20 minutes later.
        # Packs sharing a port is fine and deliberate here (see ./default.nix); what is not
        # fine is a pack disagreeing with its own unit.
        declared_port=$(getprop server-port)
        if [ "$declared_port" = "${toString srv.port}" ]; then
          good "server-port=${toString srv.port}"
        else
          bad "server-port=''${declared_port:-unset} in $props but this unit declares ${toString srv.port} (and opens only that in the firewall)"
        fi

        declared_rcon=$(getprop rcon.port)
        if [ "$declared_rcon" = "${toString srv.rconPort}" ]; then
          good "rcon.port=${toString srv.rconPort}"
        else
          bad "rcon.port=''${declared_rcon:-unset} in $props but the console/readiness probe dials ${toString srv.rconPort}"
        fi

        # Minecraft's own watchdog is the ONLY hang protection here (see the header) -- there
        # is deliberately no systemd WatchdogSec to fall back on. server.properties is
        # regenerated by the server and not managed by Nix, and plenty of modpacks ship
        # max-tick-time=-1 to dodge false positives during chunk gen, so a pack update could
        # silently disable it. Warn rather than fail: a disabled watchdog is a degraded
        # server, not an unstartable one, and failing the boot over it would be worse.
        mtt=$(getprop max-tick-time)
        case "''${mtt:-unset}" in
          unset | -1 | 0)
            warn "max-tick-time=''${mtt:-unset} -- Minecraft's hang watchdog is OFF and nothing else covers it; a wedged tick will hang indefinitely"
            ;;
          *) good "max-tick-time=$mtt (hang watchdog active)" ;;
        esac

        good "JRE ${srv.jre}/bin/java"

        if [ "$fails" -gt 0 ]; then
          echo "preflight: $fails failed"
          exit 1
        fi
        echo "preflight: ok"
      '';
    };

    # Interactive command console over Minecraft's built-in RCON. This does NOT disturb
    # the PID-1/clean-shutdown design: RCON is just a TCP listener inside the game, so
    # the FIFO, journal output, and SIGTERM-save path all stay exactly as they are.
    #
    # The secret lives only in serverDir/server.properties (out of the store -- this repo
    # stays public); the wrapper reads it at call time and keeps it off argv via
    # MCRCON_PASS. Enable it once in server.properties (that file is regenerated by the
    # server, not managed by Nix):
    #     enable-rcon=true
    #     rcon.port=<this server's rconPort>
    #     rcon.password=<pick-one>
    # The port is taken from the module, not the file, so the console can't be talked into
    # dialing somewhere else; the preflight fails if the two disagree.
    #     ${name}-console          # interactive prompt
    #     ${name}-console list     # one-shot command: prints the reply and exits
    # mcrcon runs each ARGUMENT as its own rcon command, so a multi-word command must be a
    # single quoted word or it silently becomes several commands:
    #     ${name}-console 'save-all flush'    # right
    #     ${name}-console save-all flush      # WRONG: `save-all`, then a bogus `flush`
    console = pkgs.writeShellApplication {
      name = "${name}-console";
      runtimeInputs = with pkgs; [
        mcrcon
        coreutils
        gnused
        systemd
      ];
      text = ''
        # Own the port before dialing it. Packs on this host deliberately SHARE
        # ${toString srv.rconPort} (only one runs at a time), so "something answered on
        # RCON" is NOT proof it was this pack -- `${name}-console save-all` against another
        # pack's running server would report a cheerful success while saving the wrong
        # world, and the btrbk freeze hook would be quiescing the wrong world too. The unit
        # state is the only honest answer to "whose port is this", so check it first, before
        # anything reads server.properties -- a stopped pack should say so, not complain
        # about a file.
        #
        # `activating` counts: the readiness probe runs from inside the launcher precisely
        # while the unit is still activating, and it is the caller that ends that state.
        state="$(systemctl is-active ${name} || true)"
        case "$state" in
          active | activating) ;;
          *)
            echo "${name}-console: ${name}.service is '$state' -- refusing to dial 127.0.0.1:${toString srv.rconPort}, another pack may be holding it" >&2
            exit 1
            ;;
        esac

        props="${serverDir}/server.properties"
        if [ ! -r "$props" ]; then
          echo "${name}-console: cannot read $props (is the server installed?)" >&2
          exit 1
        fi
        # tail -n1 (not head) so a closed pipe can't SIGPIPE sed into a pipefail exit.
        getprop() { sed -n "s/^$1=//p" "$props" | tr -d '\r' | tail -n1; }

        if [ "$(getprop enable-rcon)" != "true" ]; then
          echo "${name}-console: enable-rcon is not 'true' in $props" >&2
          exit 1
        fi
        MCRCON_PASS="$(getprop rcon.password)"
        if [ -z "$MCRCON_PASS" ]; then
          echo "${name}-console: rcon.password is empty in $props" >&2
          exit 1
        fi
        export MCRCON_PASS

        # No args -> interactive terminal mode; args -> run them and exit.
        if [ "$#" -eq 0 ]; then
          exec mcrcon -H 127.0.0.1 -P ${toString srv.rconPort} -t
        fi
        exec mcrcon -H 127.0.0.1 -P ${toString srv.rconPort} "$@"
      '';
    };

    # Readiness reporter, one-shot. Forked as a cgroup sibling of the JVM (see the launcher)
    # so it can drive the unit's Type=notify state while java stays PID 1. The probe is RCON
    # `list`: RCON commands execute on the server's MAIN thread, so a reply proves the server
    # is actually ticking -- a strictly better signal than a log grep or a Server List Ping,
    # both of which a deadlocked main thread can still satisfy. `timeout` is what keeps the
    # probe from blocking forever: a wedged main thread still ACCEPTS the RCON connection but
    # never replies, so mcrcon would hang without it.
    ready = pkgs.writeShellApplication {
      name = "${name}-ready";
      runtimeInputs = with pkgs; [
        coreutils
        systemd
      ];
      text = ''
        probe() { timeout 10 ${console}/bin/${name}-console list >/dev/null 2>&1; }

        # Wait for the first successful tick, report readiness, exit. That edge is the whole
        # job: it makes `activating` -> `active` mean "accepting players" rather than "execve
        # returned", and bounds a server that never comes up at TimeoutStartSec.
        #
        # Nothing polls after this on purpose. Hang detection is Minecraft's, via max-tick-time
        # (see the header), and it reacts at 60s -- faster than any loop worth running here.
        # A liveness loop would publish a status nobody acts on, keep two processes alive for
        # the life of the server, and log an RCON connect every time it ran.
        until probe; do sleep 5; done
        systemd-notify --ready
      '';
    };

    # Quiesce the world for the duration of a btrbk run. A btrfs snapshot is atomic, so an
    # un-quiesced one is *crash-consistent*: restoring it is equivalent to restoring from a
    # kill -9, with chunks still live in the JVM heap and .mca regions half-written.
    # `save-off` + `save-all flush` turns that into a real checkpoint.
    #
    # These hang off btrbk-local.service (generated by ../btrbk.nix) rather than being
    # helpers run by hand, because the weekly timer fires that same unit -- so the scheduled
    # snapshots get the identical treatment. btrbk has no native pre/post-snapshot hooks
    # (only the --preserve* flags affect a run), so systemd's Exec hooks are the seam. One
    # freeze/thaw pair is generated per snapshotted server and they run in sequence.
    #
    # Caveat: the window spans the WHOLE btrbk run, retention deletes included, not just the
    # snapshot ioctl. Deletes are fast and this host snapshots a handful of subvolumes, so it
    # is seconds -- but it is autosave-off seconds, and a crash inside it loses more than a
    # crash outside it would.
    snapshotSaves = pkgs.writeShellApplication {
      name = "${name}-snapshot-saves";
      runtimeInputs = with pkgs; [
        coreutils
        gnugrep
        systemd
      ];
      text = ''
        mode="''${1:?usage: ${name}-snapshot-saves freeze|thaw}"

        # Never fail the btrbk run. home still needs its snapshot even when the server is down
        # or RCON is wedged, and a stopped server has already flushed on SIGTERM -- so a
        # missing server is a no-op, not an error. That case is the NORM for a pack with
        # autoStart = false. Every path below exits 0 on purpose.
        if ! systemctl is-active --quiet ${name}; then
          echo "${name} not active -- world already at rest, skipping $mode"
          exit 0
        fi

        # mcrcon exits 0 whenever RCON *accepted* the line, so an in-game "Unknown command"
        # still looks like success (verified: `${name}-console tps` returns 0). Match the
        # server's reply text instead of $?, or these hooks would silently do nothing.
        #
        # Rejecting the parser error explicitly, on top of matching $want, is not redundant:
        # it is what catches a command that got MANGLED rather than refused. `save-all flush`
        # sent as two argv words ran `save-all` + `flush`, and the bare `save-all` still
        # printed "Saved the game" -- so $want matched while the flush silently never
        # happened. A $want match is not proof the command you meant is the command that ran.
        say() {
          want="$1"
          shift
          out="$(timeout 30 ${console}/bin/${name}-console "$@" 2>&1)" || out="<rcon call failed>"
          printf '  %s -> %s\n' "$*" "$out"
          if printf '%s' "$out" | grep -qiF 'Unknown or incomplete command'; then
            return 1
          fi
          printf '%s' "$out" | grep -qiE "$want"
        }

        case "$mode" in
          freeze)
            # save-off first so autosave cannot race the flush. A failure here only downgrades
            # the snapshot to crash-consistent -- today's status quo -- so warn and let btrbk
            # run anyway: a degraded backup beats a skipped one.
            say 'disabled|already turned off' save-off ||
              echo "WARNING: save-off did not take -- snapshot will be crash-consistent"
            # ONE argv word. mcrcon runs each argument as a SEPARATE rcon command, so
            # `save-all flush` unquoted is `save-all` then a bogus `flush` -- you get an
            # ordinary save, not the forced synchronous flush this hook exists for.
            say 'Saved the game' 'save-all flush' ||
              echo "WARNING: save-all flush did not take -- snapshot will be crash-consistent"
            ;;
          thaw)
            # ExecStopPost, so this runs even when btrbk fails or is interrupted. Leaving
            # autosave off until the next restart is far worse than a failed snapshot -- it
            # silently widens every subsequent crash into hours of lost world -- so retry
            # before giving up, and give up LOUDLY.
            for _ in 1 2 3; do
              if say 'enabled|already turned on' save-on; then
                exit 0
              fi
              sleep 5
            done
            echo "ERROR: autosave still off -- run '${name}-console save-on' by hand NOW"
            ;;
        esac
        exit 0
      '';
    };

    # Console input FIFO. systemd holds the read end open so a writer closing does not
    # EOF the server into a shutdown:
    #   echo "list" > /run/<name>.stdin
    # SocketUser keeps the node writable by the server's account (system sockets are
    # created owned by root by default). Output is on the journal
    # (`journalctl -u <name> -f`). For an interactive command prompt with inline replies,
    # prefer `<name>-console` (RCON) above.
    socket = {
      description = "${srv.description} console FIFO";
      partOf = [ "${name}.service" ];
      socketConfig = {
        # %t is /run for system units (was /run/user/1000 under the user manager).
        ListenFIFO = "%t/${name}.stdin";
        SocketUser = srv.user;
        SocketMode = "0600";
        RemoveOnStop = true;
        Service = "${name}.service";
      };
    };

    # A system unit running as User=<user>: the world/config/log files stay user-owned
    # exactly as they were under the old user unit, but the server's lifecycle belongs to
    # the host (boots with the machine, lives under the system manager) instead of a login
    # session — which is what it always semantically was, a public boot-critical daemon.
    # This is why `linger` is gone: it only existed to force user units to start at boot.
    service = {
      inherit (srv) description;
      requires = [ "${name}.socket" ];
      after = [
        "${name}.socket"
        "network-online.target"
      ];
      wants = [ "network-online.target" ];
      # No wantedBy when autoStart is off: the socket unit has no wantedBy of its own
      # either (it is pulled in by this unit's Requires=), so the pair stays entirely
      # dormant until `systemctl start <name>`.
      wantedBy = lib.optional srv.autoStart "multi-user.target";

      # Bound the restart loop: default 5/10s can't trip a 30s RestartSec, so a
      # repeating crash would restart forever, each risking a half-written world.
      startLimitIntervalSec = 3600;
      startLimitBurst = 3;

      serviceConfig = {
        # Type=notify: the unit stays "activating" through the multi-minute modpack load and
        # only flips to "active" once <name>-ready (forked by the launcher) confirms the
        # server is ticking and sends READY=1. NotifyAccess=all because that reporter is a
        # cgroup sibling, not the main PID. This is what makes `systemctl`/Beszel state honest
        # instead of reporting "started" at execve.
        Type = "notify";
        NotifyAccess = "all";
        User = srv.user;
        WorkingDirectory = serverDir;

        # Fail fast with a readable reason instead of a confusing JVM error minutes in.
        ExecStartPre = "${preflight}/bin/${name}-preflight";
        # Resolves the installed loader version, then execs java (JVM becomes PID 1).
        ExecStart = "${launcher}/bin/${name}-launch";

        # Console in via the FIFO socket, logs out to the journal.
        StandardInput = "socket";
        StandardOutput = "journal";
        StandardError = "journal";

        # Clean SIGTERM shutdown: the JVM runs Minecraft's save hook and exits
        # 128+15=143. Without SuccessExitStatus systemd would mark a clean stop
        # 'failed'. A real crash still fails correctly (SIGSEGV = code=killed).
        KillSignal = "SIGTERM";
        TimeoutStopSec = 90;
        SuccessExitStatus = 143;

        # Modded startup is slow, and under Type=notify this bound is load-bearing: the unit
        # fails if <name>-ready never reports READY=1 within it (server never came up).
        TimeoutStartSec = 1200;
        # No WatchdogSec on purpose -- see the header: Minecraft's max-tick-time watches the
        # same main thread, fires at 60s instead of 150s, and leaves a crash report instead of
        # a core. Its kill lands here as an ordinary JVM failure, which is what this restarts.
        #
        # startLimitBurst caps the loop either way: on the 3rd failure in the hour the unit
        # drops to failed and stays there (red in Beszel), so a deterministic hang costs 3
        # unclean kills, not an unbounded thrash against the world.
        Restart = "on-failure";
        RestartSec = 30;

        # Journald drops lines under the large startup burst; these are an UNCONFIRMED
        # mitigation. logs/latest.log in the server dir is authoritative.
        LogRateLimitIntervalSec = 0;
        LogRateLimitBurst = 0;

        # ---- sandboxing ------------------------------------------------------------
        NoNewPrivileges = true;
        CapabilityBoundingSet = "";
        UMask = "0077";

        # Own service keyring instead of sharing one: the JVM uses no keyring material,
        # so this is free isolation.
        KeyringMode = "private";

        # Home replaced with an empty tmpfs, only this server's dir bound back in: the JVM
        # can't see ~/.ssh, ~/.config, or -- now that there is more than one pack -- the
        # other server's world. /nix/store stays readable under strict (ro, not hidden), so
        # the JRE and launcher resolve.
        ProtectHome = "tmpfs";
        BindPaths = [ serverDir ];
        ProtectSystem = "strict";
        PrivateTmp = true;
        PrivateDevices = true;
        ProtectProc = "invisible";
        ProtectClock = true;
        ProtectHostname = true;
        ProtectKernelTunables = true;
        ProtectKernelModules = true;
        ProtectKernelLogs = true;
        ProtectControlGroups = true;

        # Reachable as a system unit (a user unit couldn't set these up). PrivateIPC
        # gives the JVM its own System V IPC / POSIX message-queue namespace -- the server
        # uses neither, so it is free isolation. PrivateUsers maps only the service user +
        # root into a user namespace (every other host UID appears as nobody), so a
        # compromise can't reach files owned by other users and any setuid bit in the
        # closure is inert; the user-owned world/config files stay writable because that
        # user is the mapped one.
        #
        # A user namespace *can* block perf_event_open -- the syscall kept below for
        # spark's async-profiler -- but verified on this host it does not: `spark
        # profiler` reports engine "(async)" and completes a run under PrivateUsers.
        # Breadcrumb: if a future kernel/userns tightening makes spark fall back off the
        # async engine, PrivateUsers is the first suspect; drop it and keep PrivateIPC.
        PrivateIPC = true;
        PrivateUsers = true;

        RestrictNamespaces = true;
        RestrictRealtime = true;
        RestrictSUIDSGID = true;
        LockPersonality = true;
        SystemCallArchitectures = "native";
        # @system-service is an allow-list, and it omits perf_event_open (x86_64
        # syscall 298) -- which the bundled spark profiler calls via async-profiler.
        # Under seccomp's default kill action that surfaced as SIGSYS (code=dumped,
        # status=31/SYS) about a minute into startup. Allow it explicitly so spark
        # works, and make any *other* unlisted syscall return EPERM instead of killing
        # the JVM: a large mod pack is too broad a surface to enumerate up front, and a
        # soft EPERM lets a mod degrade rather than crash-loop a half-generated world.
        SystemCallFilter = [
          "@system-service"
          "perf_event_open"
        ];
        SystemCallErrorNumber = "EPERM";
        # AF_NETLINK is not optional: java.net.NetworkInterface enumerates interfaces
        # over netlink while the server binds its listener.
        RestrictAddressFamilies = [
          "AF_UNIX"
          "AF_INET"
          "AF_INET6"
          "AF_NETLINK"
        ];

        # Deliberately NOT set (each silently breaks a JVM): MemoryDenyWriteExecute
        # (the JIT maps its code cache W+X), ProcSubset=pid (hides /proc/meminfo +
        # cpuinfo the JVM reads for ergonomics), MemoryMax (a too-tight ceiling gives
        # OOM kills that mimic a crash -- leave it to -Xmx in user_jvm_args.txt).
      };
    };
  };

  built = lib.mapAttrs build cfg.servers;
  snapshotted = lib.filterAttrs (_: srv: srv.snapshotWorld) cfg.servers;
in
{
  options.publicMinecraft.servers = lib.mkOption {
    type = lib.types.attrsOf (lib.types.submodule serverOpts);
    default = { };
    description = ''
      Modded Minecraft servers, keyed by unit name. Each gets a systemd service, a console
      FIFO socket at /run/<name>.stdin, and an RCON wrapper on PATH as `<name>-console`.
    '';
  };

  config = lib.mkIf (cfg.servers != { }) {
    # ---- host prerequisites, declarative ---------------------------------------
    systemd.tmpfiles.rules = [
      # Keep transparent hugepages off `always`. This started as an ATM10/Java-21
      # incident (G1 SIGSEGV in G1RegionMarkStatsCache), but THP=always corrupting G1's
      # mark bitmaps is a general modded-server hazard, and the rule is free. madvise,
      # not never -- so still never add -XX:+UseTransparentHugePages / -XX:+UseLargePages
      # to user_jvm_args.txt. Stated once for the host, not once per server: identical
      # duplicate tmpfiles lines are a warning at best.
      "w! /sys/kernel/mm/transparent_hugepage/enabled - - - - madvise"
    ]
    ++ lib.concatLists (
      lib.mapAttrsToList (_: srv: [
        # The pack tree itself: a plain directory, populated by hand.
        "d ${srv.serverDir} 0755 ${srv.user} users - -"
        # The world as its own NOCOW subvolume, created empty *before* first launch so the
        # .mca region files never fragment under CoW -- NOCOW is inherited only by files
        # created after the attribute is set, which is why creating it here (empty, at boot,
        # ahead of the unit) is the only way to get it right without a manual ritual. `v`
        # makes a btrfs subvolume and only acts when the path doesn't already exist, so the
        # live craftoria world is untouched; on a non-btrfs filesystem it degrades to a
        # plain directory. It also guarantees btrbk's subvolume list can't name something
        # that doesn't exist yet, which would fail the whole run -- home included.
        #
        # Resetting a world later is still NOT a plain `rm -rf world` -- that either fails
        # on the subvolume or removes it and a reflexive `mkdir world` silently gives back a
        # CoW directory. Delete the subvolume and let these lines recreate it:
        #     systemctl stop <name>
        #     btrfs subvolume delete <serverDir>/world
        #     systemd-tmpfiles --create        # remakes the subvolume, NOCOW, correct owner
        "v ${srv.serverDir}/world 0755 ${srv.user} users - -"
        "h ${srv.serverDir}/world - - - - +C"
      ]) cfg.servers
    );

    # unique because packs are allowed to share a port (see ./default.nix).
    networking.firewall.allowedTCPPorts = lib.unique (
      lib.mapAttrsToList (_: srv: srv.port) cfg.servers
    );

    # `<name>-console` for an interactive/one-shot RCON prompt; raw mcrcon for
    # scripting. e2fsprogs supplies chattr/lsattr -- not in the base system profile, and
    # needed to check the NOCOW state of a world subvolume (`lsattr -d <dir>`).
    environment.systemPackages = lib.mapAttrsToList (_: b: b.console) built ++ [
      pkgs.mcrcon
      pkgs.e2fsprogs
    ];

    systemd.sockets = lib.mapAttrs (_: b: b.socket) built;

    systemd.services = lib.mapAttrs (_: b: b.service) built // {
      # ---- clean snapshots -----------------------------------------------------
      # Extends the unit generated by services.btrbk.instances.local in ../btrbk.nix. Living
      # here, not there, keeps the RCON plumbing next to the console/probe that share it; the
      # coupling is one-directional and ../btrbk.nix carries a pointer back.
      #
      # `+` runs these as root: btrbk-local.service is User=btrbk, which cannot traverse
      # /home/<user> to read rcon.password out of server.properties.
      #
      # ExecStopPost (not ExecStop) because it must also run when btrbk fails or is killed --
      # that is the whole reason the thaw is a systemd hook instead of a line in a script.
      btrbk-local.serviceConfig = {
        ExecStartPre = lib.mapAttrsToList (
          name: _: "+${built.${name}.snapshotSaves}/bin/${name}-snapshot-saves freeze"
        ) snapshotted;
        ExecStopPost = lib.mapAttrsToList (
          name: _: "+${built.${name}.snapshotSaves}/bin/${name}-snapshot-saves thaw"
        ) snapshotted;
      };
    };
  };
}
