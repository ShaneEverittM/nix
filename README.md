# nixos-config

Public, platform-agnostic Nix configuration. Despite the legacy repo name, it is
**not WSL-only**: it holds a shared home-manager layer plus per-host assemblies for

- a **NixOS-on-WSL** system (user `shane`, host `nixos`), and
- a personal **macOS** machine (standalone home-manager, no nix-darwin).

A separate **private** repo (the work Mac) consumes this one as a flake input and adds
work-only config; see [Downstream: the private work repo](#downstream-the-private-work-repo).

## Layout

```
flake.nix              Inputs + outputs (nixosConfigurations, homeConfigurations,
                       packages, homeModules, nixosModules).
lib/
  packages.nix         The shared CLI package set: `pkgs -> [ derivations ]`. Consumed
                       by every host's home.packages and by packages.default.
files/                 Dotfiles symlinked into place (live-editable, see configRoot):
                       cargo, vscode, warp themes/settings, ideavimrc.
scripts/hm.ts          Bun helper: build/switch/add/update + Brewfile apply. Mac workflow.
Brewfile               macOS casks/formulae base (Mac-only).
modules/
  home/                home-manager modules (the universal sharing layer):
    default.nix          core bundle: imports common + git + shell + rust + bun.
    common.nix           publicHome.* options, packages, stateVersion, news.silent.
    git.nix              option-driven git (aliases, diff-so-fancy, LFS); identity
                         supplied per-host via publicHome.git.*.
    shell.nix            zsh + zoxide, eza/bat aliases, uv/mise activation.
    rust.nix             rustup + cargo (sanitized cross-compile config).
    bun.nix              bun runtime + global @types/bun.
    linux.nix            Linux-only — WSL VS Code PATH dir.
    darwin.nix           Mac-only bundle — imports vscode + warp + jetbrains.
    vscode.nix warp.nix jetbrains.nix   GUI/terminal dotfiles (out-of-store symlinks).
  nixos/               NixOS system modules (WSL host only):
    common.nix           flakes, system git, nixPath pin, stateVersion.
    wsl.nix              wsl.*, openssh, users.users.shane, nix-ld, zsh login shell.
hosts/
  wsl/default.nix      The `nixosConfigurations.nixos` system (nixos/* + home default+linux).
  macbook/default.nix  Standalone homeConfigurations."shane@macbook" (home default+darwin).
```

Why this shape: home-manager is the one layer every host shares, so the `modules/home/*`
are the real reuse atom; only WSL has a system (NixOS) layer. Neither Mac uses nix-darwin
(the work Mac can't — MDM owns the system; the personal Mac doesn't need it). Platform
splits happen by **which modules a host imports**, not by `mkIf` — `mkIf` guards values,
not option existence (`wsl.enable` can't be referenced in a Darwin eval at all).

The shared modules are **option-driven**: behavior lives in the module, per-machine values
come from the `publicHome.*` options a host sets — `username` (derives `homeDirectory`),
`git.{userName,userEmail,signingKey,sshSigningProgram}`, and `configRoot` (where the repo
is checked out, used by the out-of-store dotfile symlinks). This is what lets the public
modules carry no identity/secrets: each host — and the private work repo — supplies its own.

The interactive shell is **zsh everywhere**; macOS already defaults to it, and WSL's login
shell is set declaratively in `modules/nixos/wsl.nix`. Everything is pinned to the
**nixos-25.11** release across all inputs, with a single `nixpkgs` (`follows` threaded
through every input).

## Applying changes

**WSL (this machine):**

```bash
sudo nixos-rebuild switch --flake .#nixos
```

**Personal Mac:**

```bash
home-manager switch --flake .#shane@macbook
```

Edit the layer that fits the change:
- Shared CLI packages → `lib/packages.nix`
- Shared behavior (git, shell, rust, bun) → the matching `modules/home/*.nix`
- Per-machine values (identity, checkout path) → `publicHome.*` in the host file
- Linux/WSL-only → `modules/home/linux.nix`, `modules/nixos/*`
- macOS-only (GUI/terminal) → `modules/home/darwin.nix` (+ vscode/warp/jetbrains)

The flake is read from the git tree, so **new files must be `git add`-ed** before a
rebuild/switch will see them.

`nixos-rebuild test --flake .#nixos` activates now without touching the boot menu;
`build` just produces a `result` without activating.

## Updating dependencies

```bash
nix flake update          # updates all inputs in flake.lock
# then nixos-rebuild switch / home-manager switch as above
```

To update a single input: `nix flake update nixpkgs`. Commit `flake.lock` alongside any
input change so builds stay reproducible.

## Downstream: the private work repo

The work Mac lives in a separate **private** repo (e.g. `nix-work`) that:

- adds this repo as a flake input (`inputs.personal.inputs.nixpkgs.follows = "nixpkgs"`
  to keep a single nixpkgs);
- defines a standalone `homeConfigurations."shane@work-mac"` importing
  `personal.homeModules.default` + `personal.homeModules.darwin`, then sets its own
  `publicHome.git.{userName,userEmail,signingKey,sshSigningProgram}` and adds the
  work-only bits the public seed deliberately omitted: work session vars / CLI wrappers,
  a private Cargo registry overlay on `~/.cargo/config.toml`, and any work-only packages;
- runs on **Determinate Nix**, so it sets `nix.enable = false` to let Determinate own
  Nix's config (which is why `modules/home/common.nix` carries **no** `nix.*` settings —
  keep it that way);
- pulls secrets at runtime via the **1Password CLI** (`op run` / `op inject`) — nothing
  encrypted/committed, no sops/agenix;
- stays private only for work-internal config, not for secrets.

## Conventions

- **Format Nix files** with `nixfmt` (RFC-style) before committing (`nixfmt`, installed
  via `lib/packages.nix`).
- **Comments explain *why*, not *what*.** Non-obvious WSL workarounds (Windows PATH,
  `code .` support, uid overrides) are documented inline where they live.
- **Commit `flake.lock`** alongside any input change.

## WSL notes

- Some `wsl.wslConf.*` settings (e.g. `interop.appendWindowsPath`) only take effect after
  a full WSL restart: run `wsl --shutdown` from Windows, then reopen the distro.
- The primary user is `shane` (uid 1001); the NixOS-WSL fallback `nixos` account holds
  uid 1000.

## 1Password SSH agent (WSL)

`modules/home/ssh-agent.nix` bridges the Windows 1Password SSH agent (a named pipe) to a
Unix socket in WSL, so `ssh`/`git` here authenticate with keys that never leave 1Password
— nothing on disk. Enabled in the WSL host via `publicHome.onepassword.sshAgentRelay`. The
Nix side (socat, `SSH_AUTH_SOCK`, the lazy relay started from zsh) is automatic; these
**Windows-side** steps are manual (not Nix-managed):

1. **1Password for Windows → Settings → Developer:** enable *Use the SSH agent* (and
   *Integrate with 1Password CLI* if you want `op`/signing).
2. **Install `npiperelay.exe`** on Windows, e.g. `scoop install npiperelay`. If it lands
   somewhere other than `~/scoop/shims/npiperelay.exe`, set
   `publicHome.onepassword.npiperelay` to the WSL-visible path (`/mnt/c/...`).
3. Open a fresh WSL shell; `ssh-add -l` should list your 1Password keys. (`communication
   with agent failed` means npiperelay isn't found or the agent toggle is off.)

**Commit signing** (optional): once the agent is live, set `publicHome.git.signingKey` to
your 1Password SSH *public* key in `hosts/wsl/default.nix` (safe to commit — it's public).
`git.nix` then enables `gpg.format = ssh` + `commit.gpgsign`, and git signs via the relayed
agent (no `op-ssh-sign` needed). See the commented block in `hosts/wsl/default.nix`.
