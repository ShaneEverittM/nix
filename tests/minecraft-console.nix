# Boots the real minecraft module in a VM and smoke-tests the console *plumbing* for both
# packs: each console FIFO socket comes up under the system manager, a command written to
# a FIFO reaches that server's stdin, the two units are genuinely independent, the
# autoStart split holds, and the sandbox doesn't kill the process.
#
# What it does NOT test: the actual NeoForge servers. Those need multi-GB, non-free,
# un-committable modpacks and an accepted EULA (the module's preflight fails without them),
# so we can't run them in CI. We stand in a tiny reader for ExecStart that preserves the
# one thing that's ours to get wrong -- the StandardInput=socket wiring and the systemd
# hardening around it -- and drop the preflight. Everything else (the socket units, FIFO
# paths, SocketMode/SocketUser, world subvolume creation, sandboxing) is the real module
# under test.
{ pkgs }:
let
  inherit (pkgs) lib;
  # The stand-ins write their transcripts here and the test reads them back. Shared with
  # the module via paths.nix, so the test cannot drift from the serverDirs the units
  # actually use.
  dirs = import ../hosts/exodus/minecraft/paths.nix;
in
pkgs.testers.runNixOSTest {
  name = "minecraft-console";

  nodes.machine =
    { ... }:
    {
      imports = [ ../hosts/exodus/minecraft ];

      # The module runs the services as User=shane and the sockets as SocketUser=shane,
      # but the shane account itself is declared in modules/nixos/user.nix, which this
      # test doesn't import -- declare it here so both the units' user and the FIFO
      # owners exist.
      users.users.shane = {
        isNormalUser = true;
        uid = 1000;
      };

      # The serverDirs and their world subvolumes are created by the module's own tmpfiles
      # rules (part of what's under test); the tree *above* them is the host's job, and it
      # has to be shane-owned the whole way down -- systemd-tmpfiles refuses an "unsafe
      # path transition" from a user-owned directory into a root-owned one and bails on the
      # whole run. On exodus these already exist; here they don't, and letting tmpfiles
      # auto-create them as root is exactly the failure that guard exists to catch.
      systemd.tmpfiles.rules = [
        "d /home/shane 0700 shane users - -"
        "d /home/shane/Servers 0755 shane users - -"
        "d /home/shane/Servers/minecraft 0755 shane users - -"
      ];

      # Swap each pack's launcher (needs the modpack) for a stand-in that keeps the exact
      # console contract: read line-delimited commands from stdin (the FIFO, via
      # StandardInput=socket) and record them so the test can assert delivery. Drop the
      # preflight, which would fail-fast on the missing pack/EULA.
      systemd.services = lib.mapAttrs (name: dir: {
        serviceConfig = {
          ExecStartPre = lib.mkForce [ ];
          # Readiness is normally reported by the RCON poller the launcher forks, which this
          # stub replaces -- so the stub sends READY=1 itself to get the Type=notify unit to
          # active. Nothing here is on a clock: the module sets no WatchdogSec (Minecraft's
          # own max-tick-time owns hang detection), so a stub can sit idle indefinitely.
          ExecStart = lib.mkForce (
            pkgs.writeShellScript "${name}-console-stub" ''
              echo "${name}-console-stub up"
              ${pkgs.systemd}/bin/systemd-notify --ready
              while IFS= read -r line; do
                printf 'got: %s\n' "$line" >> ${dir}/console.log
              done
            ''
          );
        };
      }) dirs;
    };

  testScript = ''
    start_all()
    machine.wait_for_unit("multi-user.target")

    # The module creates each pack's tree ahead of the unit: the server dir plus the world
    # as its own (would-be NOCOW subvolume) directory, user-owned. On the VM's non-btrfs
    # root the `v` line degrades to a plain directory, which is the point of using `v`.
    machine.succeed("test -d ${dirs.atm10}/world")
    machine.succeed("test -d ${dirs.craftoria}/world")
    machine.succeed("[ \"$(stat -c %U ${dirs.atm10}/world)\" = shane ]")

    # atm10 carries autoStart, so it and its FIFO socket come up on their own (%t = /run
    # for a system unit). No user manager, no linger.
    machine.wait_until_succeeds("systemctl is-active atm10.socket")
    machine.wait_for_file("/run/atm10.stdin")
    machine.wait_until_succeeds("systemctl is-active atm10.service")

    # craftoria does not: autoStart = false means no wantedBy on the service, and the
    # socket has none of its own either, so the whole pair stays dormant. This is what
    # keeps a 14 GiB host from booting two modded heaps.
    machine.fail("systemctl is-active craftoria.service")
    machine.fail("systemctl is-active craftoria.socket")

    # A command written to the FIFO reaches that server's stdin (the whole point of the
    # StandardInput=socket wiring: a writer closing must not EOF the server).
    machine.succeed("echo list > /run/atm10.stdin")
    machine.wait_until_succeeds("grep -q 'got: list' ${dirs.atm10}/console.log")

    # A second write proves systemd held the read end open across the first writer's
    # close, rather than the stub hitting EOF and exiting.
    machine.succeed("echo 'say hi' > /run/atm10.stdin")
    machine.wait_until_succeeds("grep -q 'got: say hi' ${dirs.atm10}/console.log")

    # The RCON wrapper refuses to dial while its own unit is down. That guard is what makes
    # sharing port 25575 between packs safe: with atm10 up and craftoria stopped, something
    # *is* listening on 25575, so a console that only checked the socket would happily save
    # the wrong world and report success.
    craftoria_refusal = machine.fail("craftoria-console list 2>&1")
    assert "refusing to dial" in craftoria_refusal, craftoria_refusal

    # Starting the dormant pack by hand brings up its own socket via Requires=, on its own
    # FIFO path -- the two instances share no runtime state.
    machine.succeed("systemctl start craftoria.service")
    machine.wait_for_file("/run/craftoria.stdin")
    machine.succeed("echo 'seed' > /run/craftoria.stdin")
    machine.wait_until_succeeds("grep -q 'got: seed' ${dirs.craftoria}/console.log")

    # ...and it landed only there. A shared FIFO or a bind-mount leak between the two
    # sandboxes would show up as cross-talk here.
    machine.fail("grep -q 'got: seed' ${dirs.atm10}/console.log")
    machine.fail("grep -q 'got: list' ${dirs.craftoria}/console.log")

    # The hardening (seccomp allow/deny, ProtectHome=tmpfs, private keyring, PrivateUsers,
    # PrivateIPC, ...) didn't SIGSYS/kill either process after it did real work.
    machine.succeed("systemctl is-active atm10.service")
    machine.succeed("systemctl is-active craftoria.service")
  '';
}
