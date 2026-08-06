# Boots the real craftoria module in a VM and smoke-tests the console *plumbing*:
# the FIFO console socket comes up under the system manager, a command written to the
# FIFO reaches the server's stdin, and the sandbox doesn't kill the process.
#
# What it does NOT test: the actual NeoForge/Craftoria server. That needs a multi-GB,
# non-free, un-committable modpack and an accepted EULA (the module's preflight fails
# without them), so we can't run it in CI. We stand in a tiny reader for ExecStart that
# preserves the one thing that's ours to get wrong -- the StandardInput=socket wiring and
# the systemd hardening around it -- and drop the preflight. Everything else (the socket
# unit, FIFO path, SocketMode/SocketUser, sandboxing) is the real module under test.
{ pkgs }:
let
  inherit (pkgs) lib;
  # The stand-in writes its transcript here and the test reads it back from the host
  # side of the bind mount. Shared with the module via craftoria-paths.nix, so the
  # test cannot drift from the serverDir the unit actually uses.
  inherit (import ../hosts/exodus/craftoria-paths.nix) serverDir;
in
pkgs.testers.runNixOSTest {
  name = "craftoria-console";

  nodes.machine =
    { ... }:
    {
      imports = [ ../hosts/exodus/craftoria.nix ];

      # The module runs the service as User=shane and the socket as SocketUser=shane,
      # but the shane account itself is declared in modules/nixos/user.nix, which this
      # test doesn't import -- declare it here so both the unit's user and the FIFO
      # owner exist.
      users.users.shane = {
        isNormalUser = true;
        uid = 1000;
      };

      # BindPaths + WorkingDirectory need serverDir to exist and be shane-owned before
      # the unit starts.
      systemd.tmpfiles.rules = [
        "d /home/shane 0700 shane users - -"
        "d /home/shane/Servers 0755 shane users - -"
        "d /home/shane/Servers/minecraft 0755 shane users - -"
        "d ${serverDir} 0755 shane users - -"
      ];

      # Swap the NeoForge launcher (needs the modpack) for a stand-in that keeps the exact
      # console contract: read line-delimited commands from stdin (the FIFO, via
      # StandardInput=socket) and record them so the test can assert delivery. Drop the
      # preflight, which would fail-fast on the missing pack/EULA.
      systemd.services.craftoria.serviceConfig = {
        ExecStartPre = lib.mkForce [ ];
        # Readiness is normally reported by the RCON poller the launcher forks, which this
        # stub replaces -- so the stub sends READY=1 itself to get the Type=notify unit to
        # active. Nothing here is on a clock: the module sets no WatchdogSec (Minecraft's
        # own max-tick-time owns hang detection), so the stub can sit idle indefinitely.
        ExecStart = lib.mkForce (
          pkgs.writeShellScript "craftoria-console-stub" ''
            echo "craftoria-console-stub up"
            ${pkgs.systemd}/bin/systemd-notify --ready
            while IFS= read -r line; do
              printf 'got: %s\n' "$line" >> ${serverDir}/console.log
            done
          ''
        );
      };
    };

  testScript = ''
    start_all()
    machine.wait_for_unit("multi-user.target")

    # The console FIFO socket unit publishes the path the module documents (%t = /run
    # for a system unit). The service is a system unit now -- no user manager, no linger.
    machine.wait_until_succeeds("systemctl is-active craftoria.socket")
    machine.wait_for_file("/run/craftoria.stdin")
    machine.wait_until_succeeds("systemctl is-active craftoria.service")

    # A command written to the FIFO reaches the server's stdin (the whole point of the
    # StandardInput=socket wiring: a writer closing must not EOF the server).
    machine.succeed("echo list > /run/craftoria.stdin")
    machine.wait_until_succeeds("grep -q 'got: list' ${serverDir}/console.log")

    # A second write proves systemd held the read end open across the first writer's
    # close, rather than the stub hitting EOF and exiting.
    machine.succeed("echo 'say hi' > /run/craftoria.stdin")
    machine.wait_until_succeeds("grep -q 'got: say hi' ${serverDir}/console.log")

    # The hardening (seccomp allow/deny, ProtectHome=tmpfs, private keyring, PrivateUsers,
    # PrivateIPC, ...) didn't SIGSYS/kill the process after it did real work.
    machine.succeed("systemctl is-active craftoria.service")
  '';
}
