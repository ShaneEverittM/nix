# Nix Configuration

Public, multiplatform Nix configuration. It is a shared home-manager layer plus per-host
assemblies for

- a **NixOS-on-WSL** system (user `shane`, host `nixos`),
- a **personal macOS** machine (standalone home-manager, no nix-darwin), and
- a **CachyOS (Arch) desktop** (host `exodus`; standalone home-manager on a non-NixOS
  distro, with Determinate Nix supplying the daemon)

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
| `modules/home/onepassword.nix`                 | SSH_AUTH_SOCK for the 1Password agent (per-platform path).           |
| `modules/home/linux.nix`                       | shared Linux layer (WSL + native Linux).                             |
| `modules/home/wsl.nix`                         | WSL-only: Windows VS Code PATH, ssh-agent, warp-wsl.                 |
| `modules/home/generic-linux.nix`               | non-NixOS distro fixups: XDG dirs, locale, fontconfig.               |
| `modules/home/desktop.nix`                     | cross-platform GUI bundle: vscode + zed + warp + jetbrains.          |
| `modules/home/darwin.nix`                      | mac-only layer (imports desktop).                                    |
| `modules/home/{vscode,zed,warp,jetbrains}.nix` | GUI/terminal dotfiles (out-of-store symlinks), per-OS paths.         |
| `modules/home/warp-settings.nix`               | shared Warp settings schema (macOS + Linux + WSL).                   |
| `modules/home/warp-wsl.nix`                    | WSL-only: seeds the Windows-side Warp install.                       |
| `modules/nixos/`                               | NixOS system modules (WSL host only).                                |
| `modules/nixos/common.nix`                     | flakes, system git, nixPath pin, stateVersion.                       |
| `modules/nixos/wsl.nix`                        | wsl.\*, openssh, user shane, nix-ld, zsh login shell.                |
| `hosts/wsl/default.nix`                        | nixosConfigurations.nixos (nixos + home wsl).                        |
| `hosts/macbook/default.nix`                    | homeConfigurations."shane@macbook" (home darwin).                    |
| `hosts/cachy/default.nix`                      | homeConfigurations."shane@exodus" (linux + genericLinux + desktop).  |

Why this shape: home-manager is the one layer every host shares, so the `modules/home/*`
are the real reuse atom; only WSL has a system (NixOS) layer. Neither Mac uses
nix-darwin (the work Mac can't — MDM owns the system; the personal Mac doesn't need it),
and CachyOS can't either — Arch owns the system there, so home-manager _is_ the config.
Platform splits happen by **which modules a host imports**, not by `mkIf` — `mkIf`
guards values, not option existence (`wsl.enable` can't be referenced in a Darwin eval
at all).

The Linux side splits three ways, and the distinction matters: `linux.nix` is what every
Linux host shares, `wsl.nix` holds everything that assumes a Windows side exists (the
agent relay, the Windows Warp seeder, the Windows VS Code launcher), and
`generic-linux.nix` holds the non-NixOS distro fixups that would be actively wrong on
NixOS. Orthogonally, `desktop.nix` carries the GUI dotfiles for any machine with a
graphical session — macOS and CachyOS share it; WSL does not, because the GUI apps there
run on the Windows side.

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
shell is set declaratively in `modules/nixos/wsl.nix`. On CachyOS the distro owns
`/etc/passwd`, so that one takes a one-time `chsh` (see [CachyOS
Notes](#cachyos-notes)). Everything is pinned to the
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

**Mac and CachyOS:**

```bash
nh home switch
```

`nh` auto-detects `<user>@<hostname>`, so this resolves to `shane@exodus` on the CachyOS
box and falls back to the `shane` alias on the Mac.

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
only manages Warp's config — settings, themes, and keybindings under `~/.warp` and the
OSS profile's `~/.warp-oss` (`modules/home/warp.nix`; Linux uses XDG paths instead, and
the settings schema itself is shared). The `programs.warp.packageSource` option still lets a
downstream consumer install a Warp build through Nix (e.g. `"stable"` or a source-built
`"local-oss"` fork), but the public hosts here leave it at the default `"none"`.

## CachyOS Notes

`exodus` runs CachyOS (Arch) with Determinate Nix installed alongside it. Arch owns the
system; home-manager owns `$HOME`. GUI apps come from the distro (Warp, Zed, 1Password)
and Nix manages only their config — same division of labour as the Mac's Homebrew.

`modules/home/generic-linux.nix` carries the non-NixOS fixups and must **not** be
imported on a NixOS host: `targets.genericLinux.enable` extends `XDG_DATA_DIRS` so
Nix-installed `.desktop` entries appear in the KDE launcher, and sets `LOCALE_ARCHIVE` so
Nix binaries stop warning against Arch's glibc. NixOS already handles both.

One-time host setup (not Nix-managed):

1. **Bootstrap home-manager**, which isn't installed yet on a fresh box:
   ```bash
   nix run home-manager/release-26.05 -- switch --flake ~/.config/nix#shane@exodus
   ```
   After that first switch, `nh home switch` works.
2. **Make zsh the login shell** — home-manager writes `~/.zshrc` but can't touch
   `/etc/passwd` on a foreign distro:
   ```bash
   chsh -s /usr/bin/zsh
   ```
3. **1Password → Settings → Developer:** enable _Use the SSH agent_. It creates
   `~/.1password/agent.sock`, which is where `publicHome.onepassword.sshAgent` points
   `SSH_AUTH_SOCK`. Commit signing goes through `/opt/1Password/op-ssh-sign`.

Warp on Linux uses XDG paths rather than the Mac's `~/.warp` (`modules/home/warp.nix`
holds the layout table), and the first switch **overwrites** the existing
`~/.config/warp-terminal/settings.toml` with the shared profile — Warp rewrites that file
on any UI toggle, so as on macOS this is a seed-on-switch, not a locked file. Linux-only
deltas belong in the host's `programs.warp.settings` (currently just `system.force_x11`,
for this KDE/Wayland session).

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

## 1Password SSH agent

All three hosts authenticate `ssh`/`git` against the 1Password agent, and all three sign
commits with the same key — only the paths differ, so they are typed options rather than
conditionals in the shell config. `modules/home/onepassword.nix` owns
`publicHome.onepassword.sshAuthSock` (defaulting per platform) and exports
`SSH_AUTH_SOCK`; `publicHome.git.sshSigningProgram` names the signer:

| Host   | Agent socket                       | Signer                              |
| ------ | ---------------------------------- | ----------------------------------- |
| macOS  | `~/Library/Group Containers/...`   | `/Applications/1Password.app/...`   |
| Linux  | `~/.1password/agent.sock` (native) | `/opt/1Password/op-ssh-sign`        |
| WSL    | `~/.1password/agent.sock` (relay)  | none — `ssh-keygen` + relayed agent |

### The WSL relay

WSL has no native agent, so `modules/home/ssh-agent.nix` bridges the Windows 1Password
SSH agent (a named pipe) to a Unix socket at that same Linux path, so keys never leave
1Password. Enabled in the WSL host via `publicHome.onepassword.sshAgentRelay`, which
implies `sshAgent`. The Nix side (socat, `SSH_AUTH_SOCK`, the lazy relay started from zsh) is automatic; these
**Windows-side** steps are manual (not Nix-managed):

1. **1Password for Windows → Settings → Developer:** enable _Use the SSH agent_ (and
   _Integrate with 1Password CLI_ if you want `op`/signing).
2. **Install `npiperelay.exe`** on Windows, e.g. `scoop install npiperelay`. If it lands
   somewhere other than `~/scoop/shims/npiperelay.exe`, set
   `publicHome.onepassword.npiperelay` to the WSL-visible path (`/mnt/c/...`).
3. Open a fresh WSL shell; `ssh-add -l` should list your 1Password keys.
   (`communication with agent failed` means npiperelay isn't found or the agent toggle
   is off.)
