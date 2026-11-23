# Boots the host half of the game-server layer (hosts/retreat/gameservers.nix) and tests
# the two things in it that are ours to get wrong and expensive to get wrong on a remote
# box: the firewall that isolates a guest, and the `gameserver` on/off state machine.
#
# The guests themselves are NOT booted: that would need KVM nested inside the test VM.
# Everything around them is real -- the microvm host module, the per-server units, the
# tap devices, systemd-networkd addressing them -- and only the hypervisor process is
# swapped for a stand-in, so "the VM is running" means its unit is active.
#
# For the firewall a network namespace plays the guest. It hangs off a veth that carries
# a slot's tap name (the rules match on the interface name, as they do for a real tap),
# takes the guest address, and then tries to do what a compromised guest would.
{ pkgs, inputs }:
let
  identity = import ../lib/identity.nix;
  operator = identity.username;
in
pkgs.testers.runNixOSTest {
  name = "gameservers";

  # Two boots and a reboot take about a minute. Without this a step that never comes up
  # sits in its retry loop for the driver's default 15 minutes -- per step.
  globalTimeout = 600;

  node.specialArgs = { inherit inputs; };

  nodes.machine =
    { lib, pkgs, ... }:
    {
      imports = [ ../hosts/retreat/gameservers.nix ];

      virtualisation.memorySize = 2048;

      users.users.${operator} = {
        isNormalUser = true;
        uid = 1000;
      };
      security.polkit.enable = true;

      # Something on the host for a guest to be refused by.
      services.openssh.enable = true;

      publicGameServers.servers = {
        # alpha and beta share a port, hence a slot: mutually exclusive.
        alpha = {
          slot = 1;
          memory = 256;
          forwardTCP = [ 25565 ];
          autoStart = true;
          guest = { };
        };
        beta = {
          slot = 1;
          memory = 256;
          forwardTCP = [ 25565 ];
          guest = { };
        };
        # Independent of both.
        gamma = {
          slot = 2;
          memory = 256;
          forwardUDP = [ 15637 ];
          autoStart = true;
          guest = { };
        };
        # Never started: its slot is the one the fake guest borrows.
        delta = {
          slot = 9;
          memory = 256;
          forwardTCP = [ 7777 ];
          guest = { };
        };
      };

      # The stand-in hypervisor. Also drops virtiofsd, which exists only to serve it.
      systemd.services."microvm@" = {
        requires = lib.mkForce [
          "microvm-tap-interfaces@%i.service"
          "microvm-set-booted@%i.service"
        ];
        serviceConfig = {
          ExecStart = lib.mkForce "${pkgs.coreutils}/bin/sleep infinity";
          ExecStop = lib.mkForce "";
          ExecStartPost = lib.mkForce [ ];
          ExecStopPost = lib.mkForce [ ];
        };
      };

      environment.systemPackages = [ pkgs.socat ];
    };

  # Stands in for "something else on the LAN" -- both a player connecting in, and a
  # machine a guest must not be able to reach.
  nodes.lan =
    { pkgs, ... }:
    {
      networking.firewall.allowedTCPPorts = [ 8000 ];
      environment.systemPackages = [ pkgs.socat ];
    };

  testScript = ''
    start_all()
    machine.wait_for_unit("multi-user.target")
    machine.wait_for_unit("firewall.service")
    machine.wait_for_unit("gameservers-autostart.service")
    lan.wait_for_unit("multi-user.target")

    flags = "/var/lib/gameservers/enabled"

    def active(name):
        return machine.execute(f"systemctl is-active --quiet microvm@{name}.service")[0] == 0

    def enabled(name):
        return machine.execute(f"test -e {flags}/{name}")[0] == 0

    with subtest("first activation seeds the flags from autoStart and starts those"):
        machine.wait_until_succeeds("systemctl is-active microvm@alpha.service")
        machine.wait_until_succeeds("systemctl is-active microvm@gamma.service")
        assert enabled("alpha") and enabled("gamma")
        assert not enabled("beta") and not active("beta")
        assert not enabled("delta") and not active("delta")

    with subtest("a running server has its tap, addressed by networkd"):
        machine.wait_until_succeeds("ip -4 -o addr show dev vm-gs1 | grep -q '10.77.1.1/30'")
        machine.wait_until_succeeds("ip -4 -o addr show dev vm-gs2 | grep -q '10.77.2.1/30'")

    with subtest("the operator switches servers without privilege; a slot has one occupant"):
        out = machine.succeed("su - ${operator} -c 'gameserver enable beta'")
        assert "disabling alpha" in out, out
        machine.wait_until_succeeds("systemctl is-active microvm@beta.service")
        assert not active("alpha") and not enabled("alpha")
        assert enabled("beta")
        # gamma is on another slot and is none of beta's business.
        assert active("gamma") and enabled("gamma")
        # start (without enable) also evicts the rival, but leaves the boot flags alone.
        machine.succeed("su - ${operator} -c 'gameserver start alpha'")
        machine.wait_until_succeeds("systemctl is-active microvm@alpha.service")
        assert not active("beta")
        assert enabled("beta") and not enabled("alpha")
        machine.succeed("su - ${operator} -c 'gameserver list'")
        machine.fail("su - ${operator} -c 'gameserver enable nosuch'")

    with subtest("that privilege covers the game servers and nothing else"):
        machine.fail("su - ${operator} -c 'systemctl --no-ask-password stop sshd.service'")
        machine.succeed("systemctl is-active sshd.service")

    with subtest("the firewall rules load, and reloading does not stack them"):
        nat = machine.succeed("iptables -t nat -S")
        assert "--dport 25565 -j DNAT --to-destination 10.77.1.2:25565" in nat, nat
        assert "--dport 15637 -j DNAT --to-destination 10.77.2.2:15637" in nat, nat
        machine.succeed("systemctl reload firewall.service")
        machine.succeed("systemctl restart firewall.service")
        for table, chain, jump in [
            ("filter", "INPUT", "gs-input"),
            ("filter", "FORWARD", "gs-forward"),
            ("nat", "PREROUTING", "gs-prerouting"),
            ("nat", "POSTROUTING", "gs-postrouting"),
        ]:
            n = machine.succeed(f"iptables -t {table} -S {chain} | grep -c -- '-j {jump}'").strip()
            assert n == "1", f"{chain} -> {jump} appears {n} times"
        # Ahead of everything else, so nothing earlier in the chain can accept first.
        machine.succeed("iptables -S INPUT | sed -n 2p | grep -q -- '-j gs-input'")
        machine.succeed("iptables -S FORWARD | sed -n 2p | grep -q -- '-j gs-forward'")

    with subtest("a guest: reachable on its forwarded port, able to answer, unable to reach out"):
        lan_ip = lan.succeed("ip -4 -o addr show dev eth1 | awk '{print $4}' | cut -d/ -f1").strip()
        machine_ip = machine.succeed("ip -4 -o addr show dev eth1 | awk '{print $4}' | cut -d/ -f1").strip()
        assert lan_ip and machine_ip

        # The fake guest on slot 9.
        machine.succeed(
            "ip netns add guest",
            "ip link add vm-gs9 type veth peer name eth0 netns guest",
            "ip link set vm-gs9 up",
            "ip -n guest link set lo up",
            "ip -n guest link set eth0 up",
            "ip -n guest addr add 10.77.9.2/30 dev eth0",
            "ip -n guest route add default via 10.77.9.1",
        )
        # networkd addresses the host end by interface name, exactly as for a real tap.
        machine.wait_until_succeeds("ip -4 -o addr show dev vm-gs9 | grep -q '10.77.9.1/30'")
        machine.succeed(
            "systemd-run --unit=guest-game ${pkgs.iproute2}/bin/ip netns exec guest "
            "${pkgs.socat}/bin/socat TCP-LISTEN:7777,fork,reuseaddr SYSTEM:'echo hello-from-guest'"
        )
        lan.succeed("systemd-run --unit=lan-service ${pkgs.socat}/bin/socat TCP-LISTEN:8000,fork,reuseaddr SYSTEM:'echo hello-from-lan'")
        machine.wait_until_succeeds("ip netns exec guest ss -ltn | grep -q :7777")
        lan.wait_until_succeeds("ss -ltn | grep -q :8000")

        # Control: the LAN service is really there, and the host can reach it. Without
        # this the refusals below could pass for the wrong reason.
        assert "hello-from-lan" in machine.succeed(f"socat -t 5 - TCP:{lan_ip}:8000,connect-timeout=5")

        # IN: a player on the LAN hits the host's port and lands in the guest, and the
        # guest's reply makes it back.
        assert "hello-from-guest" in lan.succeed(f"socat -t 5 - TCP:{machine_ip}:7777,connect-timeout=5")

        # The host may open a connection to a guest (the snapshot freeze/thaw request).
        assert "hello-from-guest" in machine.succeed("socat -t 5 - TCP:10.77.9.2:7777,connect-timeout=5")

        # OUT: nothing private. Not the LAN...
        machine.fail(f"ip netns exec guest socat -t 3 - TCP:{lan_ip}:8000,connect-timeout=3")
        # ...not the host, by its tap address or its LAN address...
        machine.fail("ip netns exec guest socat -t 3 - TCP:10.77.9.1:22,connect-timeout=3")
        machine.fail(f"ip netns exec guest socat -t 3 - TCP:{machine_ip}:22,connect-timeout=3")
        machine.fail("ip netns exec guest ping -c1 -W2 10.77.9.1")
        # ...not another guest's slot, nor its own forwarded port by way of the host.
        machine.fail("ip netns exec guest ping -c1 -W2 10.77.2.1")
        machine.fail(f"ip netns exec guest socat -t 3 - TCP:{machine_ip}:7777,connect-timeout=3")

        # And the refusals are the rules, not a broken route: with the guest's forward
        # chain out of the way the same connection to the LAN goes through.
        machine.succeed("iptables -D FORWARD -j gs-forward")
        assert "hello-from-lan" in machine.succeed(
            f"ip netns exec guest socat -t 5 - TCP:{lan_ip}:8000,connect-timeout=5"
        )
        machine.succeed("systemctl restart firewall.service")
        machine.fail(f"ip netns exec guest socat -t 3 - TCP:{lan_ip}:8000,connect-timeout=3")

    with subtest("flags are the operator's: no re-seed, and they decide what a boot starts"):
        machine.succeed("gameserver disable beta", "gameserver disable gamma", "gameserver stop alpha")
        machine.succeed("systemctl restart gameservers-autostart.service")
        assert not any(active(n) for n in ["alpha", "beta", "gamma", "delta"])
        assert not any(enabled(n) for n in ["alpha", "beta", "gamma", "delta"])

        # Seeding is per server, so one that appears later still gets its default --
        # but not over an operator's choice: alpha's slot is held by beta, so alpha
        # stays off even though it declares autoStart.
        machine.succeed(
            "gameserver enable beta",
            "rm /var/lib/gameservers/seeded/alpha /var/lib/gameservers/seeded/gamma",
            "systemctl restart gameservers-autostart.service",
        )
        machine.wait_until_succeeds("systemctl is-active microvm@gamma.service")
        assert enabled("gamma") and enabled("beta") and not enabled("alpha")
        machine.succeed("test -e /var/lib/gameservers/seeded/alpha")
        machine.succeed("gameserver disable beta", "gameserver disable gamma")

        machine.succeed("gameserver enable gamma")
        machine.shutdown()
        machine.start()
        machine.wait_for_unit("gameservers-autostart.service")
        machine.wait_until_succeeds("systemctl is-active microvm@gamma.service")
        assert not active("alpha") and not active("beta")
  '';
}
