# WSL-only home-manager layer. Imported by the WSL host on top of ./linux.nix (the
# shared Linux layer), which it pulls in itself so the host only has to name this one.
# Everything here assumes a Windows side exists: the 1Password named-pipe relay, the
# Windows-side Warp seeder, and the Windows VS Code launcher.
{ ... }:
{
  imports = [
    ./linux.nix # shared Linux layer (also imported directly by native Linux hosts)
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
