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
    ];
  };

  programs.zoxide = {
    enable = true;
    # We emit `zoxide init` last ourselves (see initContent); home-manager's
    # integration places it too early, before mise.
    enableZshIntegration = false;
  };
}
