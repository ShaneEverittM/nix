# Warp terminal settings, keybindings, and themes (mirrored
# to both the stable `.warp` and OSS `.warp-oss` profile dirs). Mac-only (bundled via
# darwin.nix). The optional packageSource installs a Warp build through Home Manager;
# leave it "none" unless a `warpPackages` arg is supplied by the consumer.
{
  config,
  lib,
  pkgs,
  warpPackages ? { },
  ...
}:

let
  cfg = config.programs.warp;
  publicRoot = ../..;
  warpToml = pkgs.formats.toml { };
  sourceFile =
    path:
    if config.publicHome.dotfiles.mode == "outOfStore" then
      config.lib.file.mkOutOfStoreSymlink "${toString config.publicHome.repoRoot}/${path}"
    else
      publicRoot + "/${path}";
  defaultSettingsFor =
    profileDir:
    let
      themeDir = "${config.publicHome.homeDirectory}/${profileDir}/themes";
    in
    {
      appearance = {
        spacing = "normal";
        icon.app_icon = "classic_3";

        tabs = {
          show_indicators_button = true;
          workspace_decoration_visibility = "hide_fullscreen";
          header_toolbar_chip_selection.custom = {
            left = [ "tabs_panel" ];
            right = [ ];
          };
        };

        vertical_tabs = {
          display_granularity = "panes";
          compact_subtitle = "working_directory";
          primary_info = "branch";
          show_details_on_hover = true;
          enabled = true;
          view_mode = "compact";
        };

        themes = {
          theme.custom = {
            name = "JetBrains IDE Dark";
            path = "${themeDir}/jetbrains-ide-dark.yaml";
          };
          system_theme = true;
          selected_system_themes = {
            dark.custom = {
              name = "JetBrains IDE Dark";
              path = "${themeDir}/jetbrains-ide-dark.yaml";
            };
            light.custom = {
              name = "JetBrains IDE Light";
              path = "${themeDir}/jetbrains-ide-light.yaml";
            };
          };
        };

        input.input_mode = "pinned_to_top";
        window = {
          override_blur = 50;
          override_opacity = 70;
          zoom_level = 110;
        };
        text = {
          font_size = 16.0;
          line_height_ratio = 1.2000000476837158;
          notebook_font_size = 14.0;
          font_name = "JetBrains Mono";
        };
      };

      text_editing.vim_mode_enabled = true;

      terminal.input = {
        input_box_type_setting = "universal";
        honor_ps1 = false;
        error_underlining_enabled = false;
      };

      agents = {
        cloud_conversation_storage_enabled = false;
        warp_agent = {
          is_any_ai_enabled = false;
          input.nld_in_terminal_enabled = true;
          other.show_agent_notifications = false;
        };
      };

      code.editor.show_code_review_button = false;

      warpify = {
        subshells = {
          subshell_commands_denylist = [ ];
          added_subshell_commands = [ ];
        };
        ssh.use_ssh_tmux_wrapper = false;
      };

      privacy = {
        telemetry_enabled = false;
        crash_reporting_enabled = false;
        custom_secret_regex_list = [
          {
            name = "IPv4 Address";
            pattern = "\\b((25[0-5]|(2[0-4]|1\\d|[1-9]|)\\d)\\.?\\b){4}\\b";
          }
          {
            name = "IPv6 Address";
            pattern = "\\b((([0-9A-Fa-f]{1,4}:){1,6}:)|(([0-9A-Fa-f]{1,4}:){7}))([0-9A-Fa-f]{1,4})\\b";
          }
          {
            name = "Slack App Token";
            pattern = "\\bxapp-[0-9]+-[A-Za-z0-9_]+-[0-9]+-[a-f0-9]+\\b";
          }
          {
            name = "Phone Number";
            pattern = "\\b(\\+\\d{1,2}\\s)?\\(?\\d{3}\\)?[\\s.-]\\d{3}[\\s.-]\\d{4}\\b";
          }
          {
            name = "AWS Access ID";
            pattern = "\\b(AKIA|A3T|AGPA|AIDA|AROA|AIPA|ANPA|ANVA|ASIA)[A-Z0-9]{12,}\\b";
          }
          {
            name = "MAC Address";
            pattern = "\\b((([a-zA-z0-9]{2}[-:]){5}([a-zA-z0-9]{2}))|(([a-zA-z0-9]{2}:){5}([a-zA-z0-9]{2})))\\b";
          }
          {
            name = "Google API Key";
            pattern = "\\bAIza[0-9A-Za-z-_]{35}\\b";
          }
          {
            name = "GitHub Classic Personal Access Token";
            pattern = "\\bghp_[A-Za-z0-9_]{36}\\b";
          }
          {
            name = "GitHub Fine-Grained Personal Access Token";
            pattern = "\\bgithub_pat_[A-Za-z0-9_]{82}\\b";
          }
          {
            name = "GitHub OAuth Access Token";
            pattern = "\\bgho_[A-Za-z0-9_]{36}\\b";
          }
          {
            name = "GitHub User-to-Server Token";
            pattern = "\\bghu_[A-Za-z0-9_]{36}\\b";
          }
          {
            name = "GitHub Server-to-Server Token";
            pattern = "\\bghs_[A-Za-z0-9_]{36}\\b";
          }
          {
            name = "Stripe Key";
            pattern = "\\b(?:r|s)k_(test|live)_[0-9a-zA-Z]{24}\\b";
          }
          {
            name = "Firebase Auth Domain";
            pattern = "\\b([a-z0-9-]){1,30}(\\.firebaseapp\\.com)\\b";
          }
          {
            name = "JWT";
            pattern = "\\b(ey[a-zA-z0-9_\\-=]{10,}\\.){2}[a-zA-z0-9_\\-=]{10,}\\b";
          }
          {
            name = "OpenAI API Key";
            pattern = "\\bsk-[a-zA-Z0-9]{48}\\b";
          }
          {
            name = "Anthropic API Key";
            pattern = "\\bsk-ant-api\\d{0,2}-[a-zA-Z0-9\\-]{80,120}\\b";
          }
          {
            name = "Generic SK API Key";
            pattern = "\\bsk-[a-zA-Z0-9\\-]{10,100}\\b";
          }
          {
            name = "Fireworks API Key";
            pattern = "\\bfw_[a-zA-Z0-9]{24}\\b";
          }
          {
            name = "Warp API Key";
            pattern = "\\bwk-[0-9]+\\.[A-Fa-f0-9.\\-]+\\b";
          }
        ];
      };

      general = {
        default_session_mode = "terminal";
        login_item = false;
      };

      notifications = {
        toast_duration_secs = 8;
        preferences = {
          is_agent_task_completed_enabled = true;
          is_long_running_enabled = true;
          is_needs_attention_enabled = true;
          is_password_prompt_enabled = true;
          long_running_threshold = 30;
          mode = "enabled";
          play_notification_sound = true;
        };
      };
    };
  settingsFor = profileDir: lib.recursiveUpdate (defaultSettingsFor profileDir) cfg.settings;
in
{
  options.programs.warp = {
    packageSource = lib.mkOption {
      type = lib.types.enum [
        "none"
        "stable"
        "local-oss"
      ];
      default = "none";
      description = "Warp package source to install through Home Manager.";
    };

    settings = lib.mkOption {
      type = lib.types.attrs;
      default = { };
      description = "Warp settings attrs merged with the public defaults before TOML generation.";
    };
  };

  config = {
    home.packages = lib.optional (cfg.packageSource != "none") warpPackages.${cfg.packageSource};

    home.file = {
      ".warp/settings.toml" = {
        source = warpToml.generate "warp-settings.toml" (settingsFor ".warp");
        force = true;
      };

      ".warp/keybindings.yaml" = {
        source = sourceFile "files/warp/keybindings.yaml";
        force = true;
      };

      ".warp-oss/settings.toml" = {
        source = warpToml.generate "warp-oss-settings.toml" (settingsFor ".warp-oss");
        force = true;
      };

      ".warp-oss/keybindings.yaml" = {
        source = sourceFile "files/warp/keybindings.yaml";
        force = true;
      };

      ".warp/themes/jetbrains-ide-dark.yaml" = {
        source = sourceFile "files/warp/themes/jetbrains-ide-dark.yaml";
        force = true;
      };

      ".warp/themes/jetbrains-ide-light.yaml" = {
        source = sourceFile "files/warp/themes/jetbrains-ide-light.yaml";
        force = true;
      };

      ".warp-oss/themes/jetbrains-ide-dark.yaml" = {
        source = sourceFile "files/warp/themes/jetbrains-ide-dark.yaml";
        force = true;
      };

      ".warp-oss/themes/jetbrains-ide-light.yaml" = {
        source = sourceFile "files/warp/themes/jetbrains-ide-light.yaml";
        force = true;
      };
    };
  };
}
