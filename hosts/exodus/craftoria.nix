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
# net/minecraftforge, so the launcher/preflight below only change the glob. The world
# generates on first start.
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
      Type = "exec";
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

      # Modded startup is slow; Type=exec means this is a formality (systemd reports
      # "started" at execve, not readiness -- watch logs/latest.log for "Done").
      TimeoutStartSec = 1200;
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
}
