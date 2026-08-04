# Craftoria 2 (NeoForge 26.1.2.76, Java 25) Minecraft server, served natively by
# systemd. Successor to the Vault Hunters setup this replaced; the systemd skeleton
# (console FIFO + RCON + sandboxing) is carried over from vaulthunters.nix (and
# promoted from a user unit to a system service — see the service section below),
# but the runtime is different: NeoForge on Java 25, not Forge
# 1.18.2 on Java 17. The tuning comments below that reference real crashes
# (perf_event_open SIGSYS, AF_NETLINK) were earned on the older packs and are kept
# because the hazards are loader-agnostic.
#
# The pack is installed via TeamAOF's ServerStarter (server-setup-config.yaml in the
# server dir), which runs the NeoForge installer with --installServer. That drops the
# same argfile layout Forge used, just under net/neoforged instead of
# net/minecraftforge, so the launcher/preflight below only change the glob.
#
# The world is no longer greenfield -- there is a live world worth keeping now, which is
# why the readiness work below leans on *clean* SIGTERM saves, and why the world reset
# ritual (below) and the quiesced btrfs snapshots (see btrbk.nix) matter.
#
# Hang protection is deliberately NOT done here: Minecraft ships its own watchdog
# (max-tick-time in server.properties, 60s), which monitors the same main server thread a
# systemd WatchdogSec would and is strictly better at it -- it fires sooner and writes a
# crash report naming the wedged thread, where SIGABRT from systemd gives you a core at
# best. It kills the JVM, so Restart=on-failure already picks up the pieces. A second
# watchdog here would only ever be the slower, blinder of the two. The preflight asserts
# max-tick-time is still enabled, because server.properties is not managed by Nix.
{
  pkgs,
  ...
}:

let
  # The live server directory: pack files, mods, libraries, config, world, logs,
  # user_jvm_args.txt, server.properties, eula.txt. Populate it by running the pack's
  # ServerStarter (see startserver.sh / server-setup-config.yaml) here, or by running
  # the NeoForge installer directly into it. The preflight fails the start until the
  # loader argfile is in place.
  #
  # btrfs: world/ is (or should be) its own NOCOW subvolume, created greenfield before
  # first launch so the .mca region files never fragment under CoW. Resetting the world
  # later is NOT a plain `rm -rf world` -- that either fails on the subvolume or removes
  # it and a reflexive `mkdir world` silently gives back a CoW directory. The correct
  # reset is:
  #     btrfs subvolume delete world
  #     btrfs subvolume create world
  #     chattr +C world              # NOCOW is inherited only by files created after
  serverDir = "/home/shane/Servers/minecraft/craftoria2";

  # Java 25 -- Craftoria 2 requires it (see the pack README). Headless from the system
  # closure, not the desktop JDK.
  jre = pkgs.jdk25_headless;

  # Locate the NeoForge argfile at runtime instead of pinning its version. NeoForge
  # writes libraries/net/neoforged/neoforge/<version>/unix_args.txt at install time;
  # globbing it means a pack update that bumps NeoForge needs no nix edit. Execs java
  # as the final step so the JVM stays PID 1 of the unit -- signals reach it directly
  # and StandardInput=socket's fd is inherited.
  launcher = pkgs.writeShellApplication {
    name = "craftoria-launch";
    runtimeInputs = [ jre ];
    text = ''
      cd "${serverDir}" || exit 1
      shopt -s nullglob
      matches=( "${serverDir}"/libraries/net/neoforged/neoforge/*/unix_args.txt )
      if [ "''${#matches[@]}" -eq 0 ]; then
        echo "no NeoForge unix_args.txt under ${serverDir}/libraries/net/neoforged/neoforge/*/ -- run the server installer" >&2
        exit 1
      fi
      # Fork the readiness reporter as a cgroup SIBLING before the exec: the `&` child is
      # already a separate process when `exec` replaces this shell with java, so java keeps
      # the unit's main PID (signals reach it directly, StandardInput=socket's fd is
      # inherited) while the reporter sends READY=1 on its behalf under Type=notify +
      # NotifyAccess=all. It exits as soon as the server answers, leaving java alone in the
      # cgroup. If it were to die before that, the unit never reports ready and fails at
      # TimeoutStartSec -- the server itself keeps running until systemd tears it down.
      ${ready}/bin/craftoria-ready &

      # Memory/GC tuning stays in user_jvm_args.txt, under your control (the pack ships
      # 5G max / 3G min, G1GC -- set those there).
      exec java @user_jvm_args.txt "@''${matches[0]}" nogui
    '';
  };

  # Asserts what NixOS can't guarantee before the JVM starts: an accepted EULA, a
  # writable server dir, and that the pack was actually installed (NeoForge argfile
  # present). THP stays a cheap belt-and-suspenders check.
  preflight = pkgs.writeShellApplication {
    name = "craftoria-preflight";
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

      echo "craftoria preflight"

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
      matches=( "${serverDir}"/libraries/net/neoforged/neoforge/*/unix_args.txt )
      if [ "''${#matches[@]}" -gt 0 ]; then
        good "NeoForge installed ($(basename "$(dirname "''${matches[0]}")"))"
      else
        bad "no NeoForge unix_args.txt -- install the server pack + run its installer"
      fi

      # java @user_jvm_args.txt fails hard if the file is absent, and it's where -Xmx
      # lives -- a modded pack won't run on the default heap anyway. ServerStarter does
      # not create it (the NeoForge installer would), so check for it explicitly.
      if [ -r "${serverDir}/user_jvm_args.txt" ]; then
        good "user_jvm_args.txt present"
      else
        bad "no ${serverDir}/user_jvm_args.txt -- create it with your -Xmx/-Xms (the launcher reads it)"
      fi

      # RCON is load-bearing now, not just for the console: the Type=notify readiness edge
      # drives off `craftoria-console list` (RCON runs on the main server thread, so a reply
      # means the server is genuinely ticking). Without it the unit would never reach READY
      # and would fail at TimeoutStartSec 20 minutes later -- assert it here so the failure
      # is fast and legible instead.
      rcon_pw=$(sed -n 's/^rcon.password=//p' "${serverDir}/server.properties" 2>/dev/null | tr -d '\r' | tail -n1)
      if grep -qi '^enable-rcon=true' "${serverDir}/server.properties" 2>/dev/null && [ -n "$rcon_pw" ]; then
        good "RCON enabled (readiness probe)"
      else
        bad "RCON not usable in server.properties -- need enable-rcon=true and a non-empty rcon.password (the readiness probe requires it)"
      fi

      # Minecraft's own watchdog is the ONLY hang protection here (see the header) -- there
      # is deliberately no systemd WatchdogSec to fall back on. server.properties is
      # regenerated by the server and not managed by Nix, and plenty of modpacks ship
      # max-tick-time=-1 to dodge false positives during chunk gen, so a pack update could
      # silently disable it. Warn rather than fail: a disabled watchdog is a degraded
      # server, not an unstartable one, and failing the boot over it would be worse.
      mtt=$(sed -n 's/^max-tick-time=//p' "${serverDir}/server.properties" 2>/dev/null | tr -d '\r' | tail -n1)
      case "''${mtt:-unset}" in
        unset | -1 | 0)
          warn "max-tick-time=''${mtt:-unset} -- Minecraft's hang watchdog is OFF and nothing else covers it; a wedged tick will hang indefinitely"
          ;;
        *) good "max-tick-time=$mtt (hang watchdog active)" ;;
      esac

      good "JRE ${jre}/bin/java"

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
  #     rcon.port=25575
  #     rcon.password=<pick-one>
  # RCON binds to server-ip (all interfaces when empty), but 25575 is deliberately NOT
  # in the firewall allow-list, so it is reachable on loopback only. Keep it that way.
  #     craftoria-console          # interactive prompt
  #     craftoria-console list     # one-shot command: prints the reply and exits
  # mcrcon runs each ARGUMENT as its own rcon command, so a multi-word command must be a
  # single quoted word or it silently becomes several commands:
  #     craftoria-console 'save-all flush'    # right
  #     craftoria-console save-all flush      # WRONG: `save-all`, then a bogus `flush`
  rconConsole = pkgs.writeShellApplication {
    name = "craftoria-console";
    runtimeInputs = with pkgs; [
      mcrcon
      coreutils
      gnused
    ];
    text = ''
      props="${serverDir}/server.properties"
      if [ ! -r "$props" ]; then
        echo "craftoria-console: cannot read $props (is the server installed?)" >&2
        exit 1
      fi
      # tail -n1 (not head) so a closed pipe can't SIGPIPE sed into a pipefail exit.
      getprop() { sed -n "s/^$1=//p" "$props" | tr -d '\r' | tail -n1; }

      if [ "$(getprop enable-rcon)" != "true" ]; then
        echo "craftoria-console: enable-rcon is not 'true' in $props" >&2
        exit 1
      fi
      port="$(getprop rcon.port)"; port="''${port:-25575}"
      MCRCON_PASS="$(getprop rcon.password)"
      if [ -z "$MCRCON_PASS" ]; then
        echo "craftoria-console: rcon.password is empty in $props" >&2
        exit 1
      fi
      export MCRCON_PASS

      # No args -> interactive terminal mode; args -> run them and exit.
      if [ "$#" -eq 0 ]; then
        exec mcrcon -H 127.0.0.1 -P "$port" -t
      fi
      exec mcrcon -H 127.0.0.1 -P "$port" "$@"
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
    name = "craftoria-ready";
    runtimeInputs = with pkgs; [
      coreutils
      systemd
    ];
    text = ''
      probe() { timeout 10 ${rconConsole}/bin/craftoria-console list >/dev/null 2>&1; }

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
  # This hangs off btrbk-local.service (defined in ./btrbk.nix) rather than being a helper
  # run by hand, because the weekly timer fires that same unit -- so the scheduled snapshots
  # get the identical treatment. btrbk has no native pre/post-snapshot hooks (only the
  # --preserve* flags affect a run), so systemd's Exec hooks are the seam.
  #
  # Caveat: the window spans the WHOLE btrbk run, retention deletes included, not just the
  # snapshot ioctl. Deletes are fast and this host snapshots two subvolumes, so it is
  # seconds -- but it is autosave-off seconds, and a crash inside it loses more than a
  # crash outside it would.
  snapshotSaves = pkgs.writeShellApplication {
    name = "craftoria-snapshot-saves";
    runtimeInputs = with pkgs; [
      coreutils
      gnugrep
      systemd
    ];
    text = ''
      mode="''${1:?usage: craftoria-snapshot-saves freeze|thaw}"

      # Never fail the btrbk run. home still needs its snapshot even when the server is down
      # or RCON is wedged, and a stopped server has already flushed on SIGTERM -- so a
      # missing server is a no-op, not an error. Every path below exits 0 on purpose.
      if ! systemctl is-active --quiet craftoria; then
        echo "craftoria not active -- world already at rest, skipping $mode"
        exit 0
      fi

      # mcrcon exits 0 whenever RCON *accepted* the line, so an in-game "Unknown command"
      # still looks like success (verified: `craftoria-console tps` returns 0). Match the
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
        out="$(timeout 30 ${rconConsole}/bin/craftoria-console "$@" 2>&1)" || out="<rcon call failed>"
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
          echo "ERROR: autosave still off -- run 'craftoria-console save-on' by hand NOW"
          ;;
      esac
      exit 0
    '';
  };
in
{
  # ---- host prerequisites, declarative ---------------------------------------

  # Keep transparent hugepages off `always`. This started as an ATM10/Java-21
  # incident (G1 SIGSEGV in G1RegionMarkStatsCache), but THP=always corrupting G1's
  # mark bitmaps is a general modded-server hazard, and the rule is free. madvise,
  # not never -- so still never add -XX:+UseTransparentHugePages / -XX:+UseLargePages
  # to user_jvm_args.txt.
  systemd.tmpfiles.rules = [
    "w! /sys/kernel/mm/transparent_hugepage/enabled - - - - madvise"
  ];

  # Minecraft Java. A user-unit listener publishes on the normal INPUT path, so the
  # NixOS firewall genuinely governs it.
  networking.firewall.allowedTCPPorts = [ 25565 ];

  # `craftoria-console` for an interactive/one-shot RCON prompt; raw mcrcon for
  # scripting. e2fsprogs supplies chattr/lsattr -- not in the base system profile, and
  # needed for the NOCOW world-reset ritual documented next to serverDir above.
  environment.systemPackages = [
    rconConsole
    pkgs.mcrcon
    pkgs.e2fsprogs
  ];

  # ---- the service + console socket ------------------------------------------
  # System units running as User=shane: the world/config/log files stay shane-owned
  # exactly as before, but the server's lifecycle now belongs to the host (boots with
  # the machine, lives under the system manager) instead of shane's login session —
  # which is what it always semantically was, a public boot-critical daemon. This is
  # why `linger` is gone: it only existed to force user units to start at boot.

  # Console input FIFO. systemd holds the read end open so a writer closing does not
  # EOF the server into a shutdown:
  #   echo "list" > /run/craftoria.stdin
  # SocketUser=shane keeps the node shane-writable (system sockets are created owned
  # by root by default). Output is on the journal (`journalctl -u craftoria -f`). For
  # an interactive command prompt with inline replies, prefer `craftoria-console`
  # (RCON) above.
  systemd.sockets.craftoria = {
    description = "Craftoria 2 Minecraft server console FIFO";
    partOf = [ "craftoria.service" ];
    socketConfig = {
      # %t is /run for system units (was /run/user/1000 under the user manager).
      ListenFIFO = "%t/craftoria.stdin";
      SocketUser = "shane";
      SocketMode = "0600";
      RemoveOnStop = true;
      Service = "craftoria.service";
    };
  };

  systemd.services.craftoria = {
    description = "Minecraft server (Craftoria 2, NeoForge 26.1.2.76)";
    requires = [ "craftoria.socket" ];
    after = [
      "craftoria.socket"
      "network-online.target"
    ];
    wants = [ "network-online.target" ];
    wantedBy = [ "multi-user.target" ];

    # Bound the restart loop: default 5/10s can't trip a 30s RestartSec, so a
    # repeating crash would restart forever, each risking a half-written world.
    startLimitIntervalSec = 3600;
    startLimitBurst = 3;

    serviceConfig = {
      # Type=notify: the unit stays "activating" through the multi-minute modpack load and
      # only flips to "active" once craftoria-ready (forked by the launcher) confirms the
      # server is ticking and sends READY=1. NotifyAccess=all because that reporter is a
      # cgroup sibling, not the main PID. This is what makes `systemctl`/Beszel state honest
      # instead of reporting "started" at execve.
      Type = "notify";
      NotifyAccess = "all";
      # Run as shane so world/config/log files stay shane-owned, identical to the
      # former user unit — only the managing scope (system vs user) changes.
      User = "shane";
      WorkingDirectory = serverDir;

      # Fail fast with a readable reason instead of a confusing JVM error minutes in.
      ExecStartPre = "${preflight}/bin/craftoria-preflight";
      # Resolves the installed NeoForge version, then execs java (JVM becomes PID 1).
      ExecStart = "${launcher}/bin/craftoria-launch";

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
      # fails if craftoria-ready never reports READY=1 within it (server never came up).
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

      # Home replaced with an empty tmpfs, only the server dir bound back in: the JVM
      # can't see ~/.ssh, ~/.config, etc. /nix/store stays readable under strict
      # (ro, not hidden), so the JRE and launcher resolve.
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

      # Now reachable as a system unit (a user unit couldn't set these up). PrivateIPC
      # gives the JVM its own System V IPC / POSIX message-queue namespace -- the server
      # uses neither, so it is free isolation. PrivateUsers maps only shane + root into
      # a user namespace (every other host UID appears as nobody), so a compromise can't
      # reach files owned by other users and any setuid bit in the closure is inert;
      # shane-owned world/config files stay writable because shane is the mapped user.
      #
      # A user namespace *can* block perf_event_open -- the syscall kept above for
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

  # ---- clean snapshots -------------------------------------------------------
  # Extends the unit generated by services.btrbk.instances.local in ./btrbk.nix. Living
  # here, not there, keeps the RCON plumbing next to the console/probe that share it; the
  # coupling is one-directional and ./btrbk.nix carries a pointer back.
  #
  # `+` runs these as root: btrbk-local.service is User=btrbk, which cannot traverse
  # /home/shane to read rcon.password out of server.properties.
  #
  # ExecStopPost (not ExecStop) because it must also run when btrbk fails or is killed --
  # that is the whole reason the thaw is a systemd hook instead of a line in a script.
  systemd.services.btrbk-local.serviceConfig = {
    ExecStartPre = "+${snapshotSaves}/bin/craftoria-snapshot-saves freeze";
    ExecStopPost = "+${snapshotSaves}/bin/craftoria-snapshot-saves thaw";
  };
}
