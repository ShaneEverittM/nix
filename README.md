# Nix Configuration

Public, multiplatform Nix configuration. It is a shared home-manager layer plus per-host
assemblies for

- a **NixOS-on-WSL** system (user `shane`, host `nixos`),
- a **bare-metal NixOS desktop** (host `exodus`, KDE Plasma; home-manager folded in as a
  NixOS module), and
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
| `modules/home/onepassword.nix`                 | SSH_AUTH_SOCK for the 1Password agent (per-platform path).           |
| `modules/home/linux.nix`                       | shared Linux layer (WSL + native Linux).                             |
| `modules/home/wsl.nix`                         | WSL-only: Windows VS Code PATH, ssh-agent, warp-wsl.                 |
| `modules/home/generic-linux.nix`               | non-NixOS distro fixups: XDG dirs, locale, fontconfig.               |
| `modules/home/desktop.nix`                     | cross-platform GUI bundle: vscode + zed + warp + jetbrains.          |
| `modules/home/darwin.nix`                      | mac-only layer (imports desktop).                                    |
| `modules/home/{vscode,zed,warp,jetbrains}.nix` | GUI/terminal dotfiles (out-of-store symlinks), per-OS paths.         |
| `modules/home/warp-settings.nix`               | shared Warp settings schema (macOS + Linux + WSL).                   |
| `modules/home/warp-wsl.nix`                    | WSL-only: seeds the Windows-side Warp install.                       |
| `modules/nixos/`                               | NixOS system modules (WSL + exodus).                                 |
| `modules/nixos/common.nix`                     | flakes, system git, nixPath pin (shared by both NixOS hosts).        |
| `modules/nixos/wsl.nix`                        | wsl.\*, openssh, user shane, nix-ld, zsh login shell, stateVersion.  |
| `hosts/wsl/default.nix`                        | nixosConfigurations.nixos (nixos + home wsl).                        |
| `hosts/macbook/default.nix`                    | homeConfigurations."shane@macbook" (home darwin).                    |
| `hosts/exodus/default.nix`                     | nixosConfigurations.exodus (nixos + home linux + desktop).           |
| `hosts/exodus/configuration.nix`               | exodus system layer (KDE Plasma, PipeWire, users, unfree, zsh).      |

Why this shape: home-manager is the one layer every host shares, so the `modules/home/*`
are the real reuse atom. The two Linux hosts (WSL and exodus) run NixOS and fold
home-manager in as a system module (sharing `modules/nixos/common.nix`); the Mac is
standalone home-manager with no nix-darwin (the work Mac can't — MDM owns the system; the
personal Mac doesn't need it). Platform splits happen by **which modules a host imports**,
not by `mkIf` — `mkIf` guards values, not option existence (`wsl.enable` can't be
referenced in a Darwin eval at all).

The Linux side splits three ways, and the distinction matters: `linux.nix` is what every
Linux host shares, `wsl.nix` holds everything that assumes a Windows side exists (the
agent relay, the Windows Warp seeder, the Windows VS Code launcher), and
`generic-linux.nix` holds the non-NixOS distro fixups that would be actively wrong on
NixOS. Both Linux hosts run NixOS today, so `generic-linux.nix` has no in-repo consumer —
it stays exported via `homeModules.genericLinux` for downstream non-NixOS Linux.
Orthogonally, `desktop.nix` carries the GUI dotfiles for any machine with a graphical
session — macOS and exodus share it; WSL does not, because the GUI apps there run on the
Windows side.

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
interactive shell is **zsh everywhere**; macOS already defaults to it, and the two NixOS
hosts set shane's login shell declaratively (`modules/nixos/wsl.nix` for WSL,
`hosts/exodus/configuration.nix` for exodus). Everything is pinned to the
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

**WSL and exodus (both NixOS):**

```bash
nh os switch
```

**Mac:**

```bash
nh home switch
```

`nh os` builds the NixOS host matching the running system's hostname (`nixos` under WSL,
`exodus` on the desktop). `nh home` auto-detects `<user>@<hostname>` and falls back to the
`shane` alias on the Mac.

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

## exodus (NixOS desktop) Notes

`exodus` is a bare-metal NixOS KDE Plasma desktop (formerly CachyOS — see git history).
NixOS owns the whole box, and home-manager is folded in as a NixOS module the same way
the WSL host does it (`hosts/exodus/default.nix`). Apply with `nh os switch`. Unlike the
Mac, the GUI apps are installed **from Nix** here (`vscode`, `jetbrains.idea`,
`claude-code` from stable, plus `warp-terminal` and `zed-editor` from the
`nixpkgs-unstable` lane since they move fast, in the host's `home.packages`, plus the
system-level 1Password), and Nix owns their config via `desktop.nix`. (A Nix-installed
Warp can't self-update from the read-only store, so tracking unstable keeps it close to
current; bump it with `nix flake update nixpkgs-unstable`.)

`hosts/exodus/configuration.nix` is the system layer (KDE Plasma 6 on Wayland, PipeWire,
SDDM, the `shane` account with zsh as the declarative login shell, and a blanket
`nixpkgs.config.allowUnfree` for the desktop apps). `generic-linux.nix` is **not** imported
— its foreign-distro fixups (`XDG_DATA_DIRS`, `LOCALE_ARCHIVE`) are things NixOS already
handles natively.

First-boot setup (not Nix-managed):

1. **Set shane's password:** `passwd` (the config defines the account but no password).
2. **1Password → Settings → Developer:** enable _Use the SSH agent_. It creates
   `~/.1password/agent.sock`, which is where `publicHome.onepassword.sshAgent` points
   `SSH_AUTH_SOCK`. Commit signing goes through the Nix-built 1Password GUI package
   (`${pkgs._1password-gui}/share/1password/op-ssh-sign`, set as
   `publicHome.git.sshSigningProgram`) — verify the binary is present on first run.

**Filesystem (btrfs on a single 1.8 TB NVMe).** One pool on `/dev/nvme0n1p2` with a
separate 1 GB vfat ESP at `/boot`. Three mounted subvolumes: the root **is the top level**
(`subvolid=5`), plus `home` and `nix`. Two more exist but aren't mounted as such —
`/.snapshots` (btrbk's target) and the Craftoria world.

Root on `subvolid=5` is **deliberate**, not a missed step. It costs rootfs snapshot and
rollback, which is accepted: NixOS generations already cover config and package rollback,
and converting to an `@`-style layout is a live-ISO chore. The residual gap is service
state under `/var/lib`, which a generation rollback does *not* revert — a service that
migrates its on-disk format on upgrade can end up as old code against new data. Give those
their own subvolume with a `systemd.tmpfiles` `v` rule (`v /var/lib/foo 0750 foo foo -` —
subvolume where supported, plain directory otherwise; it only acts when the path doesn't
already exist, so it will not convert a directory that's already there). Not worth it for
services that only read config and write logs.

`hosts/exodus/btrfs.nix` holds the mount-time and maintenance half: `compress=zstd`
everywhere, `noatime` additionally on `/nix`, and a monthly scrub. Mount options apply to
new writes only and `nixos-rebuild switch` does not remount a live root — they land on the
next **reboot**, and a one-shot `btrfs filesystem defragment -czstd -r` is what recompresses
what's already on disk. `compsize` (installed) confirms it took. Metadata is `DUP`, so a
scrub self-heals metadata corruption; data is `single`, so scrub *detects* rot there but
cannot repair it. Early warning, not redundancy.

**The Minecraft world is its own NOCOW subvolume** (`world/` under the server dir in
`hosts/exodus/craftoria.nix`) — `.mca` region files are rewritten in place and fragment
badly under CoW. Scoped to `world/` alone and not the whole server tree on purpose: NOCOW
files are neither compressed nor checksummed, and the ~500 MB pack tree is static and
highly compressible, so it stays an ordinary CoW directory. It was created greenfield,
which matters — `chattr +C` must land on an *empty* subvolume, since NOCOW is inherited
only by files created afterward. **Resetting the world is therefore not `rm -rf world`**:
that either fails on the subvolume or removes it outright, and a reflexive `mkdir world`
hands back a CoW directory with no error at all. The ritual (`subvolume delete` →
`subvolume create` → `chattr +C`) is spelled out next to `serverDir`.

`hosts/exodus/btrbk.nix` does weekly timeline snapshots into `/.snapshots`. `home` and the
world are listed **separately** because btrfs snapshots aren't recursive — without that
second line the world would be silently skipped, which is the entire point of having given
it a subvolume. `craftoria.nix` hooks the generated `btrbk-local` unit to quiesce the
server (`save-off` + `save-all`) around the run, so the world snapshot is consistent rather
than merely crash-consistent. Not snapshotted: `/nix` (snapshots pin store paths and would
defeat `nix-collect-garbage`) and `/` (subvolid=5). Snapshots on one disk are not a backup
— the off-box `btrfs send -p` half is deferred until there's a target host.

**GPU (dual-GPU box).** Monitors are wired to the NVIDIA card (Turing RTX 2070 SUPER,
PCI `01:00.0`); the AMD Raphael iGPU (`0f:00.0`) stays on `amdgpu` but drives no display.
`hosts/exodus/configuration.nix` makes NVIDIA the primary driver — proprietary kernel
module, `modesetting.enable` (required for the Plasma 6 Wayland session), `enable32Bit`
for Steam/Proton — with **no PRIME** (that's a laptop concern; here NVIDIA already drives
the outputs). Switching to it swaps `nouveau → nvidia` and rebuilds the initrd, so it
needs a reboot. Warp still needs the `VK_DRIVER_FILES` pin (in `hosts/exodus/default.nix`):
wgpu otherwise enumerates both GPUs, picks the AMD iGPU, fails to present on the
NVIDIA-owned Wayland surface, and Warp crashes on startup and disables Wayland. The pin
lists both the 64- and 32-bit NVIDIA ICDs
(`/run/opengl-driver{,-32}/share/vulkan/icd.d/nvidia_icd.json` — note it's `nvidia_icd.json`,
not the `.x86_64.json` other ICDs use) so 32-bit Vulkan (Steam/Proton) still resolves. It
lands in `~/.config/environment.d` via `systemd.user.sessionVariables`, so it takes effect
on next login.

Warp on Linux uses XDG paths rather than the Mac's `~/.warp` (`modules/home/warp.nix`
holds the layout table), and the first switch **overwrites** the existing
`~/.config/warp-terminal/settings.toml` with the shared profile — Warp rewrites that file
on any UI toggle, so as on macOS this is a seed-on-switch, not a locked file. Linux-only
deltas belong in the host's `programs.warp.settings` (`system.force_x11` and an opacity
override, for this KDE/Wayland session).

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

| Host   | Agent socket                       | Signer                                       |
| ------ | ---------------------------------- | -------------------------------------------- |
| macOS  | `~/Library/Group Containers/...`   | `/Applications/1Password.app/...`            |
| exodus | `~/.1password/agent.sock` (native) | `${pkgs._1password-gui}/…/op-ssh-sign` (Nix) |
| WSL    | `~/.1password/agent.sock` (relay)  | none — `ssh-keygen` + relayed agent          |

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
