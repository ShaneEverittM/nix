# zsh + ergonomics, shared by every host. Aliases lean on tools from
# lib/packages.nix (eza/bat) and zoxide. On WSL, zsh is also set as the login shell
# in modules/nixos/wsl.nix; macOS already defaults to zsh.
{
  config,
  lib,
  pkgs,
  ...
}:

let
  # Auto-Warpify hook: emit the SourcedRcFileForWarp control sequence on every
  # interactive shell so Warp warpifies subshells automatically (nix develop,
  # nested zsh/bash, etc.). Guarded on TERM_PROGRAM/tty/interactive so it stays
  # silent in non-Warp terminals (Apple Terminal, ssh, WSL without Warp), which
  # would otherwise print the raw escape sequence. Harmless no-op in the
  # top-level Warp shell, which is already warpified. The syntax is valid in both
  # zsh and bash, so the same snippet is shared by both. nix develop sources
  # ~/.bashrc, so warpifying bash covers `nix develop` dev shells.
  warpifyHook = shell: ''
    if [ "$TERM_PROGRAM" = "WarpTerminal" ] && [ -t 1 ] && [[ $- == *i* ]]; then
      printf '\eP$f{"hook": "SourcedRcFileForWarp", "value": { "shell": "${shell}", "uname": "%s" }}\x9c' "$(uname)"
    fi
  '';
in
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
        # macOS only: 1Password's native SSH agent. WSL gets its SSH_AUTH_SOCK
        # from the agent relay in ssh-agent.nix (mkOrder 1500) instead.
        ${lib.optionalString pkgs.stdenv.isDarwin ''
          export SSH_AUTH_SOCK="${config.home.homeDirectory}/Library/Group Containers/2BUA8C4S2C.com.1password/t/agent.sock"
        ''}
      ''
      # zoxide must initialize last — after mise's chpwd hook — or it warns that
      # its hook may be shadowed. mkOrder 2000 puts it after every other init
      # contributor (incl. the WSL agent relay at 1500).
      (lib.mkOrder 2000 ''eval "$(${config.programs.zoxide.package}/bin/zoxide init zsh)"'')
      (lib.mkAfter (warpifyHook "zsh"))
    ];
  };

  # nix develop drops into bash and sources ~/.bashrc, so warpify bash too; this
  # is what lets `nix develop` dev shells get warpified without a wrapper.
  programs.bash = {
    enable = true;
    initExtra = warpifyHook "bash";
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
