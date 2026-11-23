# Boots the guest half of the minecraft module (hosts/retreat/minecraft/service.nix) in a
# VM and smoke-tests the plumbing a pack's microVM depends on: each console FIFO socket
# comes up under the system manager, a command written to a FIFO reaches that server's
# stdin, two units are genuinely independent, the sandbox doesn't kill the process, and
# the snapshot listener answers the host's freeze/thaw requests and nobody else's.
#
# What it does NOT test:
#   - The actual NeoForge servers. Those need multi-GB, non-free, un-committable modpacks
#     and an accepted EULA (the module's preflight fails without them), so we can't run
#     them in CI. We stand in a tiny reader for ExecStart that preserves the one thing
#     that's ours to get wrong -- the StandardInput=socket wiring and the systemd
#     hardening around it -- and drop the preflight.
#   - The VM boundary itself (microvm, tap, virtiofs, the host firewall, `gameserver`).
#     On retreat each pack is the only server in its guest; here both share one test
#     machine, which the module supports and which is what lets one node cover the
#     independence checks. The host layer is covered by the retreat toplevel build only.
{ pkgs }:
let
  inherit (pkgs) lib;
  # The stand-ins write their transcripts here and the test reads them back. Shared with
  # the module via paths.nix, so the test cannot drift from the serverDirs the units
  # actually use.
  dirs = import ../hosts/retreat/minecraft/paths.nix;
  snapshotPort = 25590;
in
pkgs.testers.runNixOSTest {
  name = "minecraft-console";

  nodes.machine =
    { ... }:
    {
      imports = [ ../hosts/retreat/minecraft/service.nix ];

      publicMinecraft = {
        servers = lib.mapAttrs (name: dir: {
          description = "stand-in for ${name}";
          serverDir = dir;
          jre = pkgs.jdk21_headless;
          memory = 1024;
        }) dirs;

        # Admit loopback only, standing in for "the host's end of the tap": the test
        # asserts both that this source gets an answer and that another one does not.
        snapshotControl = {
          enable = true;
          port = snapshotPort;
          allowFrom = "127.0.0.1";
        };
      };

      # On retreat the pack trees are host directories shared into the guest, created by
      # the host half (minecraft/host.nix). There is no host here, so make them.
      systemd.tmpfiles.rules = [
        "d /var/lib/minecraft 0755 root root - -"
      ]
      ++ lib.concatLists (
        lib.mapAttrsToList (_: dir: [
          "d ${dir} 0750 minecraft minecraft - -"
          "d ${dir}/world 0750 minecraft minecraft - -"
        ]) dirs
      );

      environment.systemPackages = [ pkgs.socat ];

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

    # Inside a guest every declared server starts with the machine -- whether a pack is
    # up is decided by whether the host starts its VM, not by anything in here. Each
    # comes up with its FIFO socket (%t = /run for a system unit), as the dedicated
    # account.
    for name in ["atm10", "craftoria"]:
        machine.wait_until_succeeds(f"systemctl is-active {name}.socket")
        machine.wait_for_file(f"/run/{name}.stdin")
        machine.wait_until_succeeds(f"systemctl is-active {name}.service")
    machine.succeed("[ \"$(systemctl show -p User --value atm10.service)\" = minecraft ]")
    machine.succeed("[ \"$(id -u minecraft)\" = 25565 ]")

    # A command written to the FIFO reaches that server's stdin (the whole point of the
    # StandardInput=socket wiring: a writer closing must not EOF the server).
    machine.succeed("echo list > /run/atm10.stdin")
    machine.wait_until_succeeds("grep -q 'got: list' ${dirs.atm10}/console.log")

    # A second write proves systemd held the read end open across the first writer's
    # close, rather than the stub hitting EOF and exiting.
    machine.succeed("echo 'say hi' > /run/atm10.stdin")
    machine.wait_until_succeeds("grep -q 'got: say hi' ${dirs.atm10}/console.log")

    # The other server has its own FIFO, and a write lands only there. A shared FIFO or
    # a leak between the two sandboxes would show up as cross-talk here.
    machine.succeed("echo 'seed' > /run/craftoria.stdin")
    machine.wait_until_succeeds("grep -q 'got: seed' ${dirs.craftoria}/console.log")
    machine.fail("grep -q 'got: seed' ${dirs.atm10}/console.log")
    machine.fail("grep -q 'got: list' ${dirs.craftoria}/console.log")

    # The sandbox is real: writable server dir, read-only everything else, and the
    # hardening (seccomp allow/deny, private keyring, PrivateUsers, PrivateIPC, ...)
    # didn't SIGSYS/kill either process after it did real work.
    machine.succeed("[ \"$(stat -c %U ${dirs.atm10}/console.log)\" = minecraft ]")
    machine.succeed("systemctl is-active atm10.service")
    machine.succeed("systemctl is-active craftoria.service")

    # The RCON wrapper refuses to dial while its own unit is down. That guard is what
    # keeps the snapshot hooks from quiescing whatever else happens to hold the port.
    machine.succeed("systemctl stop craftoria.service")
    craftoria_refusal = machine.fail("craftoria-console list 2>&1")
    assert "refusing to dial" in craftoria_refusal, craftoria_refusal

    # ---- snapshot listener ----------------------------------------------------
    # The host's btrbk run sends one word and reads the transcript back. The stand-ins
    # have no RCON, so the hooks themselves can only report that save-off did not take
    # (atm10, running) or that the world is at rest (craftoria, stopped) -- what is
    # under test is the request path: the word arrives, every snapshotted server's hook
    # runs, the transcript comes back, and the exchange ends with DONE.
    request = "printf '%s\\n' {} | socat -t 120 - TCP:127.0.0.1:${toString snapshotPort},connect-timeout=5"
    frozen = machine.succeed(request.format("freeze"))
    assert "DONE freeze" in frozen, frozen
    assert "craftoria not active" in frozen, frozen
    assert "save-off" in frozen, frozen
    thawed = machine.succeed(request.format("thaw"))
    assert "DONE thaw" in thawed, thawed

    # Anything else is refused without running a hook.
    junk = machine.succeed(request.format("stop"))
    assert "expected 'freeze' or 'thaw'" in junk, junk
    assert "DONE" not in junk, junk

    # ...and the firewall admits the configured source and nothing else to that port. A
    # single node can't make a connection from a foreign address (anything it sends to
    # itself arrives on lo, which the firewall always accepts), so assert the ruleset:
    # exactly one rule mentions the port, and it is the source-restricted one.
    rules = machine.succeed("iptables -S | grep -- '--dport ${toString snapshotPort}'").strip().splitlines()
    assert len(rules) == 1, rules
    assert "-s 127.0.0.1/32" in rules[0] and "nixos-fw-accept" in rules[0], rules
  '';
}
