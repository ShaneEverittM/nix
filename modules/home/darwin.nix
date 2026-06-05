# Darwin-only home-manager bits, shared by both Macs (personal MBA and work Mac).
# Imported alongside ./common.nix by the standalone home-manager configurations.
# Both Macs run home-manager standalone (no nix-darwin), so this is the only
# Mac-specific layer.
{ ... }:
{
  home.homeDirectory = "/Users/shane";

  # Mac-only packages/config go here (e.g. tools that only make sense on macOS).
  # Nothing yet — fills in on the Mac itself.
}
