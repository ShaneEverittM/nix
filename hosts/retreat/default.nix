# NixOS assembly for the headless dev/server box: the `nixosConfigurations.retreat`
# system — NixOS with home-manager folded in as a module. Formerly a standalone
# home-manager config on CachyOS, then a KDE desktop (see git history); now a headless
# machine reached over SSH.
#
# The home layer imports the shared core + linux.nix: the full workstation toolchain
# (unlike rebirth's server slice), because development still happens here, just
# remotely. No desktop.nix (GUI dotfiles would be inert with no graphical session) and
# NOT generic-linux.nix: that module's non-NixOS fixups (XDG_DATA_DIRS, LOCALE_ARCHIVE)
# are handled natively by NixOS and would be actively wrong here.
{ inputs, system }:

let
  # Unstable lane. Feeds the shared fast-moving CLI tools (mise, acli) and gradle
  # (see modules/home/{common,java}.nix) — fast movers that benefit from the newer channel.
  # allowUnfree matches the system's stance in the shared NixOS base; the narrow shared
  # predicate in lib/nixpkgs-config.nix only covers acli.
  pkgsUnstable = import ../../lib/mk-pkgs.nix {
    input = inputs.nixpkgs-unstable;
    inherit system;
    extraConfig.allowUnfree = true;
  };
in
inputs.nixpkgs.lib.nixosSystem {
  inherit system;

  # Thread the flake inputs to modules (the shared base uses it for the
  # nixPath pin).
  specialArgs = { inherit inputs; };

  modules = [
    ./configuration.nix
    # Shared physical-host base bundle: boot, locale, users, sshd, tailscale, nh, and
    # the home-manager fold-in with the personal identity (see modules/nixos/).
    ../../modules/nixos
    {
      home-manager.extraSpecialArgs = { inherit pkgsUnstable; };
      home-manager.users.shane =
        { pkgs, ... }:
        {
          imports = [
            ../../modules/home # core bundle (common + git + onepassword + ssh + shell + rust + bun + java)
            ../../modules/home/linux.nix # shared Linux layer
          ];

          # No 1Password app here, so neither publicHome.onepassword.sshAgent nor
          # publicHome.git.sshSigningProgram is set: SSH_AUTH_SOCK stays whatever sshd
          # forwarded (`ssh -A` / ForwardAgent from a workstation), and git signs with
          # plain ssh-keygen against that agent -- the same arrangement as rebirth.
          # Identity (name/email/signing key) still comes from the shared base. The
          # consequence: pushes and signed commits only work from a session that
          # forwarded an agent, not from the local console.

          # claude-code is what keeps this a dev box rather than a pure server: sessions
          # run here over SSH. The GUI apps that used to sit beside it (VS Code, IDEA,
          # Discord, Warp, Zed) went with the desktop.
          home.packages = [ pkgs.claude-code ];
        };
    }
  ];
}
