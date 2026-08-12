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

  # Keep the Nix expression focused on VM assembly. The only dynamic bridge is this
  # entrypoint: the test-driver objects are passed to a typed external function, while
  # replacements preserve the identity's single source of truth.
  testScript =
    builtins.replaceStrings
      [ "@identityUsername@" "@identityUserEmail@" ]
      [ identity.username identity.userEmail ]
      ''
        ${builtins.readFile ./base-smoke.py}
        run(machine, subtest)
      '';
}
