{ pkgs, ... }:
{
  home.username = "shane";
  home.homeDirectory = "/home/shane";
  home.stateVersion = "25.11";

  programs.home-manager.enable = true;

  # NixOS only assembles the full PATH (and other env) in /etc/set-environment,
  # which /etc/profile sources for LOGIN shells only. Terminal emulators that
  # spawn a non-login shell (Warp's WSL tab, VS Code's integrated terminal, ...)
  # therefore start with a near-empty PATH — which makes Warp's "command not
  # found" highlighter squiggle commands that are actually installed. Source the
  # system environment for every interactive bash; the guard makes it idempotent
  # (it's the same flag NixOS's own /etc/profile uses).
  programs.bash = {
    enable = true;
    bashrcExtra = ''
      if [ -z "$__NIXOS_SET_ENVIRONMENT_DONE" ]; then
        . /etc/set-environment
      fi
    '';
  };

  # git lives here so its identity is declarative (replaces a hand-edited
  # ~/.gitconfig). Uncomment and fill in your details, then rebuild.
  programs.git = {
    enable = true;
    userName = "Shane Murphy";
    userEmail = "mail@shanemurphy.space";
  };

  # starter user packages — adjust freely
  home.packages = with pkgs; [
    ripgrep
    fd
    nixd # Nix language server (used by VS Code nix-ide)
    nixfmt-rfc-style # official RFC-style formatter; provides `nixfmt`
  ];
}
