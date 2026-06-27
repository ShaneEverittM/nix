# Nix Configuration

Public, multiplatform Nix configuration. It is a shared home-manager layer plus per-host
assemblies for

- a **NixOS-on-WSL** system (user `shane`, host `nixos`), and
- a **personal macOS** machine (standalone home-manager, no nix-darwin)

It is also designed to be consumed by private consumers, like at work
[Downstream: the private work repo](#downstream-the-private-work-repo).

## Layout

| Path                                           | Purpose                                                              |
| ---------------------------------------------- | -------------------------------------------------------------------- |
| `flake.nix`                                    | inputs + outputs: hosts, home configs, packages, modules.            |
| `lib/packages.nix`                             | shared CLI package set (`pkgs -> [ derivations ]`), used everywhere. |
| `lib/unstable-packages.nix`                    | shared CLI packages that move fast, used everywhere.                 |
| `files/`                                       | public dotfiles; store or out-of-store per `dotfiles.mode`.          |
| `Brewfile`                                     | macOS casks/formulae base.                                           |
| `modules/home/`                                | home-manager modules (the universal sharing layer).                  |
| `modules/home/default.nix`                     | core bundle: common + git + shell + rust + bun.                      |
| `modules/home/common.nix`                      | publicHome.\* options, packages, stateVersion, news.silent.          |
| `modules/home/git.nix`                         | option-driven git; identity via publicHome.git.\*.                   |
| `modules/home/shell.nix`                       | zsh + zoxide, eza/bat aliases, uv/mise activation.                   |
| `modules/home/rust.nix`                        | rustup + cargo (sanitized cross-compile config).                     |
| `modules/home/bun.nix`                         | bun runtime + global @types/bun.                                     |
| `modules/home/linux.nix`                       | linux-only: WSL VS Code PATH, ssh-agent, warp-wsl.                   |
| `modules/home/darwin.nix`                      | mac-only: vscode + zed + warp + jetbrains.                           |
| `modules/home/{vscode,zed,warp,jetbrains}.nix` | GUI/terminal dotfiles (out-of-store symlinks).                       |
| `modules/home/warp-settings.nix`               | shared Warp settings schema (macOS + WSL).                           |
| `modules/home/warp-wsl.nix`                    | WSL-only: seeds the Windows-side Warp install.                       |
| `modules/nixos/`                               | NixOS system modules (WSL host only).                                |
| `modules/nixos/common.nix`                     | flakes, system git, nixPath pin, stateVersion.                       |
| `modules/nixos/wsl.nix`                        | wsl.\*, openssh, user shane, nix-ld, zsh login shell.                |
| `hosts/wsl/default.nix`                        | nixosConfigurations.nixos (nixos + home linux).                      |
| `hosts/macbook/default.nix`                    | homeConfigurations."shane@macbook" (home darwin).                    |

Why this shape: home-manager is the one layer every host shares, so the `modules/home/*`
are the real reuse atom; only WSL has a system (NixOS) layer. Neither Mac uses
nix-darwin (the work Mac can't — MDM owns the system; the personal Mac doesn't need it).
Platform splits happen by **which modules a host imports**, not by `mkIf` — `mkIf`
guards values, not option existence (`wsl.enable` can't be referenced in a Darwin eval
at all).

The shared modules are **option-driven**: behavior lives in the module, per-machine
values come from the `publicHome.*` options a host sets — `username` (derives
`homeDirectory`), `git.{userName,userEmail,signingKey,sshSigningProgram}`, `repoRoot`,
`dotfiles.mode`, `nh.homeFlake`, and `rust.extraCargoConfig`. Public hosts can keep
live-editable out-of-store dotfile links from their checkout; downstream private
consumers can use store-backed public dotfiles and point `nh` at their own consuming
flake, or point to a local clone of this flake. Mergeable TOML config is generated from
Nix attrsets, so downstream consumers can overlay Cargo and Warp settings without text
templates or appended TOML strings. This is what lets the public modules carry no
identity/secrets: each host — and the private work repo — supplies its own. The
interactive shell is **zsh everywhere**; macOS already defaults to it, and WSL's login
shell is set declaratively in `modules/nixos/wsl.nix`. Everything is pinned to the
**nixos-25.11** release across the baseline inputs, with a single stable `nixpkgs`
(`follows` threaded through the main inputs). A separate `nixpkgs-unstable` input is
used only for the small cross-host package lane in `lib/unstable-packages.nix`, for
tools that need to move faster than the release branch.

## AI Agent Guide

AI coding agents should read [`AGENTS.md`](AGENTS.md) before making changes. It is the
quick-reference version of the repo shape, safety constraints, edit locations, and
validation commands. Claude gets the same guidance via the [`CLAUDE.md`](CLAUDE.md)
symlink, and GitHub Copilot gets a short entrypoint through
[`.github/copilot-instructions.md`](.github/copilot-instructions.md).

## Applying Changes

**WSL:**

```bash
nh os switch
```

**Mac:**

```bash
nh home switch
```

Edit the layer that fits the change, then rebuild. The flake is read from the git tree,
so **new files must be `git add`-ed** before a rebuild/switch will see them.

`nh os test` activates now without touching the boot menu; `build` just produces a
`result` without activating.

## Updating Dependencies

```bash
# Update all inputs in flake.lock
nix flake update
# or, just one input
nix flake update <nixpkgs/nixpkgs-unstable>
nh <os/home> switch
```

## Downstream: the Private Work Repo

The work Mac lives in a separate **private** repo (e.g. `nix-work`) that:

- adds this repo as a flake input (`inputs.personal.inputs.nixpkgs.follows = "nixpkgs"`
  and `inputs.personal.inputs.nixpkgs-unstable.follows = "nixpkgs-unstable"`);
- defines a standalone `homeConfigurations."shane@work-mac"` importing
  `personal.homeModules.default` + `personal.homeModules.darwin`, then sets its own
  `publicHome.git.{userName,userEmail,signingKey,sshSigningProgram}` and adds the
  work-only bits the public seed deliberately omitted: work session vars / CLI wrappers,
  a private Cargo registry through `publicHome.rust.extraCargoConfig` attrs, and any
  work-only packages;
- runs on **Determinate Nix**, so it sets `nix.enable = false` to let Determinate own
  Nix's config (which is why `modules/home/common.nix` carries **no** `nix.*` settings —
  keep it that way);

## Notes for macOS

Warp is installed via Homebrew (`cask "warp"` in the `Brewfile`), not Nix. Home Manager
only manages Warp's config — settings, themes, and keybindings under `~/.warp`
(`modules/home/warp.nix`). The `programs.warp.packageSource` option still lets a
downstream consumer install a Warp build through Nix (e.g. `"stable"` or a source-built
`"local-oss"` fork), but the public hosts here leave it at the default `"none"`.

## WSL Notes

- Some `wsl.wslConf.*` settings (e.g. `interop.appendWindowsPath`) only take effect
  after a full WSL restart: run `wsl --shutdown` from Windows, then reopen the distro.
- The primary user is `shane` (uid 1001); the NixOS-WSL fallback `nixos` account holds
  uid 1000.

## Warp on WSL

Warp under WSL is a **Windows** app, so its config lives on the Windows filesystem and
can't be a nix-store symlink (Warp.exe can't follow one). `modules/home/warp-wsl.nix`
therefore _copies_ Nix-generated config onto `/mnt/c` during `nixos-rebuild switch`
(declarative content, imperative placement), gated by `publicHome.warp.wslConfig`:

- **settings** → `%LOCALAPPDATA%\warp\Warp\config\settings.toml`
- **themes** → `%APPDATA%\warp\Warp\data\themes\*.yaml` (JetBrains dark/light)

The settings schema is shared with the Macs (`modules/home/warp-settings.nix`); only the
`themeDir` baked into the TOML differs (a `C:/Users/...` path Warp resolves). Override
the Windows account with `publicHome.warp.windowsUser` (defaults to
`publicHome.username`) and merge extra settings via `publicHome.warp.extraSettings`.

Caveat: Warp **rewrites `settings.toml` at runtime** (any UI toggle), so this is a
seed-on-switch, not a locked file — the same trade-off the macOS module accepts except
without the symlink showing changes in this repo.

## 1Password SSH agent (WSL)

The module `modules/home/ssh-agent.nix` bridges the Windows 1Password SSH agent (a named
pipe) to a Unix socket in WSL, so `ssh`/`git` here authenticate with keys that never
leave 1Password. Enabled in the WSL host via `publicHome.onepassword.sshAgentRelay`. The
Nix side (socat, `SSH_AUTH_SOCK`, the lazy relay started from zsh) is automatic; these
**Windows-side** steps are manual (not Nix-managed):

1. **1Password for Windows → Settings → Developer:** enable _Use the SSH agent_ (and
   _Integrate with 1Password CLI_ if you want `op`/signing).
2. **Install `npiperelay.exe`** on Windows, e.g. `scoop install npiperelay`. If it lands
   somewhere other than `~/scoop/shims/npiperelay.exe`, set
   `publicHome.onepassword.npiperelay` to the WSL-visible path (`/mnt/c/...`).
3. Open a fresh WSL shell; `ssh-add -l` should list your 1Password keys.
   (`communication with agent failed` means npiperelay isn't found or the agent toggle
   is off.)
