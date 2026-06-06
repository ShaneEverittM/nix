# Linux-only home-manager bits. Imported by the WSL host (and any future personal
# Linux host) alongside ./common.nix. (homeDirectory is derived in common.nix from
# publicHome.username.)
{ ... }:
{
  imports = [
    ./ssh-agent.nix # 1Password SSH agent relay (opt-in via publicHome.onepassword)
    ./warp-wsl.nix # seed the Windows-side Warp install (opt-in via publicHome.warp.wslConfig)
  ];

  # Re-add `code .` support. Disabling appendWindowsPath (in modules/nixos/wsl.nix)
  # dropped the whole Windows PATH, including VS Code's bin dir. Put back just
  # that one dir — it contains only code/code.cmd/code-tunnel.exe (no
  # space-named files), so it won't retrigger the Warp command-generator bug
  # that motivated disabling the Windows PATH in the first place. The `code`
  # launcher also needs `wslpath`, which lives in /bin and is already on PATH in
  # WSL-interop shells (set-environment only appends the Nix dirs).
  home.sessionPath = [
    "/mnt/c/Users/shane/AppData/Local/Programs/Microsoft VS Code/bin"
  ];
}
