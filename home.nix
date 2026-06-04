{ pkgs, ... }:
{
  home.username = "nixos";
  home.homeDirectory = "/home/nixos";
  home.stateVersion = "25.11";

  programs.home-manager.enable = true;

  # git lives here so its identity is declarative (replaces a hand-edited
  # ~/.gitconfig). Uncomment and fill in your details, then rebuild.
  programs.git = {
    enable = true;
    # userName = "Your Name";
    # userEmail = "you@example.com";
  };

  # starter user packages — adjust freely
  home.packages = with pkgs; [ ripgrep fd ];
}
