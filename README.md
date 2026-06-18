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
files/                 Public dotfiles. Hosts choose store-backed copies or live
                       out-of-store symlinks via publicHome.dotfiles.mode. Mergeable
                       Cargo/Warp TOML is generated from Nix modules instead.
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
    linux.nix            Linux-only — WSL VS Code PATH dir; imports ssh-agent + warp-wsl.
    darwin.nix           Mac-only bundle — imports vscode + warp + jetbrains.
    vscode.nix warp.nix jetbrains.nix   GUI/terminal dotfiles (out-of-store symlinks).
    warp-settings.nix    Shared Warp settings schema (themeDir + overrides -> attrs),
                         consumed by warp.nix (macOS) and warp-wsl.nix (WSL).
    warp-wsl.nix         WSL-only — seeds the Windows-side Warp install (opt-in via
                         publicHome.warp.wslConfig).
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
`git.{userName,userEmail,signingKey,sshSigningProgram}`, `repoRoot`,
`dotfiles.mode`, `nh.homeFlake`, and `rust.extraCargoConfig`. Public hosts can keep
live-editable out-of-store dotfile links from their checkout; downstream private
consumers can use store-backed public dotfiles and point `nh` at their own consuming
flake. Mergeable TOML config is generated from Nix attrsets, so downstream consumers
can overlay Cargo and Warp settings without text templates or appended TOML strings.
This is what lets the public modules carry no identity/secrets: each host — and the
private work repo — supplies its own.

The interactive shell is **zsh everywhere**; macOS already defaults to it, and WSL's login
shell is set declaratively in `modules/nixos/wsl.nix`. Everything is pinned to the
**nixos-25.11** release across the baseline inputs, with a single stable `nixpkgs`
(`follows` threaded through the main inputs). A separate `nixpkgs-unstable` input is
used only for the small cross-host package lane in `lib/unstable-packages.nix`, for
tools that need to move faster than the release branch.

## AI agent guide

AI coding agents should read [`AGENTS.md`](AGENTS.md) before making changes. It is the
quick-reference version of the repo shape, safety constraints, edit locations, and
validation commands. Claude gets the same guidance via the [`CLAUDE.md`](CLAUDE.md)
symlink, and GitHub Copilot gets a short entrypoint through
[`.github/copilot-instructions.md`](.github/copilot-instructions.md).

## Applying changes

**WSL (this machine):**

```bash
sudo nixos-rebuild switch --flake .#nixos
```

**Personal Mac:**

```bash
nh home switch
```

Edit the layer that fits the change:
- Shared CLI packages → `lib/packages.nix`
- Fast-moving shared CLI packages → `lib/unstable-packages.nix`
- Shared behavior (git, shell, rust, bun) → the matching `modules/home/*.nix`
- Per-machine values (identity, checkout path) → `publicHome.*` in the host file
- Linux/WSL-only → `modules/home/linux.nix`, `modules/nixos/*`
- macOS-only (GUI/terminal) → `modules/home/darwin.nix` (+ vscode/warp/jetbrains)
- Mergeable Cargo/Warp TOML → generated inside the owning Nix module

The flake is read from the git tree, so **new files must be `git add`-ed** before a
rebuild/switch will see them.

`nixos-rebuild test --flake .#nixos` activates now without touching the boot menu;
`build` just produces a `result` without activating.

## Updating dependencies

```bash
nix flake update          # updates all inputs in flake.lock
# then nixos-rebuild switch / nh home switch as above
```

To update a single input: `nix flake update nixpkgs` or
`nix flake update nixpkgs-unstable`. Commit `flake.lock` alongside any input change so
builds stay reproducible.

## Downstream: the private work repo

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
- pulls secrets at runtime via the **1Password CLI** (`op run` / `op inject`) — nothing
  encrypted/committed, no sops/agenix;
- stays private only for work-internal config, not for secrets;
- can set `publicHome.dotfiles.mode = "store"` and `publicHome.nh.homeFlake` to its own
  private repo so public dotfiles come from the flake input while `nh home` acts on the
  downstream configuration. If the downstream configuration name is not
  auto-detectable from `<username>@<hostname>` or `<username>`, expose a matching
  `homeConfigurations` alias in the downstream flake.

## Conventions

- **Format Nix files** with `nixfmt` (RFC-style) before committing (`nixfmt`, installed
  via `lib/packages.nix`).
- **Comments explain *why*, not *what*.** Non-obvious WSL workarounds (Windows PATH,
  `code .` support, uid overrides) are documented inline where they live.
- **Commit `flake.lock`** alongside any input change.

## macOS notes

- The source-built `warp` fork input compiles Metal shaders, so it needs host Xcode
  tooling that Nix can't provide. The base Command Line Tools are **not** enough: since
  Xcode 16 / macOS Sequoia the Metal compiler ships as a separate downloadable component,
  and the `xcodebuild -downloadComponent` mechanism only exists in **full Xcode** (the CLT
  has no `xcodebuild`). Install full Xcode, then:

  ```bash
  # Point the active developer dir at full Xcode (away from /Library/Developer/CommandLineTools)
  sudo xcode-select -s /Applications/Xcode.app/Contents/Developer
  sudo xcodebuild -license accept

  # Metal compiler — separate component since Xcode 16
  xcodebuild -downloadComponent MetalToolchain
  ```

  Verify the Metal toolchain is present with `xcrun -f metal`. Only needed when a host
  sets `programs.warp.packageSource = "local-oss"`.

## WSL notes

- Some `wsl.wslConf.*` settings (e.g. `interop.appendWindowsPath`) only take effect after
  a full WSL restart: run `wsl --shutdown` from Windows, then reopen the distro.
- The primary user is `shane` (uid 1001); the NixOS-WSL fallback `nixos` account holds
  uid 1000.

## Warp on WSL

Warp under WSL is a **Windows** app, so its config lives on the Windows filesystem and
can't be a nix-store symlink (Warp.exe can't follow one). `modules/home/warp-wsl.nix`
therefore *copies* Nix-generated config onto `/mnt/c` during `nixos-rebuild switch`
(declarative content, imperative placement), gated by `publicHome.warp.wslConfig`:

- **settings** → `%LOCALAPPDATA%\warp\Warp\config\settings.toml`
- **themes** → `%APPDATA%\warp\Warp\data\themes\*.yaml` (JetBrains dark/light)

The settings schema is shared with the Macs (`modules/home/warp-settings.nix`); only the
`themeDir` baked into the TOML differs (a `C:/Users/...` path Warp resolves). Override the
Windows account with `publicHome.warp.windowsUser` (defaults to `publicHome.username`) and
merge extra settings via `publicHome.warp.extraSettings`.

Caveat: Warp **rewrites `settings.toml` at runtime** (any UI toggle), so this is a
seed-on-switch, not a locked file — the same trade-off the macOS module accepts.
Restart Warp after a switch to pick up changes.

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
