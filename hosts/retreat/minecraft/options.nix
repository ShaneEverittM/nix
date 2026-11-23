# Option declarations for `publicMinecraft`, shared by both sides of the VM boundary:
# the host (./host.nix: storage, snapshots, one guest per pack) and the guest
# (./service.nix: the units themselves). Kept apart from either so that both can import
# the same declarations without importing each other's config.
{ lib, ... }:

let
  # `config` here is the *submodule's* own config, not the host's — that is what lets
  # worldSubvolume below derive from a sibling option.
  serverOpts =
    { config, ... }:
    {
      options = {
        description = lib.mkOption {
          type = lib.types.str;
          example = "Minecraft server (Craftoria 2, NeoForge 26.1.2.76)";
          description = "systemd unit description — name the pack and its loader version.";
        };

        # The live server directory: pack files, mods, libraries, config, world, logs,
        # user_jvm_args.txt, server.properties, eula.txt. Populate it by running the pack's
        # ServerStarter here, or by running the loader installer directly into it. The
        # preflight fails the start until the loader argfile is in place.
        serverDir = lib.mkOption {
          type = lib.types.str;
          description = ''
            Absolute path to the installed pack. The directory itself is created (owner
            `user`) by tmpfiles; populating it with the pack is a manual step.

            Every ancestor must already exist and be owned by `user` (or by root the whole
            way down): systemd-tmpfiles refuses an "unsafe path transition" from a
            user-owned directory into a root-owned one, and it fails the entire
            tmpfiles run when it hits one -- not just this line.
          '';
        };

        jre = lib.mkOption {
          type = lib.types.package;
          example = lib.literalExpression "pkgs.jdk21_headless";
          description = ''
            The JRE this pack requires — check the pack README, a mismatch is a hard
            failure at class-load time. Headless, from the system closure, so a desktop
            JDK upgrade can't move it.
          '';
        };

        user = lib.mkOption {
          type = lib.types.str;
          default = "minecraft";
          description = "Account that owns the world/config/log files and runs the JVM.";
        };

        # Minecraft Java. Opened in the guest's firewall and forwarded to it from the same
        # port on the host (./host.nix). It must match server-port in server.properties,
        # which the preflight asserts. Packs are allowed to SHARE a port (see
        # ./default.nix): they then share a network slot, so only one can be up at a time
        # and players keep one address whichever it is.
        port = lib.mkOption {
          type = lib.types.port;
          default = 25565;
          description = "server-port: opened in the guest and forwarded from the host.";
        };

        # RCON is deliberately NOT opened in the firewall: loopback only. Keep it that way
        # — the password sits in plaintext in server.properties.
        rconPort = lib.mkOption {
          type = lib.types.port;
          default = 25575;
          description = ''
            rcon.port. Loopback only, and it must match server.properties — the preflight
            fails otherwise. Packs sharing a port is supported; `<name>-console` refuses to
            talk to a port its own unit isn't holding, so a shared port cannot become
            cross-talk.
          '';
        };

        loaderPath = lib.mkOption {
          type = lib.types.str;
          default = "net/neoforged/neoforge";
          example = "net/minecraftforge/forge";
          description = ''
            Vendor path under `libraries/` holding `<version>/unix_args.txt`. Globbed at
            runtime rather than version-pinned, so a pack update that bumps the loader
            needs no nix edit.
          '';
        };

        autoStart = lib.mkOption {
          type = lib.types.bool;
          default = true;
          description = ''
            Whether this pack starts enabled the first time the host is activated. Only a
            seed: after that, which packs run is host state changed with
            `gameserver enable|disable <name>`, not by a rebuild. Packs that share a port
            share a network slot, so at most one of them can be enabled at a time.
          '';
        };

        # The guest's RAM is a hard, fully-reserved ceiling (unlike the old host unit,
        # which deliberately had no MemoryMax): the JVM's -Xmx in user_jvm_args.txt plus
        # metaspace, code cache, direct buffers and the guest's own kernel and page cache
        # must all fit, or the guest OOM-kills the JVM in a way that mimics a crash. Leave
        # roughly 3 GiB over -Xmx for a large pack, and raise both together.
        memory = lib.mkOption {
          type = lib.types.ints.positive;
          example = 11264;
          description = "Guest RAM in MiB. Must comfortably exceed -Xmx in user_jvm_args.txt.";
        };

        vcpu = lib.mkOption {
          type = lib.types.ints.positive;
          default = 8;
          description = "Guest vCPUs. The JVM sizes its GC and worker pools from this.";
        };

        snapshotWorld = lib.mkOption {
          type = lib.types.bool;
          default = true;
          description = ''
            Include this world in the btrbk timeline (../btrbk.nix) and quiesce it around
            each run. Only turn this off for a world you would not miss — the static pack
            tree is never snapshotted either way, being re-downloadable from CurseForge.
          '';
        };

        worldSubvolume = lib.mkOption {
          type = lib.types.str;
          readOnly = true;
          default = builtins.substring 1 (-1) config.serverDir + "/world";
          defaultText = lib.literalMD "`serverDir` minus its leading slash, plus `/world`";
          description = ''
            The world subvolume in the volume-relative form btrbk wants. Read-only: it is
            the seam that keeps ../btrbk.nix from drifting away from serverDir.
          '';
        };
      };
    };
in
{
  options.publicMinecraft = {
    servers = lib.mkOption {
      type = lib.types.attrsOf (lib.types.submodule serverOpts);
      default = { };
      description = ''
        Modded Minecraft servers, keyed by name. On the host each one becomes a microVM
        (`microvm@<name>`, driven by `gameserver`); inside its guest it is a systemd
        service of the same name.
      '';
    };

    # Identity of the account that owns the pack trees. Numeric and fixed because the
    # same files are seen from two kernels -- the host's, and the guest's through
    # virtiofs, which passes UIDs straight through -- so both must agree on the number,
    # not just the name.
    uid = lib.mkOption {
      type = lib.types.int;
      default = 25565;
      description = "UID/GID of the `minecraft` account on the host and in every guest.";
    };

    snapshotControl = {
      enable = lib.mkEnableOption "the guest-side freeze/thaw listener the host's btrbk run drives";
      port = lib.mkOption {
        type = lib.types.port;
        default = 25590;
        description = "TCP port the listener binds inside the guest.";
      };
      allowFrom = lib.mkOption {
        type = lib.types.str;
        example = "10.77.1.1";
        description = "The only source address the guest firewall admits to the listener (the host's end of the tap).";
      };
    };
  };
}
