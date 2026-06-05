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
  packages.nix         The shared package set: `pkgs -> [ derivations ]`. Consumed by
                       every host's home.packages and by packages.default.
modules/
  home/                home-manager modules (the universal sharing layer):
    common.nix           shared on every host — git, bash, packages, stateVersion.
    linux.nix            Linux-only — /home/shane, WSL VS Code PATH dir.
    darwin.nix           macOS-only — /Users/shane, mac-only bits (both Macs).
  nixos/               NixOS system modules (WSL host only):
    common.nix           flakes, system git, nixPath pin, stateVersion.
    wsl.nix              wsl.*, openssh, users.users.shane, nix-ld.
hosts/
  wsl/default.nix      The `nixosConfigurations.nixos` system (nixos/* + home/{common,linux}).
  macbook/default.nix  Standalone homeConfigurations."shane@macbook" (home/{common,darwin}).
```

Why this shape: home-manager is the one layer every host shares, so the `modules/home/*`
are the real reuse atom; only WSL has a system (NixOS) layer. Neither Mac uses nix-darwin
(the work Mac can't — MDM owns the system; the personal Mac doesn't need it). Platform
splits happen by **which modules a host imports**, not by `mkIf` — `mkIf` guards values,
not option existence (`wsl.enable` can't be referenced in a Darwin eval at all).

Everything is pinned to the **nixos-25.11** release across all inputs, with a single
`nixpkgs` (`follows` threaded through every input).

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
- Shared across all hosts (your packages, git, bash) → `modules/home/common.nix` /
  `lib/packages.nix`
- Linux/WSL-only → `modules/home/linux.nix`, `modules/nixos/*`
- macOS-only → `modules/home/darwin.nix`

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
  `personal.homeModules.default` + `personal.homeModules.darwin`, plus work-only packages;
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
