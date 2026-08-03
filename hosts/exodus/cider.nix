# Launcher entry for Cider (Apple Music client), exodus-only.
#
# Cider ships as a paywalled AppImage with no stable URL, so it can't be fetched
# reproducibly into the Nix store. Following the same out-of-store split this repo
# uses for dotfiles, the binary and icon stay as live local files:
#
#   ~/Applications/Cider.AppImage   (chmod +x; runs via programs.appimage binfmt)
#   ~/Applications/cider.png        (256x256 icon, extracted from the AppImage)
#
# Only the .desktop entry is declared here. home-manager writes it to
# ~/.local/share/applications/, so KDE's launcher picks it up and it can be pinned
# to the task manager. StartupWMClass matches Cider's window class so a launched
# (or pinned) instance maps back to this icon instead of a generic one. The MPRIS
# actions and music:/itms: URL handlers are copied from the AppImage's own entry.
#
# Not in the cross-platform desktop.nix: this is a single Linux desktop app, and
# macOS eval would carry a dead Linux-only path.
{ config, ... }:

let
  appImage = "${config.home.homeDirectory}/Applications/Cider.AppImage";
  mprisAction = member: {
    name = member;
    exec = "dbus-send --print-reply --dest=org.mpris.MediaPlayer2.cider /org/mpris/MediaPlayer2 org.mpris.MediaPlayer2.Player.${member}";
  };
in
{
  xdg.desktopEntries.cider = {
    name = "Cider";
    genericName = "Music Player";
    comment = "A cross-platform Apple Music experience";
    exec = "${appImage} %U";
    icon = "${config.home.homeDirectory}/Applications/cider.png";
    terminal = false;
    categories = [
      "Audio"
      "AudioVideo"
    ];
    mimeType = [
      "x-scheme-handler/ame"
      "x-scheme-handler/cider"
      "x-scheme-handler/itms"
      "x-scheme-handler/itmss"
      "x-scheme-handler/musics"
      "x-scheme-handler/music"
    ];
    settings.StartupWMClass = "cider";
    actions = {
      PlayPause = mprisAction "PlayPause";
      Next = mprisAction "Next";
      Previous = mprisAction "Previous";
      Stop = mprisAction "Stop";
    };
  };
}
