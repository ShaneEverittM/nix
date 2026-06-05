# The stable cross-host shared package set. A plain `pkgs -> [ derivation ]` function
# so it can be consumed uniformly by home-manager's `home.packages` on every host
# (WSL, personal Mac, work Mac) and by the `packages.default` buildEnv in flake.nix
# for ad-hoc `nix profile install`. Keep this list platform-agnostic; host- or
# OS-specific packages belong in the relevant modules/home/{linux,darwin}.nix.
pkgs: with pkgs; [
  # Search / navigation / file viewing
  ripgrep
  fd
  eza # modern ls (aliased to `ls` in modules/home/shell.nix)
  bat # modern cat (aliased to `cat`)
  ncdu # disk-usage TUI

  # Nix tooling
  nixd # Nix language server (used by VS Code nix-ide)
  nixfmt-rfc-style # official RFC-style formatter; provides `nixfmt`
  manix # fast CLI search over NixOS/HM option + nixpkgs docs (`manix ssh`)

  # Git extras (programs.git provides git itself; these back its config in git.nix)
  git-lfs # large-file filters
  diff-so-fancy # git pager
  glab # GitLab CLI

  # General CLI
  jq
  tokei # code line counter
  stow
  watch
  wget
  sshpass
  btop # system monitor
  p7zip
  gh

  # Languages / runtimes (rustup -> rust.nix, bun -> bun.nix, mise -> unstable-packages.nix)
  uv # Python package/runtime manager

  # Editors / misc
  neovim
  fastfetch
]
