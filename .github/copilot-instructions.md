# GitHub Copilot instructions

Read the repository-level instructions in [`../AGENTS.md`](../AGENTS.md) before making
changes.

Key reminders:

- This is a public Nix flake for two NixOS hosts + standalone home-manager on macOS;
  keep it secret-free.
- Shared behavior belongs in `modules/home/*`; per-host public values belong in
  `hosts/*/default.nix` via `publicHome.*` options.
- Keep `modules/home/common.nix` platform-agnostic and free of `nix.*` settings.
- Put NixOS-only settings in `modules/home/linux.nix` or `modules/nixos/*`; put Mac-only
  GUI/home settings in `modules/home/darwin.nix` and its imported modules.
- Format Nix with `nixfmt`;
  `nix flake check --all-systems --no-build --no-write-lock-file --show-trace` is the
  fast eval gate (CI additionally builds the checks per runner).
