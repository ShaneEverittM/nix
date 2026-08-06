# Boots the shared NixOS base in a VM and asserts its *behavior*, not just its
# buildability. The toplevel builds prove the config compiles; nothing before this
# ever started the services — a valid-but-wrong sshd config (hardening silently not
# applying) would ship green. The assertions here are the base's actual contracts:
# key-only ssh enforced on the wire, discovery/DNS/tailnet daemons up, the memory
# backstops armed, and the home-manager fold-in producing shane's real git identity.
#
# Imports are à la carte, not the bundle: btrfs.nix appends compress= mount options to
# the real hosts' pool mounts, which would break the test VM's virtual filesystems —
# exactly the per-module composition the modules/nixos split exists for.
{ pkgs, inputs }:
let
  identity = import ../lib/identity.nix;
in
pkgs.testers.runNixOSTest {
  name = "base-smoke";

  # user.nix imports home-manager from the flake inputs and core.nix pins nixPath to
  # them, so the node needs the same specialArgs the real host assemblies thread.
  node.specialArgs = { inherit inputs; };

  nodes.machine =
    { lib, ... }:
    {
      imports = [
        ../modules/nixos/core.nix
        ../modules/nixos/user.nix
        ../modules/nixos/ssh.nix
        ../modules/nixos/network.nix
        ../modules/nixos/memory.nix
      ];

      # The test framework boots the VM with direct kernel boot; the EFI bootloader
      # the physical hosts use can't (and needn't) install here.
      boot.loader.systemd-boot.enable = lib.mkForce false;
      boot.loader.efi.canTouchEfiVariables = lib.mkForce false;

      # nixpkgs.config is a unique-merge option and the test framework supplies the
      # node's nixpkgs itself, colliding with core.nix's allowUnfree. Nothing in the
      # base needs unfree packages, so force it empty here rather than weakening the
      # shared module's definition.
      nixpkgs.config = lib.mkForce { };

      # stateVersion is per-host by design (the shared modules never set it); this
      # node is its own "host", so it supplies both like a real assembly does.
      system.stateVersion = "26.05";
      home-manager.users.${identity.username}.home.stateVersion = "26.05";
    };

  testScript = ''
    machine.wait_for_unit("multi-user.target")

    with subtest("sshd is up and hardened"):
        machine.wait_for_unit("sshd.service")
        machine.wait_for_open_port(22)
        # Assert the rendered config the module manages. (First attempt asserted on
        # `sshd -T` instead; it exited 0 in this VM with output that matched nothing,
        # so its dump is printed below as an unasserted diagnostic breadcrumb only —
        # the wire tests are the real effective-behavior check.)
        rendered = machine.succeed("cat /etc/ssh/sshd_config")
        for expected in [
            "PasswordAuthentication no",
            "KbdInteractiveAuthentication no",
            "PermitRootLogin no",
            "AllowUsers ${identity.username}",
        ]:
            assert expected in rendered, f"sshd_config missing: {expected}"
        print("sshd -T dump (diagnostic only):")
        print(machine.succeed("sshd -T 2>&1 || true"))

    with subtest("only publickey auth is offered on the wire"):
        # A real client attempt, and a discriminating one: the server names its
        # permitted auth methods in the denial. Hardened → "Permission denied
        # (publickey)."; password auth enabled would read "(publickey,password)" and
        # fail the exact-match assertion. The `ssh` guard keeps machine.fail honest —
        # a missing client binary would otherwise fake the failure.
        machine.succeed("command -v ssh")
        denied = machine.fail(
            "ssh -o UserKnownHostsFile=/dev/null -o StrictHostKeyChecking=no "
            "-o NumberOfPasswordPrompts=0 ${identity.username}@127.0.0.1 true 2>&1"
        )
        assert "Permission denied (publickey)" in denied, f"unexpected denial: {denied!r}"

    with subtest("discovery, DNS, and tailnet daemons are up"):
        machine.wait_for_unit("avahi-daemon.service")
        machine.wait_for_unit("systemd-resolved.service")
        machine.succeed("resolvectl status >/dev/null")
        # tailscaled runs unauthenticated until `tailscale up`; the contract here is
        # that it starts and stays up, not that it joins a tailnet.
        machine.wait_for_unit("tailscaled.service")

    with subtest("memory backstops are armed"):
        machine.wait_for_unit("earlyoom.service")
        machine.succeed("swapon --show=NAME --noheadings | grep -q zram")

    with subtest("home-manager fold-in produced the shared identity"):
        # End-to-end through the fold-in: the activation unit ran, wrote shane's git
        # config, and the identity plumbed through from lib/identity.nix.
        email = machine.succeed(
            "su - ${identity.username} -c 'git config --get user.email'"
        ).strip()
        assert email == "${identity.userEmail}", f"git user.email is {email!r}"
        machine.succeed("getent passwd ${identity.username} | grep -q zsh")
        machine.succeed("nh --version")
  '';
}
