# The cross-host shared package set. A plain `pkgs -> [ derivation ]` function so it
# can be consumed uniformly by home-manager's `home.packages` on every host (WSL,
# personal Mac, work Mac) and by the `packages.default` buildEnv in flake.nix for
# ad-hoc `nix profile install`. Keep this list platform-agnostic; host- or
# OS-specific packages belong in the relevant modules/home/{linux,darwin}.nix.
pkgs:
with pkgs;
[
  ripgrep
  fd
  nixd # Nix language server (used by VS Code nix-ide)
  nixfmt-rfc-style # official RFC-style formatter; provides `nixfmt`
  manix # fast CLI search over NixOS/HM option + nixpkgs docs (`manix ssh`)
  fastfetch
  uv
]
