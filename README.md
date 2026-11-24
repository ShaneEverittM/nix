# Nix Configuration

Public, multiplatform Nix configuration. It is a shared home-manager layer plus per-host
assemblies for

- a **headless NixOS dev/server box** (host `retreat`, bare metal; home-manager folded
  in as a NixOS module),
- a **headless NixOS home server** (host `rebirth`, a repurposed laptop; home-manager
  folded in, git + shell modules only),
- a **personal macOS** machine (standalone home-manager, no nix-darwin), and
- a **CachyOS desktop** (host `hope`, KDE; standalone home-manager on a non-NixOS
  distro)

(A NixOS-on-WSL host existed before the two physical machines did; it was dropped once
they made it redundant — see git history.)

It is also designed to be consumed by private consumers, like at work
[Downstream: the private work repo](#downstream-the-private-work-repo).

## Layout

| Path                                           | Purpose                                                                                              |
| ---------------------------------------------- | ---------------------------------------------------------------------------------------------------- |
| `flake.nix`                                    | inputs + outputs: hosts, home configs, packages, modules.                                            |
| `lib/packages.nix`                             | shared CLI package set (`pkgs -> [ derivations ]`), used everywhere.                                 |
| `lib/unstable-packages.nix`                    | shared CLI packages that move fast, used everywhere.                                                 |
| `lib/identity.nix`                             | single-sourced public identity: login name, name, email, SSH key.                                    |
| `lib/nixpkgs-config.nix`                       | narrow shared unfree predicate (standalone home configs).                                            |
| `lib/mk-pkgs.nix`                              | the one nixpkgs instantiation every consumer shares.                                                 |
| `lib/checks.nix`                               | CI gates: lint checks, downstream contract checks, host builds.                                      |
| `pyproject.toml`, `uv.lock`                    | project-local Python tooling for NixOS VM test scripts.                                              |
| `files/`                                       | public dotfiles; store or out-of-store per `dotfiles.mode`.                                          |
| `Brewfile`                                     | macOS casks/formulae base.                                                                           |
| `modules/home/`                                | home-manager modules (the universal sharing layer).                                                  |
| `modules/home/default.nix`                     | core bundle: common + git + onepassword + ssh + shell + rust + bun + java.                           |
| `modules/home/common.nix`                      | publicHome.\* options, packages, stateVersion, news.silent.                                          |
| `modules/home/git.nix`                         | option-driven git; identity via publicHome.git.\*.                                                   |
| `modules/home/shell.nix`                       | zsh + zoxide/direnv, eza/bat aliases, uv/mise, Warp auto-warpify.                                    |
| `modules/home/rust.nix`                        | rustup + cargo (sanitized cross-compile config).                                                     |
| `modules/home/bun.nix`                         | bun runtime + global @types/bun.                                                                     |
| `modules/home/java.nix`                        | LTS JDK + gradle, stable JAVA_HOME symlink for JetBrains.                                            |
| `modules/home/onepassword.nix`                 | SSH_AUTH_SOCK for the 1Password agent (per-platform path).                                           |
| `modules/home/ssh.nix`                         | owns `~/.ssh/config`: host aliases for this repo's machines + a local include.                       |
| `modules/home/linux.nix`                       | shared Linux layer.                                                                                  |
| `modules/home/generic-linux.nix`               | non-NixOS distro fixups: XDG dirs, locale, fontconfig.                                               |
| `modules/home/desktop.nix`                     | cross-platform GUI bundle: vscode + zed + warp + jetbrains.                                          |
| `modules/home/darwin.nix`                      | mac-only layer (imports desktop).                                                                    |
| `modules/home/{vscode,zed,warp,jetbrains}.nix` | GUI/terminal dotfiles (out-of-store symlinks), per-OS paths.                                         |
| `modules/home/warp-settings.nix`               | shared Warp settings schema (macOS + Linux).                                                         |
| `modules/nixos/default.nix`                    | shared NixOS base bundle (core + user + ssh + network + memory + btrfs).                             |
| `modules/nixos/core.nix`                       | nix settings, nixPath pin, boot, locale, git+neovim, nix-ld, nh.                                     |
| `modules/nixos/user.nix`                       | shane account (identity.nix), zsh login shell, home-manager fold-in.                                 |
| `modules/nixos/ssh.nix`                        | hardened key-only sshd + tailnet penalty exemption.                                                  |
| `modules/nixos/network.nix`                    | avahi mDNS + tailscale + systemd-resolved (split DNS).                                               |
| `modules/nixos/memory.nix`                     | zram + earlyoom baseline.                                                                            |
| `modules/nixos/btrfs.nix`                      | compression/scrub/trim for the hosts' identical btrfs layouts.                                       |
| `hosts/macbook/default.nix`                    | homeConfigurations."shane@macbook" (home darwin).                                                    |
| `hosts/hope/default.nix`                       | homeConfigurations."shane@hope" (home linux, non-NixOS).                                             |
| `hosts/retreat/default.nix`                    | nixosConfigurations.retreat (base bundle + home core/linux + claude-code).                           |
| `hosts/retreat/configuration.nix`              | retreat system layer (headless: networking, 1Password CLI, memory + coredump limits).                |
| `hosts/retreat/minecraft/`                     | retreat Minecraft servers: packs, options, guest module (`service.nix`), host module (`host.nix`).   |
| `hosts/retreat/gameservers.nix`                | microVM layer for public game servers: isolation firewall, port forwards, `gameserver` command.      |
| `hosts/retreat/{btrbk,swap,beszel}.nix`        | retreat services: snapshots, swap tiers, metrics.                                                    |
| `hosts/retreat/sure.nix`                       | Sure personal-finance app: upstream containers under podman, tailnet-only.                           |
| `hosts/retreat/enshrouded.nix`                 | Enshrouded dedicated server: community Proton container under podman, in its own microVM, UDP 15637. |
| `hosts/retreat/plex.nix`                       | Plex Media Server (native): LAN + tailnet, media in `/srv/media`, not internet-facing.               |
| `hosts/retreat/timelock.nix`                   | `timelock` command: a CPU-bound delay (time-lock puzzle) in front of admin credentials.              |
| `hosts/retreat/tailscale-serve.nix`            | `publicTailscale.serve.*`: declarative tailnet-only HTTPS proxies (beszel, sure).                    |
| `hosts/rebirth/default.nix`                    | nixosConfigurations.rebirth (base bundle + home git/shell/CLI set).                                  |
| `hosts/rebirth/configuration.nix`              | rebirth system layer (Wi-Fi, lid-switch).                                                            |
| `tests/minecraft-console.nix`                  | NixOS VM test for the Minecraft guest module: console/sandbox plumbing, snapshot listener.           |
| `tests/gameservers.nix`                        | NixOS VM test for the game-server host layer: guest isolation firewall, `gameserver` state.          |
| `tests/base-smoke.{nix,py}`                    | NixOS VM test booting the shared base: assembly + Python behavior assertions.                        |
| `.zed/settings.json`                           | project-level Zed nixd + format-on-save (Zed-over-SSH on rebirth).                                   |

Why this shape: home-manager is the one layer every host shares, so the `modules/home/*`
are the real reuse atom. The two Linux hosts (retreat and rebirth) run NixOS and fold
home-manager in as a system module via the shared base bundle (`modules/nixos/` —
single-concern modules mirroring the home side's shape, with the personal identity from
`lib/identity.nix`); the Mac is standalone home-manager with no nix-darwin (the work Mac
can't — MDM owns the system; the personal Mac doesn't need it). Platform splits happen
by **which modules a host imports**, not by `mkIf` — `mkIf` guards values, not option
existence (a NixOS-only option can't be referenced in a Darwin eval at all).

On the Linux side, `linux.nix` is what every Linux host shares, and `generic-linux.nix`
holds the non-NixOS distro fixups that would be actively wrong on NixOS. Its one in-repo
consumer is `hope` (CachyOS); it is also exported via `homeModules.genericLinux` for
downstream non-NixOS Linux. Orthogonally, `desktop.nix` carries the GUI dotfiles for any
machine with a graphical session — the Macs and `hope`; the headless NixOS hosts
(retreat, rebirth) do not import it.

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

**retreat and rebirth (both NixOS):**

```bash
nh os switch
```

**Mac and hope (both standalone home-manager):**

```bash
nh home switch
```

`nh os` builds the NixOS host matching the running system's hostname (`retreat` on the
dev box, `rebirth` on the home server). `nh home` auto-detects `<user>@<hostname>`
(`shane@hope` on the CachyOS desktop) and falls back to the `shane` alias on the Mac.

Edit the layer that fits the change, then rebuild. The flake is read from the git tree,
so **new files must be `git add`-ed** before a rebuild/switch will see them.

`nh os test` activates now without touching the boot menu; `build` just produces a
`result` without activating.

The NixOS VM tests keep their behavior assertions in normal Python files, which the Nix
test assembly loads into the test driver. The small project-local `uv` environment keeps
that code formatted and linted:

```bash
uv run ruff format --check tests
uv run ruff check tests
```

For editor type resolution, run `./scripts/refresh-nixos-test-driver-types` after
cloning and whenever the locked `nixpkgs` input changes. It creates an ignored link to
the pinned test-driver source, which basedpyright uses for the driver API types.

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

## hope (CachyOS desktop) Notes

`hope` is a KDE desktop running CachyOS. Arch owns the system (packages, display
manager, login shell, the 1Password and Warp apps); Nix is installed alongside it and
home-manager owns only the home directory, exactly like the Mac.
`modules/home/generic-linux.nix` bridges the foreign distro and the Nix store.

One-time bootstrap, after installing Nix (with flakes enabled):

```bash
# nh isn't on PATH until the first activation, so run home-manager straight from the
# flake. -b moves the distro's stock ~/.zshrc, ~/.bashrc and any hand-written
# ~/.ssh/config aside instead of refusing to activate over them.
nix run home-manager/release-26.05 -- switch -b backup --flake ~/.config/nix#shane@hope
```

After that, `nh home switch` is enough. The shared shell config is zsh, but CachyOS
defaults the login shell to fish and the distro owns `/etc/passwd`, so switch it once
with `chsh -s /usr/bin/zsh`.

## retreat (headless NixOS dev box) Notes

`retreat` is a bare-metal headless NixOS box on a Minisforum MS-A2 (the install was
moved over on its NVMe from the retired `exodus` tower, and was CachyOS before that —
see git history). It was a KDE Plasma desktop, then a headless box with an on-demand
Plasma session streamed over Sunshine; the whole graphical stack (SDDM, Plasma,
PipeWire, Sunshine, Firefox, the 1Password app, and the Nix-installed GUI apps) has
since been removed, so it boots to `multi-user.target` and is reached over SSH (LAN or
tailnet) or the text console. NixOS owns the whole box, and home-manager is folded in as
a NixOS module via the shared base bundle (`modules/nixos/`). Apply with `nh os switch`.

Unlike `rebirth` it keeps the full workstation home layer (core bundle + `linux.nix`:
git, shell, rust, bun, java, the shared CLI sets) plus `claude-code`, because
development still happens here — just remotely. `desktop.nix` is not imported.

`hosts/retreat/configuration.nix` is the system layer (the wired uplink on
systemd-networkd, the 1Password CLI, memory tuning, coredump bounds, and — via sibling
files — the Minecraft/btrbk/swap/beszel/sure/enshrouded/plex/timelock stack); the
`shane` account, zsh login shell, sshd, btrfs tuning, and `allowUnfree` all come from
the shared base. `generic-linux.nix` is **not** imported — its foreign-distro fixups
(`XDG_DATA_DIRS`, `LOCALE_ARCHIVE`) are things NixOS already handles natively.

First-boot setup (not Nix-managed):

1. **Set shane's password:** `passwd` (the config defines the account but no password).
2. **Connect with agent forwarding.** There is no 1Password app on the box, so it has no
   SSH agent or signer of its own: git pushes and commit signing use the agent forwarded
   from the connecting workstation (`ForwardAgent` is already set for `retreat` in
   `modules/home/ssh.nix`), with git signing through plain `ssh-keygen`. From the local
   console there is no agent, so signed commits and pushes don't work there.

**Game servers run in microVMs.** The game servers are the only things on retreat that
take traffic from the open internet, and a large modded Minecraft pack, or a
closed-source Windows server under Proton, is exactly the kind of software that gets
exploited. A systemd sandbox or a container shares the host kernel, so each server
instead gets its own guest kernel behind KVM
([microvm.nix](https://github.com/microvm-nix/microvm.nix)), holding its game's files
and nothing else. `hosts/retreat/gameservers.nix` is the game-agnostic layer:

- **Network.** Each server sits on a routed point-to-point tap (`10.77.<slot>.2`). The
  host forwards the game's public port to it and gives it outbound internet; the
  firewall refuses a guest everything else — the host itself, the LAN, the tailnet,
  other guests. `tests/gameservers.nix` asserts that with a network namespace playing a
  compromised guest.
- **On and off is state, not config.** Every server is always declared; which ones run
  is a flag per server, changed without a rebuild:

  ```bash
  gameserver list                # boot flag, state, and players online
  gameserver enable craftoria    # start now and at boot (takes over a shared slot)
  gameserver disable craftoria   # stop and stay off
  gameserver restart atm10       # also how a guest picks up a rebuilt system
  gameserver logs atm10          # the guest's console: the server log
  ```

  `autoStart` only seeds the flags on first activation. A rebuild never restarts a
  running guest, so an unrelated `nh os switch` does not kick players.

- **No way in.** A guest has no sshd, no password and no key. Its console is the host
  unit's journal; its system is the host's `/nix/store`, shared read-only.

**Minecraft servers.** `hosts/retreat/minecraft/` is four files: `default.nix` declares
the packs via `publicMinecraft.servers.<name>`; `options.nix` holds the option
declarations; `service.nix` is the **guest** half (the systemd unit, readiness probe,
sandbox, and the snapshot hooks); `host.nix` is the **host** half (pack storage, world
subvolumes, btrbk hooks, one guest per pack). Today that's **atm10** (Java 21, enabled
by default) and **craftoria** (Java 25, disabled by default).

Both deliberately share **25565**, which puts them on one network slot: starting either
stops the other, and players keep one address whichever is up. Running both at once is a
port change on one of them.

Pack trees live in `/var/lib/minecraft/<pack>`, owned by a dedicated `minecraft` account
(fixed UID 25565 on the host and in every guest) and shared into the pack's guest at the
same path. They are deliberately not under a home directory: a share exposes everything
beneath it. To work on a pack by hand, `sudo -u minecraft -s`. Pack installation,
`eula.txt`, `user_jvm_args.txt`, and `server.properties` are out-of-store manual state;
the unit's preflight fails fast and legibly when any of it is missing or when a pack's
declared ports disagree with `server.properties`. A guest's RAM (`memory`) is a hard
ceiling and must stay roughly 3 GiB above `-Xmx` in `user_jvm_args.txt`.

RCON and the console FIFO still exist, but only inside the guest, where the readiness
probe and the snapshot hooks use them; there is no operator console on the host. Run
server commands in-game.

**Filesystem (btrfs on a single 1.8 TB NVMe).** One pool on `/dev/nvme0n1p2` with a
separate 1 GB vfat ESP at `/boot`. Four mounted subvolumes: the root **is the top
level** (`subvolid=5`), plus `home`, `nix`, and `swap` (the disk-swapfile tier, which
has its own first-boot NOCOW ritual — see `hosts/retreat/swap.nix`). Two more exist but
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
`hosts/retreat/minecraft/host.nix` creates it) — `.mca` region files are rewritten in
place and fragment badly under CoW. Scoped to `world/` alone and not the whole server
tree on purpose: NOCOW files are neither compressed nor checksummed, and the ~500 MB
pack tree is static and highly compressible, so it stays an ordinary CoW directory. It
must be created greenfield, which matters — `chattr +C` must land on an _empty_
subvolume, since NOCOW is inherited only by files created afterward. That is why the
module makes it declaratively (`v` + `h … +C` tmpfiles rules at boot, ahead of the
guest) rather than leaving it to a manual ritual. **Resetting a world is therefore still
not `rm -rf world`**: that either fails on the subvolume or removes it outright, and a
reflexive `mkdir world` hands back a CoW directory with no error at all. Stop the guest,
`btrfs subvolume delete <serverDir>/world`, and let `systemd-tmpfiles --create` remake
it.

`hosts/retreat/btrbk.nix` does twice-daily timeline snapshots into `/.snapshots`. `home`
and each world are listed **separately** because btrfs snapshots aren't recursive —
without those extra lines the worlds would be silently skipped, which is the entire
point of having given them subvolumes. The paths come off
`publicMinecraft.servers.*.worldSubvolume` so they can't drift from the `serverDir` the
units run in, and each carries an explicit `snapshot_name` of `<pack>-world`. That name
is load-bearing with more than one pack: it defaults to the subvolume's basename, and
every world subvolume is called `world`, so the default would file two different worlds
under one name in one `snapshot_dir` — disambiguated only positionally by btrbk's `_N`
collision suffix, and thinned as a single series by retention, since btrbk identifies a
snapshot set by `snapshot_name` + `snapshot_dir`. `minecraft/host.nix` hooks the
generated `btrbk-local` unit to quiesce each running server around the run: it asks the
pack's guest to `save-off` + `save-all flush` and then sync through to the host, since
the snapshot is taken by the host's kernel on a world the guest's kernel is writing
(`minecraft/service.nix` has the listener), so the world snapshots are consistent rather
than merely crash-consistent. Not snapshotted: `/nix` (snapshots pin store paths and
would defeat `nix-collect-garbage`) and `/` (subvolid=5). Snapshots on one disk are not
a backup — they die with the fs, which a power loss (no UPS) can corrupt wholesale, not
just tear a NOCOW file — so each snapshot is also pushed off-box with `btrfs send -p` to
`rebirth`. rebirth authorizes the receive via `services.btrbk.sshAccess` in
`hosts/rebirth/btrbk.nix` (a dedicated `btrbk` user, its key pinned to
`ssh_filter_btrbk.sh` as a forced command with a NOPASSWD sudo rule for `btrfs receive`,
so `PermitRootLogin=no` stays intact). The push needs a dedicated SSH key that is
**not** in this repo — see the bootstrap below.

**Off-box replication key (manual secret).** Like the Wi-Fi PSK, the private key lives
out-of-band, referenced by path (`ssh_identity` in `hosts/retreat/btrbk.nix`). It is
low-value and disposable — rebirth pins it to a receive-only forced command, so a lost
key just means regenerating and re-committing the public half:

1. Generate the dedicated keypair on retreat, as the `btrbk` service user:

   ```bash
   sudo -u btrbk ssh-keygen -t ed25519 -f /var/lib/btrbk/.ssh/id_ed25519 -N "" \
     -C "btrbk retreat->rebirth"
   ```

   `-N ""` (no passphrase) is required for the unattended service; the private half
   stays at `0700` under `/var/lib/btrbk/.ssh`, never in the repo.

2. Copy the **public** half into rebirth's receiver config — the
   `services.btrbk.sshAccess` entry's `key` in `hosts/rebirth/btrbk.nix` — and commit it
   (a public key is safe to publish):

   ```bash
   sudo cat /var/lib/btrbk/.ssh/id_ed25519.pub
   ```

3. Switch **rebirth first** (creates the `btrbk` user, authorized key, sudo rule, and
   receive dir), then retreat. Validate before moving data with a dry run — it also
   auto-accepts rebirth's host key on first contact:

   ```bash
   sudo -u btrbk btrbk -c /etc/btrbk/local.conf dryrun
   ```

   The first real run is a full baseline (`home` + both worlds); do it on the **LAN**.

**Sure (personal finance).** `hosts/retreat/sure.nix` runs
[Sure](https://github.com/we-promise/sure) from the upstream image as five podman
containers (web, Sidekiq worker, Postgres, Redis, and upstream's own backup tool) -- the
project's compose file transcribed to `virtualisation.oci-containers`, with the version
pinned. It is reachable only over Tailscale, at `https://<tailnet name>:8443`; nothing
is opened in the firewall. There is no manual secret step: a oneshot generates
`/var/lib/sure/config/.env` on first start and never rewrites it. Nightly backup bundles
(database dump, uploaded files and that `.env`) land in `/var/lib/sure/backups`, which
is its own subvolume in the btrbk timeline and so is replicated to rebirth. The first
account registered becomes the admin, so create it straight after the first switch.
Backup, restore and upgrade commands are in the module header.

**Plex.** `hosts/retreat/plex.nix` runs Plex Media Server from nixpkgs, on the host. Its
ports are open in the firewall so TVs and consoles on the LAN find it, and tailnet
devices reach it at `http://retreat:32400/web`; nothing is forwarded on the router, and
Plex's own Remote Access should stay off. Media goes in `/srv/media/{movies,tv}` (its
own subvolume, owned by the login user, deliberately outside the btrbk timeline); the
library database in `/var/lib/plex` is not backed up off-box either. A fresh server can
only be claimed from the machine itself, so the first sign-in goes through
`ssh -L 32400:localhost:32400 retreat` and `http://localhost:32400/web`.

**Enshrouded.** `hosts/retreat/enshrouded.nix` runs an
[Enshrouded](https://enshrouded.com) dedicated server from the community
[mornedhels/enshrouded-server](https://github.com/mornedhels/enshrouded-server) image
(the Windows server under GE-Proton; Keen ships no Linux build), version-pinned, on
UDP 15637. Like the Minecraft packs it runs in its own microVM
(`gameserver ... enshrouded`); podman runs _inside_ that guest, as packaging rather than
as the security boundary. State lives on the host in `/var/lib/enshrouded`, shared into
the guest: the game install, the world in its own `savegame` subvolume (in the btrbk
timeline, so replicated to rebirth), and `secrets.env`, the per-role join passwords a
oneshot generates on first start. The container image store is a guest-private disk
image, re-pullable and not backed up. The server updates the game itself while nobody is
connected. Importing a client-hosted world and the day-to-day commands are in the module
header.

**GPU.** `retreat` has one Radeon iGPU on the in-kernel `amdgpu` driver, which now only
drives the text console: with no graphical session there is no `hardware.graphics`,
`videoDrivers`, or `hardware.nvidia` in the config. (See git history for the desktop-era
setup, and for `exodus`'s NVIDIA configuration before that.)

## rebirth (NixOS home server) Notes

`rebirth` is a home server built from a repurposed Razer laptop, running headless NixOS
(lid-switch handling is `ignore` so closing the lid doesn't suspend it). It was folded
in from a formerly standalone repo
([`nix-server`](https://github.com/ShaneEverittM/nix-server), now archived — its
pre-merge history lives there), where the host was named `nixos`; it was renamed on
merge because that flake attr then belonged to the since-dropped WSL host. Machine
shape:

- Disk: one btrfs pool — the root is the top level (`subvolid=5`, same deliberate choice
  as retreat), with `home` and `nix` as subvolume mounts; separate vfat `/boot`. The
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
| hope    | `~/.1password/agent.sock` (native)            | `/opt/1Password/op-ssh-sign` (distro)        |
| retreat | `~/.1password/agent.sock` (native)            | `${pkgs._1password-gui}/…/op-ssh-sign` (Nix) |
| rebirth | forwarded agent (`ssh -A` from a workstation) | none — `ssh-keygen` + forwarded agent        |

rebirth runs no 1Password app: it has no secrets of its own, and signing/auth work
through the SSH agent forwarded from whichever workstation is connected.

The same applies to a workstation reached over SSH: its own 1Password app can't be
unlocked from a remote session, so `modules/home/git.nix` wraps the signer and falls
back to `ssh-keygen` + the forwarded agent whenever `SSH_CONNECTION` is set and
`SSH_AUTH_SOCK` is a live socket (an `ssh -A` session, or a JetBrains remote backend).

## SSH client config

`modules/home/ssh.nix` owns `~/.ssh/config`, so home-manager writes the whole file and
refuses to activate over a hand-written one (`Existing file … would be clobbered` — move
it aside, or switch once with `nh home switch -b bak`). It carries the `rebirth` and
`retreat` aliases; `onepassword.nix` appends the `IdentityAgent` blocks on top of it.

Block order is load-bearing: ssh_config keeps the **first** value it sees for a keyword,
so the per-host blocks are `lib.hm.dag.entryBefore [ "forwarded-agent" "default" ]` to
sort above the `Host *` block that carries the agent socket. A DAG edge to an absent
entry is a no-op, so that ordering still holds on a host where `sshAgent` is off and
neither entry exists.

Anything that shouldn't be public — a host reachable only by its WAN address, say — goes
in `~/.ssh/config.local`, which this module `Include`s ahead of every managed block.
That file is unmanaged and outside the checkout; OpenSSH skips the include silently when
it doesn't exist, so hosts without one need no opt-out.
