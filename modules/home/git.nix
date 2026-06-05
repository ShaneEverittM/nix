# Option-driven git config, shared by every host. Behavior (aliases, diff-so-fancy
# pager, LFS filters, colors) lives here; identity is supplied per-machine via the
# publicHome.git.* options so the public modules never carry a user's name/email or
# signing key (the work machine sets its own in the private nix-work repo).
#
# Requires git-lfs and diff-so-fancy on PATH — both are in lib/packages.nix.
{
  config,
  lib,
  pkgs,
  ...
}:

let
  cfg = config.publicHome.git;
in
{
  options.publicHome.git = {
    userName = lib.mkOption {
      type = lib.types.nullOr lib.types.str;
      default = null;
      description = "Git user.name. Keep private machine identity outside the public module.";
    };

    userEmail = lib.mkOption {
      type = lib.types.nullOr lib.types.str;
      default = null;
      description = "Git user.email. Keep private machine identity outside the public module.";
    };

    signingKey = lib.mkOption {
      type = lib.types.nullOr lib.types.str;
      default = null;
      description = "Optional SSH signing key.";
    };

    sshSigningProgram = lib.mkOption {
      type = lib.types.nullOr lib.types.str;
      default = null;
      description = "Optional SSH signing program, such as a password-manager signer.";
    };
  };

  config = {
    programs.git = {
      enable = true;

      settings = {
        alias = {
          slog = "log --graph --abbrev-commit --decorate --format=oneline -n 10";
          hist = "log --graph --abbrev-commit --decorate --format=oneline --all";
          stat = "show --stat --abbrev-commit";
          stuff = "commit --amend -a --no-edit";
        };

        core = {
          autocrlf = "input";
          pager = "diff-so-fancy | less --tabs=4 -RF";
        };

        init.defaultBranch = "main";

        filter.lfs = {
          clean = "git-lfs clean -- %f";
          smudge = "git-lfs smudge -- %f";
          process = "git-lfs filter-process";
          required = true;
        };

        interactive.diffFilter = "diff-so-fancy --patch";

        color.ui = "auto";
        color.diff-highlight = {
          oldNormal = "red bold";
          oldHighlight = "red bold 52";
          newNormal = "green bold";
          newHighlight = "green bold 22";
        };

        color.diff = {
          meta = "11";
          frag = "magenta bold";
          func = "146 bold";
          commit = "yellow bold";
          old = "red bold";
          new = "green bold";
          whitespace = "red reverse";
        };

        diff-so-fancy.markEmptyLines = false;
      }
      // lib.optionalAttrs (cfg.userName != null || cfg.userEmail != null || cfg.signingKey != null) {
        user =
          lib.optionalAttrs (cfg.userName != null) { name = cfg.userName; }
          // lib.optionalAttrs (cfg.userEmail != null) { email = cfg.userEmail; }
          // lib.optionalAttrs (cfg.signingKey != null) { signingkey = cfg.signingKey; };
      }
      // lib.optionalAttrs (cfg.signingKey != null) {
        commit.gpgsign = true;
      }
      // lib.optionalAttrs (cfg.signingKey != null || cfg.sshSigningProgram != null) {
        # Build the entire `gpg` block in ONE attrset literal so its dotted keys
        # deep-merge. Splitting gpg.* across separate `//` blocks shallow-merges and
        # silently drops siblings (e.g. allowedSignersFile clobbering gpg.format,
        # which falls back to openpgp and breaks signing).
        gpg.format = "ssh";
        gpg.ssh =
          lib.optionalAttrs (cfg.signingKey != null && cfg.userEmail != null) {
            # Lets local `git log --show-signature` / `verify-commit` trust this
            # identity's own key (signing itself works without it).
            allowedSignersFile = toString (
              pkgs.writeText "git-allowed-signers" "${cfg.userEmail} ${cfg.signingKey}\n"
            );
          }
          // lib.optionalAttrs (cfg.sshSigningProgram != null) {
            program = cfg.sshSigningProgram;
          };
      };
    };
  };
}
