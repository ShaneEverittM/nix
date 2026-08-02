# Boots the real craftoria module in a VM and smoke-tests the console *plumbing*:
# the FIFO console socket comes up under the lingering user manager, a command written
# to the FIFO reaches the server's stdin, and the sandbox doesn't kill the process.
#
# What it does NOT test: the actual NeoForge/Craftoria server. That needs a multi-GB,
# non-free, un-committable modpack and an accepted EULA (the module's preflight fails
# without them), so we can't run it in CI. We stand in a tiny reader for ExecStart that
# preserves the one thing that's ours to get wrong -- the StandardInput=socket wiring and
# the systemd hardening around it -- and drop the preflight. Everything else (the socket
# unit, FIFO path, SocketMode, sandboxing, linger) is the real module under test.
{ pkgs }:
let
  inherit (pkgs) lib;
  # Must match modules serverDir; the stand-in writes its transcript here and the test
  # reads it back from the host side of the bind mount.
  serverDir = "/home/shane/Servers/minecraft/craftoria2";
in
pkgs.testers.runNixOSTest {
  name = "craftoria-console";

  nodes.machine =
    { ... }:
    {
      imports = [ ../hosts/exodus/craftoria.nix ];

      # The module sets users.users.shane.linger = true but (on exodus) the user itself
      # is declared in configuration.nix. Declare it here with the uid the FIFO path
      # (%t = /run/user/1000) assumes.
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
      systemd.user.services.craftoria.serviceConfig = {
        ExecStartPre = lib.mkForce [ ];
        ExecStart = lib.mkForce (
          pkgs.writeShellScript "craftoria-console-stub" ''
            echo "craftoria-console-stub up"
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
    # Linger (set by the module) starts shane's user manager at boot, before any login.
    machine.wait_for_unit("user@1000.service")


    def as_shane(cmd):
        # Reach the per-user systemd manager without an interactive login.
        return f"su shane -c 'XDG_RUNTIME_DIR=/run/user/1000 {cmd}'"


    # The console FIFO socket unit publishes the path the module documents.
    machine.wait_until_succeeds(as_shane("systemctl --user is-active craftoria.socket"))
    machine.wait_for_file("/run/user/1000/craftoria.stdin")
    machine.wait_until_succeeds(as_shane("systemctl --user is-active craftoria.service"))

    # A command written to the FIFO reaches the server's stdin (the whole point of the
    # StandardInput=socket wiring: a writer closing must not EOF the server).
    machine.succeed("echo list > /run/user/1000/craftoria.stdin")
    machine.wait_until_succeeds("grep -q 'got: list' ${serverDir}/console.log")

    # A second write proves systemd held the read end open across the first writer's
    # close, rather than the stub hitting EOF and exiting.
    machine.succeed("echo 'say hi' > /run/user/1000/craftoria.stdin")
    machine.wait_until_succeeds("grep -q 'got: say hi' ${serverDir}/console.log")

    # The hardening (seccomp all/deny, ProtectHome=tmpfs, private keyring, ...) didn't
    # SIGSYS/kill the process after it did real work.
    machine.succeed(as_shane("systemctl --user is-active craftoria.service"))
  '';
}
