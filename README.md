# Nix Configuration

Public, multiplatform Nix configuration. It is a shared home-manager layer plus per-host
assemblies for

- a **bare-metal NixOS desktop** (host `exodus`, KDE Plasma; home-manager folded in as a
  NixOS module),
- a **headless NixOS home server** (host `rebirth`, a repurposed laptop; home-manager
  folded in, git + shell modules only), and
- a **personal macOS** machine (standalone home-manager, no nix-darwin)

(A NixOS-on-WSL host existed before the two physical machines did; it was dropped once
they made it redundant — see git history.)

It is also designed to be consumed by private consumers, like at work
[Downstream: the private work repo](#downstream-the-private-work-repo).

## Layout

| Path                                           | Purpose                                                                                 |
| ---------------------------------------------- | --------------------------------------------------------------------------------------- |
| `flake.nix`                                    | inputs + outputs: hosts, home configs, packages, modules.                               |
| `lib/packages.nix`                             | shared CLI package set (`pkgs -> [ derivations ]`), used everywhere.                    |
| `lib/unstable-packages.nix`                    | shared CLI packages that move fast, used everywhere.                                    |
| `lib/identity.nix`                             | single-sourced public identity: login name, name, email, SSH key.                       |
| `lib/nixpkgs-config.nix`                       | narrow shared unfree predicate (standalone home configs).                               |
| `lib/mk-pkgs.nix`                              | the one nixpkgs instantiation every consumer shares.                                    |
| `lib/checks.nix`                               | CI gates: lint checks, downstream contract checks, host builds.                         |
| `files/`                                       | public dotfiles; store or out-of-store per `dotfiles.mode`.                             |
| `Brewfile`                                     | macOS casks/formulae base.                                                              |
| `modules/home/`                                | home-manager modules (the universal sharing layer).                                     |
| `modules/home/default.nix`                     | core bundle: common + git + onepassword + shell + rust + bun + java.                    |
| `modules/home/common.nix`                      | publicHome.\* options, packages, stateVersion, news.silent.                             |
| `modules/home/git.nix`                         | option-driven git; identity via publicHome.git.\*.                                      |
| `modules/home/shell.nix`                       | zsh + zoxide/direnv, eza/bat aliases, uv/mise, Warp auto-warpify.                       |
| `modules/home/rust.nix`                        | rustup + cargo (sanitized cross-compile config).                                        |
| `modules/home/bun.nix`                         | bun runtime + global @types/bun.                                                        |
| `modules/home/java.nix`                        | LTS JDK + gradle, stable JAVA_HOME symlink for JetBrains.                               |
| `modules/home/onepassword.nix`                 | SSH_AUTH_SOCK for the 1Password agent (per-platform path).                              |
| `modules/home/linux.nix`                       | shared Linux layer.                                                                     |
| `modules/home/generic-linux.nix`               | non-NixOS distro fixups: XDG dirs, locale, fontconfig.                                  |
| `modules/home/desktop.nix`                     | cross-platform GUI bundle: vscode + zed + warp + jetbrains.                             |
| `modules/home/darwin.nix`                      | mac-only layer (imports desktop).                                                       |
| `modules/home/{vscode,zed,warp,jetbrains}.nix` | GUI/terminal dotfiles (out-of-store symlinks), per-OS paths.                            |
| `modules/home/warp-settings.nix`               | shared Warp settings schema (macOS + Linux).                                            |
| `modules/nixos/default.nix`                    | shared NixOS base bundle (core + user + ssh + network + memory + btrfs).                |
| `modules/nixos/core.nix`                       | nix settings, nixPath pin, boot, locale, git+neovim, nix-ld, nh.                        |
| `modules/nixos/user.nix`                       | shane account (identity.nix), zsh login shell, home-manager fold-in.                    |
| `modules/nixos/ssh.nix`                        | hardened key-only sshd + tailnet penalty exemption.                                     |
| `modules/nixos/network.nix`                    | avahi mDNS + tailscale + systemd-resolved (split DNS).                                  |
| `modules/nixos/memory.nix`                     | zram + earlyoom baseline.                                                               |
| `modules/nixos/btrfs.nix`                      | compression/scrub/trim for the hosts' identical btrfs layouts.                          |
| `hosts/macbook/default.nix`                    | homeConfigurations."shane@macbook" (home darwin).                                       |
| `hosts/exodus/default.nix`                     | nixosConfigurations.exodus (base bundle + home core/linux/desktop).                     |
| `hosts/exodus/configuration.nix`               | exodus system layer (KDE Plasma, NVIDIA, PipeWire, crash handling).                     |
| `hosts/exodus/minecraft/`                      | exodus Minecraft servers: one generic module (`service.nix`) + the packs it serves.     |
| `hosts/exodus/{btrbk,swap,beszel,cider}.nix`   | exodus services: snapshots, swap tiers, metrics, Cider launcher.                        |
| `hosts/rebirth/default.nix`                    | nixosConfigurations.rebirth (base bundle + home git/shell/CLI set).                     |
| `hosts/rebirth/configuration.nix`              | rebirth system layer (Wi-Fi, lid-switch).                                               |
| `tests/minecraft-console.nix`                  | NixOS VM test for the Minecraft console/sandbox plumbing (both packs).                  |
| `tests/base-smoke.nix`                         | NixOS VM test booting the shared base: sshd hardening on the wire, daemons, hm fold-in. |
| `.zed/settings.json`                           | project-level Zed nixd + format-on-save (Zed-over-SSH on rebirth).                      |

Why this shape: home-manager is the one layer every host shares, so the `modules/home/*`
are the real reuse atom. The two Linux hosts (exodus and rebirth) run NixOS and fold
home-manager in as a system module via the shared base bundle (`modules/nixos/` —
single-concern modules mirroring the home side's shape, with the personal identity from
`lib/identity.nix`); the Mac is standalone home-manager with no nix-darwin (the work Mac
can't — MDM owns the system; the personal Mac doesn't need it). Platform splits happen
by **which modules a host imports**, not by `mkIf` — `mkIf` guards values, not option
existence (a NixOS-only option can't be referenced in a Darwin eval at all).

On the Linux side, `linux.nix` is what every Linux host shares, and `generic-linux.nix`
holds the non-NixOS distro fixups that would be actively wrong on NixOS. All in-repo
Linux hosts run NixOS today, so `generic-linux.nix` has no in-repo consumer — it stays
exported via `homeModules.genericLinux` for downstream non-NixOS Linux. Orthogonally,
`desktop.nix` carries the GUI dotfiles for any machine with a graphical session — macOS
and exodus share it; the headless rebirth does not.

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
interactive shell is **zsh everywhere**; macOS already defaults to it, and the NixOS
hosts set shane's login shell declaratively in the shared base
(`modules/nixos/user.nix`). Everything is pinned to the **nixos-26.05** release across
the baseline inputs, with a single stable `nixpkgs` (`follows` threaded through the main
inputs). A separate `nixpkgs-unstable` input is used only for the small cross-host
package lane in `lib/unstable-packages.nix`, for tools that need to move faster than the
release branch.

## AI Agent Guide

AI coding agents should read [`AGENTS.md`](AGENTS.md) before making changes. It is the
quick-reference version of the repo shape, safety constraints, edit locations, and
validation commands. Claude gets the same guidance via the [`CLAUDE.md`](CLAUDE.md)
symlink, and GitHub Copilot gets a short entrypoint through
[`.github/copilot-instructions.md`](.github/copilot-instructions.md).

## Applying Changes

**exodus and rebirth (both NixOS):**

```bash
nh os switch
```

**Mac:**

```bash
nh home switch
```

`nh os` builds the NixOS host matching the running system's hostname (`exodus` on the
desktop, `rebirth` on the home server). `nh home` auto-detects `<user>@<hostname>` and
falls back to the `shane` alias on the Mac.

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
the settings schema itself is shared). The `programs.warp.packageSource` option still
lets a downstream consumer install a Warp build through Nix (e.g. `"stable"` or a
source-built `"local-oss"` fork), but the public hosts here leave it at the default
`"none"`.

## exodus (NixOS desktop) Notes

`exodus` is a bare-metal NixOS KDE Plasma desktop (formerly CachyOS — see git history).
NixOS owns the whole box, and home-manager is folded in as a NixOS module via the shared
base bundle (`modules/nixos/`). Apply with `nh os switch`. Unlike the Mac, the GUI apps
are installed **from Nix** here (`vscode`, `jetbrains.idea`, `claude-code`, `discord`
from stable, plus `warp-terminal` and `zed-editor` from the `nixpkgs-unstable` lane
since they move fast, in the host's `home.packages`, plus the system-level 1Password),
and Nix owns their config via `desktop.nix`. (A Nix-installed Warp can't self-update
from the read-only store, so tracking unstable keeps it close to current; bump it with
`nix flake update nixpkgs-unstable`.)

`hosts/exodus/configuration.nix` is the system layer (KDE Plasma 6 on Wayland, PipeWire,
SDDM, NVIDIA, crash handling, and — via sibling files — the Minecraft/btrbk/swap/beszel
stack); the `shane` account, zsh login shell, sshd, btrfs tuning, and `allowUnfree` all
come from the shared base. `generic-linux.nix` is **not** imported — its foreign-distro
fixups (`XDG_DATA_DIRS`, `LOCALE_ARCHIVE`) are things NixOS already handles natively.

First-boot setup (not Nix-managed):

1. **Set shane's password:** `passwd` (the config defines the account but no password).
2. **1Password → Settings → Developer:** enable _Use the SSH agent_. It creates
   `~/.1password/agent.sock`, which is where `publicHome.onepassword.sshAgent` points
   `SSH_AUTH_SOCK`. Commit signing goes through the Nix-built 1Password GUI package
   (`${pkgs._1password-gui}/share/1password/op-ssh-sign`, set as
   `publicHome.git.sshSigningProgram`) — verify the binary is present on first run.

**Minecraft servers.** `hosts/exodus/minecraft/` splits into a generic module
(`service.nix`, which owns the systemd unit, console FIFO, RCON wrapper, readiness
probe, sandbox, world subvolume, and btrbk quiescing) and `default.nix`, which declares
the packs via `publicMinecraft.servers.<name>`. Today that's **atm10** (Java 21, starts
at boot) and **craftoria** (Java 25, `autoStart = false`). Only one runs at a time — 14
GiB and a KDE session won't hold two modded heaps, and the failure mode is
thrash-to-livelock rather than a clean OOM kill — so switching packs is
`systemctl stop atm10 && systemctl start craftoria`.

Both deliberately share **25565** (and 25575 for RCON), which is what enforces that:
players keep one address whichever pack is up, and starting a second server without
stopping the first dies at the bind in seconds instead of quietly succeeding and taking
the desktop with it. The tradeoff is that "something answered on RCON" no longer
identifies a pack, so `<name>-console` checks its own unit state before dialing — that
guard is what keeps a shared port from becoming a `save-all` against the wrong world,
and `tests/minecraft-console.nix` asserts it. Worlds are separate subvolumes regardless,
so concurrent packs after the RAM upgrade are a port change plus `autoStart`, not a
migration.

Each server gets `<name>-console` on `PATH` for one-shot or interactive RCON, and
`/run/<name>.stdin` as a write-only console FIFO. Pack installation, `eula.txt`,
`user_jvm_args.txt`, and `server.properties` are out-of-store manual state; the unit's
preflight fails fast and legibly when any of it is missing or when a pack's declared
ports disagree with `server.properties`.

**Filesystem (btrfs on a single 1.8 TB NVMe).** One pool on `/dev/nvme0n1p2` with a
separate 1 GB vfat ESP at `/boot`. Four mounted subvolumes: the root **is the top
level** (`subvolid=5`), plus `home`, `nix`, and `swap` (the disk-swapfile tier, which
has its own first-boot NOCOW ritual — see `hosts/exodus/swap.nix`). Two more exist but
aren't mounted as such — `/.snapshots` (btrbk's target) and one world subvolume per
Minecraft pack.

Root on `subvolid=5` is **deliberate**, not a missed step. It costs rootfs snapshot and
rollback, which is accepted: NixOS generations already cover config and package
rollback, and converting to an `@`-style layout is a live-ISO chore. The residual gap is
service state under `/var/lib`, which a generation rollback does _not_ revert — a
service that migrates its on-disk format on upgrade can end up as old code against new
data. Give those their own subvolume with a `systemd.tmpfiles` `v` rule
(`v /var/lib/foo 0750 foo foo -` — subvolume where supported, plain directory otherwise;
it only acts when the path doesn't already exist, so it will not convert a directory
that's already there). Not worth it for services that only read config and write logs.

The shared `modules/nixos/btrfs.nix` holds the mount-time and maintenance half — both
hosts have the same single-disk layout, so rebirth gets the identical treatment (with a
`publicNixos.btrfs.compression` knob if its laptop CPU ever minds zstd): `compress=zstd`
everywhere, `noatime` additionally on `/nix`, and a monthly scrub. Mount options apply
to new writes only and `nixos-rebuild switch` does not remount a live root — they land
on the next **reboot**, and a one-shot `btrfs filesystem defragment -czstd -r` is what
recompresses what's already on disk. `compsize` (installed) confirms it took. Metadata
is `DUP`, so a scrub self-heals metadata corruption; data is `single`, so scrub
_detects_ rot there but cannot repair it. Early warning, not redundancy.

**Each Minecraft world is its own NOCOW subvolume** (`world/` under the server dir —
`hosts/exodus/minecraft/service.nix` creates it) — `.mca` region files are rewritten in
place and fragment badly under CoW. Scoped to `world/` alone and not the whole server
tree on purpose: NOCOW files are neither compressed nor checksummed, and the ~500 MB
pack tree is static and highly compressible, so it stays an ordinary CoW directory. It
must be created greenfield, which matters — `chattr +C` must land on an _empty_
subvolume, since NOCOW is inherited only by files created afterward. That is why the
module makes it declaratively (`v` + `h … +C` tmpfiles rules at boot, ahead of the unit)
rather than leaving it to a manual ritual. **Resetting a world is therefore still not
`rm -rf world`**: that either fails on the subvolume or removes it outright, and a
reflexive `mkdir world` hands back a CoW directory with no error at all. Stop the unit,
`btrfs subvolume delete <serverDir>/world`, and let `systemd-tmpfiles --create` remake
it.

`hosts/exodus/btrbk.nix` does weekly timeline snapshots into `/.snapshots`. `home` and
each world are listed **separately** because btrfs snapshots aren't recursive — without
those extra lines the worlds would be silently skipped, which is the entire point of
having given them subvolumes. The paths come off
`publicMinecraft.servers.*.worldSubvolume` so they can't drift from the `serverDir` the
units run in. `minecraft/service.nix` hooks the generated `btrbk-local` unit to quiesce
each running server (`save-off` + `save-all flush`) around the run, so the world
snapshots are consistent rather than merely crash-consistent. Not snapshotted: `/nix`
(snapshots pin store paths and would defeat `nix-collect-garbage`) and `/` (subvolid=5).
Snapshots on one disk are not a backup — the off-box `btrfs send -p` half is deferred
until there's a target host.

**GPU (dual-GPU box).** Monitors are wired to the NVIDIA card (Turing RTX 2070 SUPER,
PCI `01:00.0`); the AMD Raphael iGPU (`0f:00.0`) stays on `amdgpu` but drives no
display. `hosts/exodus/configuration.nix` makes NVIDIA the primary driver — proprietary
kernel module, `modesetting.enable` (required for the Plasma 6 Wayland session),
`enable32Bit` for Steam/Proton — with **no PRIME** (that's a laptop concern; here NVIDIA
already drives the outputs). Switching to it swaps `nouveau → nvidia` and rebuilds the
initrd, so it needs a reboot. Warp still needs the `VK_DRIVER_FILES` pin (in
`hosts/exodus/default.nix`): wgpu otherwise enumerates both GPUs, picks the AMD iGPU,
fails to present on the NVIDIA-owned Wayland surface, and Warp crashes on startup and
disables Wayland. The pin lists both the 64- and 32-bit NVIDIA ICDs
(`/run/opengl-driver{,-32}/share/vulkan/icd.d/nvidia_icd.json` — note it's
`nvidia_icd.json`, not the `.x86_64.json` other ICDs use) so 32-bit Vulkan
(Steam/Proton) still resolves. It lands in `~/.config/environment.d` via
`systemd.user.sessionVariables`, so it takes effect on next login.

Warp on Linux uses XDG paths rather than the Mac's `~/.warp` (`modules/home/warp.nix`
holds the layout table), and the first switch **overwrites** the existing
`~/.config/warp-terminal/settings.toml` with the shared profile — Warp rewrites that
file on any UI toggle, so as on macOS this is a seed-on-switch, not a locked file.
Linux-only deltas belong in the host's `programs.warp.settings` (`system.force_x11` and
an opacity override, for this KDE/Wayland session).

## rebirth (NixOS home server) Notes

`rebirth` is a home server built from a repurposed Razer laptop, running headless NixOS
(lid-switch handling is `ignore` so closing the lid doesn't suspend it). It was folded
in from a formerly standalone repo
([`nix-server`](https://github.com/ShaneEverittM/nix-server), now archived — its
pre-merge history lives there), where the host was named `nixos`; it was renamed on
merge because that flake attr then belonged to the since-dropped WSL host. Machine
shape:

- Disk: one btrfs pool — the root is the top level (`subvolid=5`, same deliberate choice
  as exodus), with `home` and `nix` as subvolume mounts; separate vfat `/boot`. The
  shared `modules/nixos/btrfs.nix` applies compression/scrub/trim here too; mount
  options land on the first reboot after a switch.
- Networking: Wi-Fi via `networking.wireless` (wpa_supplicant), mDNS via Avahi
  (reachable as `rebirth.local` on the LAN), plus Tailscale + systemd-resolved from the
  shared base.
- Home-manager is folded in via the shared base (git module + identity), and the host
  adds `shell.nix` plus the shared stable CLI set (`lib/packages.nix`) — no core bundle,
  no GUI dotfiles, no language toolchains, no unstable lane.

### First switch after the fold-in (or a rename)

The box's running hostname must match its flake attr before plain `nh os switch` works:
hostname auto-detection looks for a config named after the machine, and while the
hostname is still `nixos` no such config exists. For the first switch, name the host
explicitly:

```bash
sudo nixos-rebuild switch --flake ~/.config/nix#rebirth
```

(and repoint the `~/.config/nix` checkout at this repo first — same path the old repo
used, so `programs.nh.flake` is unchanged). After that switch the hostname is `rebirth`,
plain `nh os switch` resolves correctly, and the box answers to `rebirth.local` instead
of `nixos.local` — update any `~/.ssh/config` entries on other machines. That last step
is load-bearing, not cosmetic: a `Host` block that no longer matches the new name
silently stops applying `ForwardAgent`, and since this box does all git auth _and_
commit signing through the forwarded agent, the symptom is git failing against GitHub
(auth/signing errors) rather than anything obviously SSH-related.

### Wi-Fi PSK secret

`hosts/rebirth/configuration.nix` references the network's pre-shared key indirectly:

```nix
networking.wireless.networks."Marconi".pskRaw = "ext:psk_Marconi";
networking.wireless.secretsFile = "/etc/wpa_supplicant/wireless.conf";
```

The `ext:psk_Marconi` value tells wpa_supplicant to read a variable named `psk_Marconi`
from `secretsFile`. That file is **not** in this repo (it holds a secret) and must be
created manually on the box:

1. Compute the raw (hashed) PSK from the Wi-Fi passphrase:

   ```bash
   wpa_passphrase Marconi 'YOUR_WIFI_PASSWORD'
   ```

   Copy the `psk=` value (a 64-hex-char string) from the output.

2. Write it into the secrets file as the `psk_Marconi` variable:

   ```bash
   echo 'psk_Marconi=PASTE_THE_64_HEX_HASH_HERE' | sudo tee /etc/wpa_supplicant/wireless.conf
   ```

## 1Password SSH agent

The workstation hosts authenticate `ssh`/`git` against the 1Password agent, and every
host signs commits with the same key — only the paths differ, so they are typed options
rather than conditionals in the shell config. `modules/home/onepassword.nix` owns
`publicHome.onepassword.sshAuthSock` (defaulting per platform) and exports
`SSH_AUTH_SOCK`; `publicHome.git.sshSigningProgram` names the signer:

| Host    | Agent socket                                  | Signer                                       |
| ------- | --------------------------------------------- | -------------------------------------------- |
| macOS   | `~/Library/Group Containers/...`              | `/Applications/1Password.app/...`            |
| exodus  | `~/.1password/agent.sock` (native)            | `${pkgs._1password-gui}/…/op-ssh-sign` (Nix) |
| rebirth | forwarded agent (`ssh -A` from a workstation) | none — `ssh-keygen` + forwarded agent        |

rebirth runs no 1Password app: it has no secrets of its own, and signing/auth work
through the SSH agent forwarded from whichever workstation is connected.
