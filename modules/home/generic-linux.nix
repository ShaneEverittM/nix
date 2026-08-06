# Standalone home-manager on a NON-NixOS Linux distro (Arch/CachyOS, Ubuntu, ...).
#
# Import this ONLY on hosts where some other distro owns /etc and /usr. It must never
# reach a NixOS host: targets.genericLinux exists to paper over the gap between a
# foreign distro and the Nix store, and on NixOS those same fixups are wrong (NixOS
# already sets XDG_DATA_DIRS and LOCALE_ARCHIVE correctly, and home-manager warns when
# genericLinux is enabled there).
#
# What it buys us:
#   * XDG_DATA_DIRS picks up ~/.nix-profile/share, so .desktop entries and icons from
#     Nix-installed GUI apps show up in the distro's launcher (KDE, GNOME, ...).
#   * LOCALE_ARCHIVE points at a glibc locale archive from nixpkgs, which stops the
#     "cannot change locale" warnings Nix-built binaries emit against a foreign glibc.
#   * A wrapped systemd/dbus session so `systemctl --user` sees home-manager's units.
{ pkgs, ... }:
{
  targets.genericLinux.enable = true;

  # Make fonts installed through home.packages visible to non-Nix apps: this generates
  # the fontconfig files under ~/.config/fontconfig that point at the Nix profile's
  # font dirs. Needed for the shared Warp profile, which asks for JetBrains Mono by
  # name (see modules/home/warp-settings.nix).
  fonts.fontconfig.enable = true;

  home.packages = [
    # Must be the plain family, NOT nerd-fonts.jetbrains-mono: the Nerd Font build
    # registers its families as "JetBrainsMono Nerd Font" (no space, plus the suffix),
    # so an app asking for literal "JetBrains Mono" — as the shared Warp profile does —
    # finds nothing and silently falls back.
    pkgs.jetbrains-mono
  ];
}
