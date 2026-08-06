# CI gates, surfaced as flake `checks.<system>.*` so `nix flake check` runs the exact
# same checks locally and in CI (see .github/workflows/ci.yml). No logic lives in the
# workflow YAML — CI is just `nix flake check` per runner OS.
#
# Split by what's buildable where. `nix flake check` builds the checks for the *host*
# system, so the CI matrix runs it once on x86_64-linux (Linux toplevels) and once on
# aarch64-darwin (Darwin home activations); together they cover every target.
#
#   Every system : nixfmt / deadnix / statix / prettier / gitleaks / home-nix-free lint
#                  gates (source-only, cheap), plus the `packages.default` buildEnv and
#                  the exported formatter — outputs that would otherwise never be built
#                  before someone ran them.
#   x86_64-linux : both NixOS toplevels (exodus desktop + rebirth server) build — this is
#                  what catches build-time breakage that pure eval misses, e.g. a wrong
#                  Warp AppImage hash or a broken substituteInPlace — plus
#                  `downstream-linux`, the genericLinux flavor of the downstream check.
#   aarch64-darwin: the personal macbook home activation, plus `downstream` — a standalone
#                  home-manager config assembled from the exported homeModules exactly as
#                  the private work-Mac repo consumes them (default + darwin, outOfStore
#                  mode) — and `downstream-store`, its store-mode/knobs twin. A change
#                  here that would break that repo fails this repo's CI first, via the
#                  same public interface it imports.
{
  inputs,
  self,
  systems,
}:
let
  inherit (inputs) nixpkgs home-manager;
  inherit (nixpkgs) lib;
  mkPkgs = import ./mk-pkgs.nix;

  pkgsFor =
    system:
    mkPkgs {
      input = nixpkgs;
      inherit system;
    };
  pkgsUnstableFor =
    system:
    mkPkgs {
      input = inputs.nixpkgs-unstable;
      inherit system;
    };

  # Generated hardware scans — we don't own their formatting, so keep them out of the
  # source-hygiene gates.
  generated = [
    "./hosts/exodus/hardware-configuration.nix"
    "./hosts/rebirth/hardware-configuration.nix"
  ];

  # Source-hygiene checks run against the flake source in the store (${self}), which is
  # the clean git tree (no .git), so we enumerate with `find`, not `git ls-files`.
  lintChecks =
    system:
    let
      pkgs = pkgsFor system;
    in
    {
      nixfmt = pkgs.runCommandLocal "check-nixfmt" { nativeBuildInputs = [ pkgs.nixfmt ]; } ''
        cd ${self}
        nixfmt --check $(find . -name '*.nix' ${
          lib.concatMapStringsSep " " (p: "-not -path '${p}'") generated
        })
        touch $out
      '';

      deadnix = pkgs.runCommandLocal "check-deadnix" { nativeBuildInputs = [ pkgs.deadnix ]; } ''
        cd ${self}
        deadnix --fail --exclude ${lib.concatMapStringsSep " " (p: "'${p}'") generated} -- .
        touch $out
      '';

      statix = pkgs.runCommandLocal "check-statix" { nativeBuildInputs = [ pkgs.statix ]; } ''
        cd ${self}
        # -i takes glob patterns matched per-file; one basename glob covers every
        # generated hardware scan (the same files `generated` lists by path).
        statix check . -i 'hardware-configuration.nix'
        touch $out
      '';

      # Prettier over the non-Nix sources (markdown, JSON/JSONC tooling configs,
      # workflow YAML). .prettierignore excludes flake.lock and files/ — the live
      # app-owned dotfiles keep their owning app's native formatting.
      prettier = pkgs.runCommandLocal "check-prettier" { nativeBuildInputs = [ pkgs.prettier ]; } ''
        cd ${self}
        prettier --check .
        touch $out
      '';

      # Secret scan. The repo's number-one standing rule is "safe to publish"; this
      # makes the invariant a gate instead of reviewer discipline. --no-git because
      # ${self} is the clean source tree without .git.
      gitleaks = pkgs.runCommandLocal "check-gitleaks" { nativeBuildInputs = [ pkgs.gitleaks ]; } ''
        gitleaks detect --no-git --source ${self} --redact
        touch $out
      '';

      # The exported home modules must never SET a nix.* option: the downstream work
      # Mac runs Determinate Nix, which owns Nix's own config (see the header of
      # modules/home/common.nix). Comment-only mentions are fine; this greps for
      # non-comment lines that assign under the nix.* namespace.
      home-nix-free = pkgs.runCommandLocal "check-home-nix-free" { } ''
        cd ${self}
        if grep -rnE '^[^#]*\bnix\.[a-z]' modules/home; then
          echo 'nix.* setting found in modules/home — this breaks the Determinate-Nix downstream consumer' >&2
          exit 1
        fi
        touch $out
      '';
    };

  # Standalone home-manager config built purely from the exported homeModules, the way
  # the downstream work-Mac flake consumes them. Two flavors: `downstream` mirrors the
  # real work-Mac shape (outOfStore dotfiles, whose symlink targets need not exist at
  # build time, so no repo checkout is required); `downstream-store` exercises the
  # downstream-only knobs nothing else ever sets — store-mode dotfiles, a custom
  # repoRoot/homeFlake, a cargo-registry overlay, and an own stateVersion (proving the
  # bundle's mkDefault contract holds).
  downstreamHome =
    system: extraModule:
    (home-manager.lib.homeManagerConfiguration {
      pkgs = pkgsFor system;
      extraSpecialArgs = {
        pkgsUnstable = pkgsUnstableFor system;
      };
      modules = [
        self.homeModules.default
        self.homeModules.darwin
        {
          publicHome.git.userName = "CI Downstream";
          publicHome.git.userEmail = "ci@example.com";
        }
        extraModule
      ];
    }).activationPackage;

  downstreamStoreModule = {
    publicHome.dotfiles.mode = "store";
    publicHome.repoRoot = "/opt/ci/downstream-flake";
    publicHome.nh.homeFlake = "/opt/ci/downstream-flake";
    publicHome.rust.extraCargoConfig = {
      registries.ci-private.index = "sparse+https://registry.example.com/index/";
    };
    home.stateVersion = "26.05";
  };

  # Exported outputs that nothing else builds: without these rows, a package that
  # evaluates but fails to build (or an unfree/broken marking on one platform) ships
  # green until someone runs `nix profile install .#default` by hand.
  exportedOutputs = system: {
    packages-env = self.packages.${system}.default;
    formatter-pkg = self.formatter.${system};
  };

  buildChecks =
    system:
    exportedOutputs system
    // {
      x86_64-linux = {
        exodus-toplevel = self.nixosConfigurations.exodus.config.system.build.toplevel;
        rebirth-toplevel = self.nixosConfigurations.rebirth.config.system.build.toplevel;

        # Boots a VM and smoke-tests the craftoria console plumbing (FIFO socket +
        # sandboxing) with a stand-in for the un-CI-able NeoForge server. NixOS VM tests
        # need /dev/kvm, so the Linux CI job enables it (see .github/workflows/ci.yml).
        craftoria-console = import ../tests/craftoria-console.nix { pkgs = pkgsFor system; };

        # Boots the shared modules/nixos base (minus btrfs — its mount options assume
        # the real pools) and asserts behavior: hardened sshd on the wire, the
        # discovery/DNS/tailnet daemons, memory backstops, and the home-manager
        # fold-in end to end.
        base-smoke = import ../tests/base-smoke.nix {
          pkgs = pkgsFor system;
          inherit inputs;
        };

        # The genericLinux flavor of the downstream check: homeModules.default + linux
        # + genericLinux, as a downstream non-NixOS Linux box would consume them. The
        # only coverage genericLinux has — it's exported for exactly that consumer and
        # imported by no in-repo host (all Linux hosts are NixOS).
        downstream-linux =
          (home-manager.lib.homeManagerConfiguration {
            pkgs = pkgsFor system;
            extraSpecialArgs = {
              pkgsUnstable = pkgsUnstableFor system;
            };
            modules = [
              self.homeModules.default
              self.homeModules.linux
              self.homeModules.genericLinux
              {
                publicHome.git.userName = "CI Downstream";
                publicHome.git.userEmail = "ci@example.com";
              }
            ];
          }).activationPackage;
      };
      aarch64-darwin = {
        macbook = self.homeConfigurations."shane@macbook".activationPackage;
        downstream = downstreamHome system { };
        downstream-store = downstreamHome system downstreamStoreModule;
      };
    }
    .${system} or { };
in
lib.genAttrs systems (system: lintChecks system // buildChecks system)
