# zsh + ergonomics, shared by every host. Aliases lean on tools from
# lib/packages.nix (eza/bat) and zoxide. On WSL, zsh is also set as the login shell
# in modules/nixos/wsl.nix; macOS already defaults to zsh.
{ ... }:

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

    initContent = ''
      PS1="%(?:%B%F{green}:%B%F{red})➜%f%b %F{cyan}%1d%f "
      if command -v uv >/dev/null 2>&1; then
        eval "$(uv generate-shell-completion zsh)"
      fi
      if command -v mise >/dev/null 2>&1; then
        eval "$(mise activate zsh)"
      fi
    '';
  };

  programs.zoxide = {
    enable = true;
    enableZshIntegration = true;
  };
}
