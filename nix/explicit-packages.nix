# Helper for scripts/hm.ts `update`: dumps "name<TAB>version<TAB>storePath" for every
# package in the home configuration, so the tool can diff package versions across a
# nixpkgs bump. Evaluated against the personal Mac config (the package set is shared,
# so any homeConfiguration would do).
let
  flake = builtins.getFlake (toString ./..);
  home = flake.homeConfigurations."shane@macbook";
  packages = home.config.home.packages;

  describe =
    package:
    let
      name = package.pname or package.name;
      version = package.version or "unknown";
    in
    "${name}\t${version}\t${package}";
in
builtins.concatStringsSep "\n" (map describe packages)
