# JVM toolchain: the Gradle build tool plus the JDK it (and JetBrains) should target.
#
# Gradle bundles its own JVM purely to launch itself; that bundled JDK is an internal
# store path and must NOT be used as the project / IDE JDK — it's the wrong role and
# its path churns on every gradle bump. So we install an explicit LTS JDK and expose
# it at a stable symlink. JetBrains stores the "Gradle JVM" / project SDK as an
# absolute path, so pointing it directly at the nix store would break on every nixpkgs
# update. The symlink below keeps a constant path (~/.local/share/jdk) that is
# retargeted to the current store path on each `home-manager switch`, so the IDE field
# never needs touching.
#
# gradle comes from pkgsUnstable (faster release cadence; passed via extraSpecialArgs
# by each host). The unversioned `gradle` attr is aliased to the previous major
# (gradle_8) for compat, so pin gradle_9 explicitly for the current major. Shared by
# every host.
{
  config,
  lib,
  pkgs,
  pkgsUnstable,
  ...
}:

let
  jdk = pkgs.jdk25; # current LTS; stable nixpkgs carries it, so no unstable lane needed
  javaHome = "${config.home.homeDirectory}/.local/share/jdk";
in
{
  home.packages = [
    jdk
    pkgsUnstable.gradle_9
  ];

  # JAVA_HOME for shells points at the stable symlink (kept current by activation),
  # so the value never goes stale either.
  home.sessionVariables = {
    JAVA_HOME = javaHome;
  };

  home.activation.linkJdk = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
    $DRY_RUN_CMD mkdir -p "${config.home.homeDirectory}/.local/share"
    $DRY_RUN_CMD ln -sfn "${jdk.home}" "${javaHome}"
  '';
}
