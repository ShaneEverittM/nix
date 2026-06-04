{ pkgs, ... }:
{
  home.username = "shane";
  home.homeDirectory = "/home/shane";
  home.stateVersion = "25.11";

  programs.home-manager.enable = true;

  # Let home-manager manage bash. This is what sources hm-session-vars.sh (and
  # thus applies home.sessionPath below) — without an HM-managed shell, those
  # session vars are written but never sourced. (This is unrelated to the
  # earlier reverted set-environment hack; it adds no bashrcExtra.)
  programs.bash.enable = true;

  # Re-add `code .` support. Disabling appendWindowsPath (in configuration.nix)
  # dropped the whole Windows PATH, including VS Code's bin dir. Put back just
  # that one dir — it contains only code/code.cmd/code-tunnel.exe (no
  # space-named files), so it won't retrigger the Warp command-generator bug
  # that motivated disabling the Windows PATH in the first place. The `code`
  # launcher also needs `wslpath`, which lives in /bin and is already on PATH in
  # WSL-interop shells (set-environment only appends the Nix dirs).
  home.sessionPath = [
    "/mnt/c/Users/shane/AppData/Local/Programs/Microsoft VS Code/bin"
  ];

  # git lives here so its identity is declarative (replaces a hand-edited
  # ~/.gitconfig). Uncomment and fill in your details, then rebuild.
  programs.git = {
    enable = true;
    userName = "Shane Murphy";
    userEmail = "mail@shanemurphy.space";
    extraConfig.init.defaultBranch = "main";
  };

  # starter user packages — adjust freely
  home.packages = with pkgs; [
    ripgrep
    fd
    nixd # Nix language server (used by VS Code nix-ide)
    nixfmt-rfc-style # official RFC-style formatter; provides `nixfmt`
  ];
}
