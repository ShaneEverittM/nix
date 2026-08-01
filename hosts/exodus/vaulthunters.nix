# Vault Hunters 3rd Edition — Remastered (Forge, Minecraft 1.18.2) served natively
# by systemd. Successor to the ATM10 setup this replaced; the systemd skeleton
# (user service + console FIFO + sandboxing) is carried over from
# ~/Servers/minecraft/atm10/atm10-backup, but the runtime is entirely different:
# Forge 1.18.2 on Java 17, not NeoForge 1.21.1 on Java 21.
#
# Vault Hunters Remastered is designed for a fresh world (changed worldgen, not a
# migration target) — which is exactly the situation here, so there is nothing to
# restore. Install the server pack into serverDir (see the preflight) and the world
# generates on first start.
{
  config,
  lib,
  pkgs,
  ...
}:

let
  # The live server directory: pack files, mods, libraries, config, world, logs,
  # user_jvm_args.txt, server.properties, eula.txt. Not populated yet — install the
  # "Vault-Hunters-3rd-Edition-remastered-<ver>-server-files.zip" from CurseForge
  # here and run its installer. The preflight fails the start until it's in place.
  serverDir = "/home/shane/Servers/minecraft/vaulthunters";

  # Java 17 from the system closure — MC 1.18.2 / Forge's runtime, not Java 21.
  jre = pkgs.jdk17_headless;

  # Locate the Forge argfile at runtime instead of pinning its version. Forge 1.17+
  # writes libraries/net/minecraftforge/forge/<mc>-<forge>/unix_args.txt at install
  # time; globbing it means a pack update that bumps Forge needs no nix edit. Execs
  # java as the final step so the JVM stays PID 1 of the unit — signals reach it
  # directly and StandardInput=socket's fd is inherited.
  launcher = pkgs.writeShellApplication {
    name = "vaulthunters-launch";
    runtimeInputs = [ jre ];
    text = ''
      cd "${serverDir}" || exit 1
      shopt -s nullglob
      matches=( "${serverDir}"/libraries/net/minecraftforge/forge/*/unix_args.txt )
      if [ "''${#matches[@]}" -eq 0 ]; then
        echo "no Forge unix_args.txt under ${serverDir}/libraries/net/minecraftforge/forge/*/ -- run the server installer" >&2
        exit 1
      fi
      # Memory/GC tuning stays in user_jvm_args.txt, under your control.
      exec java @user_jvm_args.txt "@''${matches[0]}" nogui
    '';
  };

  # Asserts what NixOS can't guarantee before the JVM starts: an accepted EULA, a
  # writable server dir, and that the pack was actually installed (Forge argfile
  # present). THP stays a cheap belt-and-suspenders check.
  preflight = pkgs.writeShellApplication {
    name = "vaulthunters-preflight";
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

      echo "vaulthunters preflight"

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
      matches=( "${serverDir}"/libraries/net/minecraftforge/forge/*/unix_args.txt )
      if [ "''${#matches[@]}" -gt 0 ]; then
        good "Forge installed ($(basename "$(dirname "''${matches[0]}")"))"
      else
        bad "no Forge unix_args.txt -- install the server pack + run its installer"
      fi

      good "JRE ${jre}/bin/java"

      if [ "$fails" -gt 0 ]; then
        echo "preflight: $fails failed"
        exit 1
      fi
      echo "preflight: ok"
    '';
  };
in
{
  # ---- host prerequisites, declarative ---------------------------------------

  # Keep transparent hugepages off `always`. This started as an ATM10/Java-21
  # incident (G1 SIGSEGV in G1RegionMarkStatsCache), but THP=always corrupting G1's
  # mark bitmaps is a general modded-server hazard, and the rule is free. madvise,
  # not never — so still never add -XX:+UseTransparentHugePages / -XX:+UseLargePages
  # to user_jvm_args.txt.
  systemd.tmpfiles.rules = [
    "w! /sys/kernel/mm/transparent_hugepage/enabled - - - - madvise"
  ];

  # Minecraft Java. A user-unit listener publishes on the normal INPUT path, so the
  # NixOS firewall genuinely governs it.
  networking.firewall.allowedTCPPorts = [ 25565 ];

  # Start shane's user units at boot without an interactive login.
  users.users.shane.linger = true;

  # ---- the service + console socket ------------------------------------------
  # User units, so they run as shane and the world files stay shane-owned. Single-
  # user box, so `systemd.user.*` is effectively shane-only; linger starts them at
  # boot.

  # Console input FIFO. systemd holds the read end open so a writer closing does not
  # EOF the server into a shutdown:
  #   echo "list" > /run/user/1000/vaulthunters.stdin
  # Output is on the journal (`journalctl --user -u vaulthunters -f`).
  systemd.user.sockets.vaulthunters = {
    description = "Vault Hunters Minecraft server console FIFO";
    partOf = [ "vaulthunters.service" ];
    socketConfig = {
      ListenFIFO = "%t/vaulthunters.stdin";
      SocketMode = "0600";
      RemoveOnStop = true;
      Service = "vaulthunters.service";
    };
  };

  systemd.user.services.vaulthunters = {
    description = "Minecraft server (Vault Hunters 3rd Edition Remastered, Forge 1.18.2)";
    requires = [ "vaulthunters.socket" ];
    after = [
      "vaulthunters.socket"
      "network-online.target"
    ];
    wants = [ "network-online.target" ];
    wantedBy = [ "default.target" ];

    # Bound the restart loop: default 5/10s can't trip a 30s RestartSec, so a
    # repeating crash would restart forever, each risking a half-written world.
    startLimitIntervalSec = 3600;
    startLimitBurst = 3;

    serviceConfig = {
      Type = "exec";
      WorkingDirectory = serverDir;

      # Fail fast with a readable reason instead of a confusing JVM error minutes in.
      ExecStartPre = "${preflight}/bin/vaulthunters-preflight";
      # Resolves the installed Forge version, then execs java (JVM becomes PID 1).
      ExecStart = "${launcher}/bin/vaulthunters-launch";

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
      # "started" at execve, not readiness — watch logs/latest.log for "Done").
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
      RestrictNamespaces = true;
      RestrictRealtime = true;
      RestrictSUIDSGID = true;
      LockPersonality = true;
      SystemCallArchitectures = "native";
      # @system-service is an allow-list, and it omits perf_event_open (x86_64
      # syscall 298) — which VH's bundled spark profiler calls via async-profiler.
      # Under seccomp's default kill action that surfaced as SIGSYS (code=dumped,
      # status=31/SYS) about a minute into startup. Allow it explicitly so spark
      # works, and make any *other* unlisted syscall return EPERM instead of killing
      # the JVM: a 200+ mod pack is too broad a surface to enumerate up front, and a
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
      # OOM kills that mimic a crash — leave it to -Xmx in user_jvm_args.txt).
    };
  };
}
