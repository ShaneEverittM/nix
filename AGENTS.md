# AGENTS.md

Guidance for AI coding agents working in this repository.

## Repository purpose

This is a public, platform-agnostic Nix flake for Shane's personal machines:

- `nixosConfigurations.exodus`: bare-metal NixOS KDE Plasma desktop, with home-manager
  folded in as a module.
- `nixosConfigurations.rebirth`: headless NixOS home server (repurposed laptop),
  home-manager folded in; only the shared git + shell home modules.
- `homeConfigurations."shane@macbook"` and `homeConfigurations.shane`: standalone
  home-manager for a personal macOS machine.
- `homeModules.*` and `nixosModules.*`: reusable public modules consumed by a separate
  private work-Mac repo.

Both NixOS hosts import the shared base bundle `modules/nixos/` (single-concern modules
mirroring `modules/home/`: core, user, ssh, network, memory, btrfs — with the identity
from `lib/identity.nix`). "Linux" in this repo means **any** Linux host; non-NixOS
distro workarounds go in `generic-linux.nix`, which must never reach a NixOS host. All
in-repo Linux hosts run NixOS, so `generic-linux.nix` currently has no in-repo consumer
— it stays exported via `homeModules.genericLinux` for downstream non-NixOS Linux use.
(A NixOS-on-WSL host existed before the physical machines; it was dropped — see git
history.)

Keep this repo safe to publish. Do not add secrets, work-internal settings, tokens,
private hostnames, private registry URLs, or encrypted secret files.

## High-level map

| Path                                                     | Purpose                                                                                                                             |
| -------------------------------------------------------- | ----------------------------------------------------------------------------------------------------------------------------------- |
| `flake.nix`                                              | Inputs and public outputs: NixOS hosts, Mac home configs, reusable modules, default package env.                                    |
| `hosts/macbook/default.nix`                              | Personal Mac standalone home-manager assembly. No nix-darwin.                                                                       |
| `hosts/exodus/default.nix`                               | `exodus` NixOS desktop assembly. Folds home-manager in as a module (core + linux + desktop).                                        |
| `hosts/exodus/configuration.nix`                         | `exodus` system layer: KDE Plasma, NVIDIA, PipeWire, crash handling; imports the minecraft/btrbk/swap/beszel siblings.              |
| `hosts/exodus/hardware-configuration.nix`                | `exodus` generated hardware scan (filesystems, kernel modules).                                                                     |
| `hosts/rebirth/default.nix`                              | `rebirth` headless home-server assembly. Home layer: git (via base) + shell + shared CLI set.                                       |
| `hosts/rebirth/configuration.nix`                        | `rebirth` system layer: Wi-Fi (wpa_supplicant), lid-switch.                                                                         |
| `hosts/rebirth/hardware-configuration.nix`               | `rebirth` generated hardware scan (filesystems, kernel modules).                                                                    |
| `modules/home/default.nix`                               | Universal home-manager core bundle.                                                                                                 |
| `modules/home/common.nix`                                | Owns the `publicHome.*` option namespace and shared cross-host config.                                                              |
| `modules/home/{git,shell,rust,bun,java}.nix`             | Shared home-manager behavior in the core bundle (git + shell are also on rebirth).                                                  |
| `modules/home/onepassword.nix`                           | `SSH_AUTH_SOCK` for the 1Password agent; per-platform socket path.                                                                  |
| `modules/home/ssh.nix`                                   | Owns `~/.ssh/config`: aliases for this repo's hosts, plus an `Include config.local` for non-public hosts.                           |
| `modules/home/linux.nix`                                 | Shared Linux layer.                                                                                                                 |
| `modules/home/generic-linux.nix`                         | Non-NixOS distro fixups (XDG data dirs, locale archive, fontconfig). Never on NixOS; downstream-only now.                           |
| `modules/home/desktop.nix`                               | Cross-platform GUI dotfile bundle (vscode + zed + warp + jetbrains).                                                                |
| `modules/home/darwin.nix`                                | macOS-only layer. Imports `desktop.nix`.                                                                                            |
| `modules/home/{vscode,zed,warp,jetbrains}.nix`           | Cross-platform dotfile/app modules; each resolves its own per-OS paths.                                                             |
| `modules/home/warp-settings.nix`                         | Shared Warp settings attr schema (macOS + Linux).                                                                                   |
| `modules/nixos/default.nix`                              | Shared NixOS base bundle; hosts import this.                                                                                        |
| `modules/nixos/{core,user,ssh,network,memory,btrfs}.nix` | Single-concern base modules: nix/boot/locale/nh, account + hm fold-in, sshd, avahi/tailscale/resolved, zram/earlyoom, btrfs tuning. |
| `lib/identity.nix`                                       | Single-sourced public identity (login name, name, email, SSH public key).                                                           |
| `lib/mk-pkgs.nix`                                        | The one shared nixpkgs instantiation (unfree predicate baked in).                                                                   |
| `lib/checks.nix`                                         | CI gates: lint checks, downstream contract checks, host toplevel builds.                                                            |
| `lib/packages.nix`                                       | Stable, platform-agnostic shared CLI package list.                                                                                  |
| `lib/unstable-packages.nix`                              | Small platform-agnostic package lane from `nixpkgs-unstable`.                                                                       |
| `files/`                                                 | Public dotfiles used by home-manager modules.                                                                                       |
| `Brewfile`                                               | Mac-only Homebrew base outside home-manager.                                                                                        |

The `README.md` has the detailed human-facing explanation. Use this file for quick rules
and workflow reminders.

## Design rules that matter

1. **Home-manager is the main reuse layer.** Shared behavior belongs in
   `modules/home/*`; host files should mostly supply values.
2. **Use `publicHome.*` for public, per-machine values.** If a module needs
   host-specific input, add a typed option under `publicHome` rather than hardcoding
   values in shared modules.
3. **Keep `modules/home/common.nix` platform-agnostic.** It must work on Linux and
   Darwin.
4. **Do not add `nix.*` settings to home-manager modules.** The private work Mac uses
   Determinate Nix and consumes these modules; Nix settings belong in `modules/nixos/*`
   only.
5. **Split platforms by imports, not by unsafe option references.** Darwin eval cannot
   reference NixOS-only options. Put Linux logic in `modules/home/linux.nix` or
   `modules/nixos/*`, and Mac logic in `modules/home/darwin.nix`/GUI modules.
6. **Keep package lists platform-agnostic unless the file says otherwise.** Shared CLI
   packages go in `lib/packages.nix`; fast-moving shared CLI tools go in
   `lib/unstable-packages.nix`; OS-specific packages belong in platform modules.
7. **Generate mergeable config from Nix attrsets.** Cargo and Warp config are
   intentionally generated from attrs so downstream private consumers can overlay with
   `lib.recursiveUpdate`-style merges. Avoid text-template appends for TOML.
8. **Out-of-store dotfiles are intentional.** Public hosts default to
   `publicHome.dotfiles.mode = "outOfStore"` so app dotfiles are live-editable from the
   checkout. Downstream consumers can set `"store"`.
9. **Avoid state-version churn.** Do not change `home.stateVersion` or
   `system.stateVersion` unless explicitly requested and you understand the migration
   impact.
10. **New files must be added to git before flake rebuilds see them.** Nix reads flakes
    from the git tree. Mention `git add <path>` when introducing files that are consumed
    by Nix.

## Where to make common changes

| Change                                   | Edit here                                                                                                                 |
| ---------------------------------------- | ------------------------------------------------------------------------------------------------------------------------- |
| Add shared CLI tool                      | `lib/packages.nix`                                                                                                        |
| Add shared CLI tool that needs unstable  | `lib/unstable-packages.nix`                                                                                               |
| Add shell alias/init behavior            | `modules/home/shell.nix`                                                                                                  |
| Add git behavior                         | `modules/home/git.nix`                                                                                                    |
| Add an SSH host alias                    | `modules/home/ssh.nix` (non-public hosts go in an unmanaged `~/.ssh/config.local`)                                        |
| Add host identity/path/value             | the relevant `hosts/*/default.nix` via `publicHome.*`                                                                     |
| Add reusable per-host option             | `modules/home/common.nix` or the owning module's `options.publicHome.*`                                                   |
| Add NixOS behavior for every NixOS host  | the matching single-concern `modules/nixos/*.nix` (new concerns: new module + bundle line in `modules/nixos/default.nix`) |
| Add JVM/gradle behavior                  | `modules/home/java.nix`                                                                                                   |
| Add exodus-only system behavior          | `hosts/exodus/configuration.nix`                                                                                          |
| Add/change a Minecraft pack              | `hosts/exodus/minecraft/default.nix` (a pack) or `minecraft/service.nix` (behavior every pack gets)                       |
| Add rebirth-only system behavior         | `hosts/rebirth/configuration.nix`                                                                                         |
| Change name/email/SSH public key         | `lib/identity.nix`                                                                                                        |
| Add behavior for every Linux host        | `modules/home/linux.nix`                                                                                                  |
| Add a non-NixOS distro workaround        | `modules/home/generic-linux.nix`                                                                                          |
| Add GUI/dotfile behavior for any desktop | `modules/home/desktop.nix` plus `vscode.nix`, `zed.nix`, `warp.nix`, or `jetbrains.nix`                                   |
| Add macOS-only behavior                  | `modules/home/darwin.nix`                                                                                                 |
| Change shared Warp settings              | `modules/home/warp-settings.nix`                                                                                          |
| Change source dotfiles                   | `files/`                                                                                                                  |
| Change CI gates                          | `lib/checks.nix` (the workflow `.github/workflows/ci.yml` is just its driver)                                             |

## Validation workflow

Prefer the narrowest check that covers your change, then run the broader eval when
practical.

```bash
# Format changed Nix files.
nixfmt path/to/file.nix

# Fast local eval of every output without building or touching flake.lock.
# NOT CI-equivalent: CI *builds* the checks for the runner's own system, so lint
# gates and toplevels actually run there. To run a lint gate for real locally:
#   nix build .#checks.aarch64-darwin.deadnix --no-link --no-write-lock-file
nix flake check --all-systems --no-build --no-write-lock-file --show-trace

# Optional targeted host evaluations.
nix eval .#nixosConfigurations.exodus.config.system.build.toplevel.drvPath --no-write-lock-file
nix eval .#nixosConfigurations.rebirth.config.system.build.toplevel.drvPath --no-write-lock-file
nix eval .#homeConfigurations."shane@macbook".activationPackage.drvPath --no-write-lock-file
```

Notes:

- Mac home config is evaluable anywhere but buildable only with a Darwin builder.
- `programs.warp.packageSource = "local-oss"` may require full Xcode + Metal toolchain
  on macOS when actually building.
- Do not run `nixos-rebuild switch`, `nh home switch`, or any activation command unless
  explicitly asked; those mutate the user's machine.
- Do not run `nix flake update` unless explicitly asked; it changes `flake.lock`.

## Commit hygiene

- Use Conventional Commits for commit messages, e.g. `docs: add agent guidance`,
  `feat: add shared shell helper`, `fix(exodus): correct warp path`.
- Do not create commits unless explicitly asked.
- Before proposing or creating a commit, inspect `git status --short` and the relevant
  diff so unrelated user work is not staged.
- Stage only files that belong to the requested change. Remember that new files consumed
  by the flake must be `git add`-ed before Nix can see them.
- Include `flake.lock` only when inputs were intentionally updated.

## Flake input update PRs

Any PR that changes `flake.lock` should include an `nvd` closure diff in the body,
inside a collapsible `<details>` block. It's a breadcrumb trail: when a later bump
breaks something, the per-PR diff shows exactly which package versions moved, so
bisecting a regression starts from a concrete suspect list (kernel, systemd, glibc, a
driver) instead of a bare rev bump.

- **Scope: only PRs that touch `flake.lock`.** Module-only PRs have no meaningful
  closure delta — skip it there.
- **Easy path:** paste the diff `nh`/`nvd` already prints when you `switch` the bump on
  a host. That's the same artifact, for free.
- **Canonical / reproducible path** (independent of any machine's generations — builds
  each side, so it needs the relevant builder):

  ```bash
  base=$(nix build --no-link --print-out-paths \
    'github:ShaneEverittM/nix/main#nixosConfigurations.exodus.config.system.build.toplevel')
  head=$(nix build --no-link --print-out-paths \
    '.#nixosConfigurations.exodus.config.system.build.toplevel')
  nix run nixpkgs#nvd -- diff "$base" "$head"
  ```

- **Per output.** The diff is specific to what you built (`exodus`, `rebirth`, or the
  macbook home `activationPackage`); the toolchain-level changes that actually break
  things are largely shared across them, so one representative host's diff is usually
  enough — note which one it is.
- Generation stays manual for now; automating it belongs in the Dagger/flake-check lane,
  not a `.github` Actions job.

## Style

- Format Nix with `nixfmt` / `nixfmt-rfc-style`.
- Keep comments focused on non-obvious why/constraints, not line-by-line what.
- Prefer small, composable modules and typed options over ad-hoc host conditionals.
- Keep public modules identity- and secret-free. Public SSH keys are okay only when
  already intentionally public.
- Preserve existing names and structure unless a requested change needs a refactor.
