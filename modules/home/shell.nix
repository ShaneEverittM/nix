# zsh + ergonomics, shared by every host. Aliases lean on tools from
# lib/packages.nix (eza/bat) and zoxide. On WSL, zsh is also set as the login shell
# in modules/nixos/wsl.nix; macOS already defaults to zsh.
{ config, lib, ... }:

{
  programs.zsh = {
    enable = true;
    enableCompletion = true;

    shellAliases = {
      cd = "z";
      ls = "eza";
      cat = "bat";
      rr = "rustrover";
    };

    history = {
      size = 5000000;
      save = 5000000;
      extended = true;
    };

    initContent = lib.mkMerge [
      ''
        PS1="%(?:%B%F{green}:%B%F{red})➜%f%b %F{cyan}%1d%f "
        if command -v uv >/dev/null 2>&1; then
          eval "$(uv generate-shell-completion zsh)"
        fi
        if command -v mise >/dev/null 2>&1; then
          eval "$(mise activate zsh)"
        fi
      ''
      # zoxide must initialize last — after mise's chpwd hook — or it warns that
      # its hook may be shadowed. mkOrder 2000 puts it after every other init
      # contributor (incl. the WSL agent relay at 1500).
      (lib.mkOrder 2000 ''eval "$(${config.programs.zoxide.package}/bin/zoxide init zsh)"'')
      (lib.mkAfter ''
        # Warpify this zsh only when explicitly requested (the `dev` function sets
        # WARP_BOOTSTRAP_SUBSHELL). Opt-in, so it never fires for the top-level Warp
        # shell or for incidental nested zsh.
        if [ -n "$WARP_BOOTSTRAP_SUBSHELL" ] && [ "$TERM_PROGRAM" = "WarpTerminal" ] \
             && [ -t 1 ] && [[ $- == *i* ]]; then
          unset WARP_BOOTSTRAP_SUBSHELL
          printf '\eP$f{"hook": "SourcedRcFileForWarp", "value": { "shell": "zsh" }}\x9c'
        fi

        # Drop into a warpified zsh dev shell for the flake in the current dir.
        dev() { WARP_BOOTSTRAP_SUBSHELL=1 nix develop "$@" -c zsh; }
      '')
    ];
  };

  programs.zoxide = {
    enable = true;
    # We emit `zoxide init` last ourselves (see initContent); home-manager's
    # integration places it too early, before mise.
    enableZshIntegration = false;
  };

  # Per-directory environments. nix-direnv adds the fast, GC-cached `use flake`
  # implementation so entering a repo with a flake.nix reuses its dev shell
  # instead of re-evaluating on every cd. The zsh hook is installed by
  # home-manager's integration; it runs before the zoxide hook (mkOrder 2000),
  # which is fine — direnv only needs to load before the prompt is drawn.
  programs.direnv = {
    enable = true;
    nix-direnv.enable = true;
  };
}
