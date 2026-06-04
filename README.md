# nixos-config

Declarative configuration for a **NixOS-on-WSL** system, built as a Nix flake.
It manages both the system (via [NixOS-WSL](https://github.com/nix-community/NixOS-WSL))
and the user environment (via [home-manager](https://github.com/nix-community/home-manager))
for user `shane` on host `nixos`.

## Layout

| File | Purpose |
|------|---------|
| [`flake.nix`](flake.nix) | Entry point. Pins inputs (nixpkgs, NixOS-WSL, home-manager) and wires them into the `nixosConfigurations.nixos` system. |
| [`flake.lock`](flake.lock) | Exact, reproducible versions of every input. Commit changes to this file. |
| [`configuration.nix`](configuration.nix) | System-level config: WSL options, user accounts, SSH, nix-ld, system packages, `stateVersion`. |
| [`home.nix`](home.nix) | User-level config (home-manager): user packages, git identity, bash, `home.sessionPath`. |
| `result` | Symlink to the last build output. Git-ignored. |

Everything is pinned to the **nixos-25.11** release across all inputs.

## Applying changes

This is a flake-based config, so all commands reference the flake and its
output name (`nixos`).

**1. Edit** the relevant file:
- System-wide changes (services, users, WSL, system packages) → `configuration.nix`
- Per-user changes (your packages, dotfiles, git config) → `home.nix`

**2. Rebuild and switch** (home-manager is wired into the system config, so a
single command applies both):

```bash
sudo nixos-rebuild switch --flake .#nixos
```

Run this from the repo root. `.#nixos` selects `nixosConfigurations.nixos`
defined in `flake.nix`. `git` must be staged-or-tracked aware: the flake is
read from the git tree, so **new files must be `git add`-ed** before a rebuild
will see them.

**3. Test without making it the boot default** (optional):

```bash
sudo nixos-rebuild test --flake .#nixos
```

`test` activates the new config now but doesn't add it to the boot menu;
`switch` does both. Use `build` to just produce a `result` without activating.

## Updating dependencies

To pull newer versions of nixpkgs / home-manager / NixOS-WSL within the
25.11 release:

```bash
nix flake update          # updates all inputs in flake.lock
sudo nixos-rebuild switch --flake .#nixos
```

To update a single input: `nix flake update nixpkgs`.

## Conventions in this repo

- **Format Nix files** with `nixfmt` (RFC-style) before committing — it's
  installed via `home.nix` and surfaced as `nixfmt`.
- **Comments explain *why*, not *what*.** Several non-obvious WSL workarounds
  (Windows PATH handling, `code .` support, uid overrides) are documented inline
  where they live — read them before changing those blocks.
- **Commit `flake.lock`** alongside any input change so builds stay reproducible.

## WSL notes

- Some `wsl.wslConf.*` settings (e.g. `interop.appendWindowsPath`) only take
  effect after a full WSL restart: run `wsl --shutdown` from Windows, then
  reopen the distro.
- The primary user is `shane` (uid 1001); the NixOS-WSL fallback `nixos`
  account holds uid 1000.
