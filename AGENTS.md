# AGENTS.md

Guidance for AI coding agents working in this repository.

## Repository purpose

This is a public, platform-agnostic Nix flake for Shane's personal machines:

- `nixosConfigurations.nixos`: NixOS-on-WSL system for user `shane`.
- `homeConfigurations."shane@macbook"` and `homeConfigurations.shane`: standalone home-manager for a personal macOS machine.
- `homeModules.*` and `nixosModules.*`: reusable public modules consumed by a separate private work-Mac repo.

Keep this repo safe to publish. Do not add secrets, work-internal settings, tokens, private hostnames, private registry URLs, or encrypted secret files.

## High-level map

| Path | Purpose |
| --- | --- |
| `flake.nix` | Inputs and public outputs: WSL system, Mac home configs, reusable modules, default package env. |
| `hosts/wsl/default.nix` | WSL host assembly and public per-host values. Imports NixOS + home-manager layers. |
| `hosts/macbook/default.nix` | Personal Mac standalone home-manager assembly. No nix-darwin. |
| `modules/home/default.nix` | Universal home-manager core bundle. |
| `modules/home/common.nix` | Owns the `publicHome.*` option namespace and shared cross-host config. |
| `modules/home/{git,shell,rust,bun}.nix` | Shared home-manager behavior imported everywhere. |
| `modules/home/linux.nix` | Linux/WSL-only home-manager layer. |
| `modules/home/darwin.nix` | macOS-only home-manager bundle for GUI/terminal config. |
| `modules/home/{vscode,warp,jetbrains}.nix` | macOS dotfile/app modules. |
| `modules/home/warp-settings.nix` | Shared Warp settings attr schema used by macOS and WSL seeders. |
| `modules/home/warp-wsl.nix` | WSL activation step that copies generated Warp config to Windows paths. |
| `modules/home/ssh-agent.nix` | WSL 1Password SSH agent relay. |
| `modules/nixos/*.nix` | NixOS-only system modules for WSL. |
| `lib/packages.nix` | Stable, platform-agnostic shared CLI package list. |
| `lib/unstable-packages.nix` | Small platform-agnostic package lane from `nixpkgs-unstable`. |
| `files/` | Public dotfiles used by home-manager modules. |
| `Brewfile` | Mac-only Homebrew base outside home-manager. |

The `README.md` has the detailed human-facing explanation. Use this file for quick rules and workflow reminders.

## Design rules that matter

1. **Home-manager is the main reuse layer.** Shared behavior belongs in `modules/home/*`; host files should mostly supply values.
2. **Use `publicHome.*` for public, per-machine values.** If a module needs host-specific input, add a typed option under `publicHome` rather than hardcoding values in shared modules.
3. **Keep `modules/home/common.nix` platform-agnostic.** It must work on Linux and Darwin.
4. **Do not add `nix.*` settings to home-manager modules.** The private work Mac uses Determinate Nix and consumes these modules; Nix settings belong in `modules/nixos/*` only.
5. **Split platforms by imports, not by unsafe option references.** Darwin eval cannot reference NixOS/WSL-only options like `wsl.*`. Put WSL logic in `modules/home/linux.nix` or `modules/nixos/*`, and Mac logic in `modules/home/darwin.nix`/GUI modules.
6. **Keep package lists platform-agnostic unless the file says otherwise.** Shared CLI packages go in `lib/packages.nix`; fast-moving shared CLI tools go in `lib/unstable-packages.nix`; OS-specific packages belong in platform modules.
7. **Generate mergeable config from Nix attrsets.** Cargo and Warp config are intentionally generated from attrs so downstream private consumers can overlay with `lib.recursiveUpdate`-style merges. Avoid text-template appends for TOML.
8. **Out-of-store dotfiles are intentional.** Public hosts default to `publicHome.dotfiles.mode = "outOfStore"` so app dotfiles are live-editable from the checkout. Downstream consumers can set `"store"`.
9. **Avoid state-version churn.** Do not change `home.stateVersion` or `system.stateVersion` unless explicitly requested and you understand the migration impact.
10. **New files must be added to git before flake rebuilds see them.** Nix reads flakes from the git tree. Mention `git add <path>` when introducing files that are consumed by Nix.

## Where to make common changes

| Change | Edit here |
| --- | --- |
| Add shared CLI tool | `lib/packages.nix` |
| Add shared CLI tool that needs unstable | `lib/unstable-packages.nix` |
| Add shell alias/init behavior | `modules/home/shell.nix` |
| Add git behavior | `modules/home/git.nix` |
| Add host identity/path/value | the relevant `hosts/*/default.nix` via `publicHome.*` |
| Add reusable per-host option | `modules/home/common.nix` or the owning module's `options.publicHome.*` |
| Add WSL system behavior | `modules/nixos/wsl.nix` or `modules/nixos/common.nix` |
| Add WSL home behavior | `modules/home/linux.nix` or an imported WSL-only module |
| Add macOS GUI/dotfile behavior | `modules/home/darwin.nix` plus `vscode.nix`, `warp.nix`, or `jetbrains.nix` |
| Change shared Warp settings | `modules/home/warp-settings.nix` |
| Change source dotfiles | `files/` |
| Change CI eval | `.github/workflows/eval.yml` |

## Validation workflow

Prefer the narrowest check that covers your change, then run the broader eval when practical.

```bash
# Format changed Nix files.
nixfmt path/to/file.nix

# CI-equivalent evaluation without building outputs or modifying flake.lock.
nix flake check --all-systems --no-build --no-write-lock-file --show-trace

# Optional targeted host evaluations.
nix eval .#nixosConfigurations.nixos.config.system.build.toplevel.drvPath --no-write-lock-file
nix eval .#homeConfigurations."shane@macbook".activationPackage.drvPath --no-write-lock-file
```

Notes:

- Mac home config is evaluable anywhere but buildable only with a Darwin builder.
- `programs.warp.packageSource = "local-oss"` may require full Xcode + Metal toolchain on macOS when actually building.
- Do not run `nixos-rebuild switch`, `nh home switch`, or any activation command unless explicitly asked; those mutate the user's machine.
- Do not run `nix flake update` unless explicitly asked; it changes `flake.lock`.

## Commit hygiene

- Use Conventional Commits for commit messages, e.g. `docs: add agent guidance`, `feat: add shared shell helper`, `fix: correct WSL warp path`.
- Do not create commits unless explicitly asked.
- Before proposing or creating a commit, inspect `git status --short` and the relevant diff so unrelated user work is not staged.
- Stage only files that belong to the requested change. Remember that new files consumed by the flake must be `git add`-ed before Nix can see them.
- Include `flake.lock` only when inputs were intentionally updated.

## Style

- Format Nix with `nixfmt` / `nixfmt-rfc-style`.
- Keep comments focused on non-obvious why/constraints, not line-by-line what.
- Prefer small, composable modules and typed options over ad-hoc host conditionals.
- Keep public modules identity- and secret-free. Public SSH keys are okay only when already intentionally public.
- Preserve existing names and structure unless a requested change needs a refactor.
