# Enshrouded dedicated server, run from the community container image
# (https://github.com/mornedhels/enshrouded-server) under podman, inside its own microVM.
#
# WHY A CONTAINER, IN A VM. Keen ships the server as a Windows binary only. The image
# bundles SteamCMD, GE-Proton and the 32-bit libraries both expect, and runs
# `proton run enshrouded_server.exe`; doing the same natively would mean an FHS wrapper
# around steamcmd and Proton for no gain. The container is packaging, not a security
# boundary -- Wine is not a sandbox, and a container shares its host's kernel. The
# boundary is the guest (see ./gameservers.nix), which is why the container simply runs
# as the image intends and nothing more is made of it: what it could reach by breaking
# out is a VM that holds this game and nothing else.
#
# A real Windows guest was not seriously considered: it would be a licensed,
# hand-maintained, undeclarable machine to patch, to run a binary that works under Proton.
#
# LAYOUT.
#   /var/lib/enshrouded (host, shared into the guest at the same path):
#     game/        the image's /opt/enshrouded volume: the SteamCMD download (several GB,
#                  re-downloadable), the Proton prefix, and server/enshrouded_server.json,
#                  which the image rewrites from the environment below on every start.
#     savegame/    the world. Its own subvolume, bind-mounted over the server's default
#                  ./savegame, so btrbk snapshots the world without the game install.
#     secrets.env  role passwords, generated on first start (see SECRETS).
#   /var/lib/containers (guest-only disk image): podman's image store. A guest's root is
#     RAM, so without this the multi-GB image would be pulled into memory on every start.
#     Nothing in it is worth a snapshot; deleting the image file just means a re-pull.
# The image runs the server as uid/gid 4711 and chowns its volume to match; nothing on the
# host owns that id, which is what upstream intends.
#
# ACCESS. One UDP port, 15637 (Steam query *and* game traffic on current builds),
# forwarded from the host on every interface. Players outside the LAN/tailnet
# additionally need that port forwarded on the router. Joining asks for a role password.
#
# SECRETS. None in this public flake. `enshrouded-secrets` (in the guest) writes
# secrets.env (root, 0600) on first start with a random password per role and never
# touches it again. It lives on the shared directory, so read or edit it from the host:
#     sudo cat /var/lib/enshrouded/secrets.env
# To change a password edit that file and `gameserver restart enshrouded`.
#
# UPDATES. Client and server must be on the same game build, so the image polls Steam every
# 30 minutes and updates itself, but only while nobody is connected. The *image* is pinned;
# bump `imageVersion` deliberately.
#
# BACKUPS. savegame/ is in the btrbk timeline (local snapshots + the push to rebirth). The
# server is not quiesced around the snapshot, so a snapshot is crash-consistent -- and
# since the VM, slightly weaker than that: a save the guest has written but not yet
# flushed through the share is not in it. The game writes a save as a whole small file,
# and the timeline keeps older ones if the newest is torn or missing. The image's own zip
# backups are left off.
#
# IMPORTING A WORLD (a client-hosted save). Current builds store a world as one file,
# `world<N>.ksd`; the server loads slot 0. From the host:
#     gameserver stop enshrouded
#     install -o 4711 -g 4711 -m 0644 world1.ksd /var/lib/enshrouded/savegame/world0.ksd
#     gameserver start enshrouded
# Start the server once *before* importing and check that it wrote world0.ksd there: the
# rename to slot 0 is inferred from that layout, not documented by Keen. Characters are
# stored on each player's own machine and need no transfer.
#
# OPERATING IT (from the host; there is no way into the guest):
#   on/off    gameserver enable|disable enshrouded
#   logs      gameserver logs enshrouded
#   restart   gameserver restart enshrouded      (stop saves the world; allow 90 s)
#   update    restart it -- the image checks Steam on start as well as on its timer.
#
# MEMORY. Upstream recommends 16 GB; in practice the server sits a little over 1 GB idle
# and at a few GB with a small group. `memory` below is reserved in full while the guest
# runs, and is a hard ceiling: raise it if the guest ever OOM-kills the server.
{
  config,
  lib,
  ...
}:

let
  # Pinned to the Proton flavour, not `latest`: a new image can change Proton or the
  # bootstrap scripts under a live world.
  imageVersion = "1.8.1-proton";

  stateDir = "/var/lib/enshrouded";
  saveDir = "${stateDir}/savegame";
  envFile = "${stateDir}/secrets.env";

  # The image's default uid/gid for the server process (PUID/PGID).
  uid = "4711";

  port = 15637;

  # What players see in the server browser. Captured here, on the host: inside the guest
  # `networking.hostName` is the VM's name.
  serverName = config.networking.hostName;
in
{
  imports = [ ./gameservers.nix ];

  # Host side: the state directory and its place in the snapshot timeline. These stay
  # here for the same reason the Minecraft worlds do (./minecraft/host.nix) -- the guest
  # could only ever make a plain directory through the share, and holds no backup keys.
  systemd.tmpfiles.rules = [
    "d ${stateDir} 0755 root root - -"
    "d ${stateDir}/game 0750 ${uid} ${uid} - -"
    # A subvolume so btrbk can snapshot it; `v` only acts when the path doesn't exist yet,
    # and degrades to a plain directory off btrfs.
    "v ${saveDir} 0750 ${uid} ${uid} - -"
  ];

  # Volume-relative path, the form btrbk wants (the volume is "/", see ./btrbk.nix).
  services.btrbk.instances.local.settings.volume."/".subvolume.${lib.removePrefix "/" saveDir} = {
    snapshot_name = "enshrouded-savegame";
  };

  publicGameServers.servers.enshrouded = {
    # Its own slot, well clear of the ones ./minecraft/host.nix numbers upward from 1.
    slot = 20;
    memory = 6144;
    vcpu = 6;
    forwardUDP = [ port ];
    shares = [ stateDir ];
    volumes = [
      {
        image = "containers.img";
        mountPoint = "/var/lib/containers";
        size = 24576;
      }
    ];
    autoStart = true;

    guest =
      { pkgs, ... }:
      {
        virtualisation.podman.enable = true;
        virtualisation.oci-containers.backend = "podman";

        # First-start password generation. Never rewrites an existing file, so the
        # passwords players were given keep working across rebuilds and restarts.
        systemd.services.enshrouded-secrets = {
          description = "Generate the Enshrouded server's role passwords on first start";
          wantedBy = [ "multi-user.target" ];
          path = [ pkgs.openssl ];
          unitConfig.RequiresMountsFor = [ stateDir ];
          serviceConfig = {
            Type = "oneshot";
            RemainAfterExit = true;
            UMask = "0077";
          };
          script = ''
            if [ ! -s ${envFile} ]; then
              printf 'SERVER_ROLE_0_PASSWORD=%s\nSERVER_ROLE_1_PASSWORD=%s\n' \
                "$(openssl rand -hex 8)" "$(openssl rand -hex 8)" > ${envFile}.tmp
              mv ${envFile}.tmp ${envFile}
            fi
          '';
        };

        systemd.services.podman-enshrouded = {
          after = [ "enshrouded-secrets.service" ];
          requires = [ "enshrouded-secrets.service" ];
          unitConfig.RequiresMountsFor = [
            stateDir
            "/var/lib/containers"
          ];
        };

        virtualisation.oci-containers.containers.enshrouded = {
          image = "docker.io/mornedhels/enshrouded-server:${imageVersion}";
          ports = [ "${toString port}:${toString port}/udp" ];
          volumes = [
            "${stateDir}/game:/opt/enshrouded"
            # Nested over the server's default save directory (the image installs the
            # server to /opt/enshrouded/server and leaves saveDirectory at ./savegame).
            "${saveDir}:/opt/enshrouded/server/savegame"
          ];
          environment = {
            SERVER_NAME = serverName;
            SERVER_SLOT_COUNT = "8";
            SERVER_QUERYPORT = toString port;
            PUID = uid;
            PGID = uid;

            UPDATE_CRON = "*/30 * * * *";
            UPDATE_CHECK_PLAYERS = "true";

            # Roles are the server's only access control (the old single server password
            # is ignored by the game). Passwords come from envFile.
            SERVER_ROLE_0_NAME = "Admin";
            SERVER_ROLE_0_CAN_KICK_BAN = "true";
            SERVER_ROLE_0_CAN_ACCESS_INVENTORIES = "true";
            SERVER_ROLE_0_CAN_EDIT_WORLD = "true";
            SERVER_ROLE_0_CAN_EDIT_BASE = "true";
            SERVER_ROLE_0_CAN_EXTEND_BASE = "true";
            SERVER_ROLE_0_RESERVED_SLOTS = "1";

            SERVER_ROLE_1_NAME = "Friend";
            SERVER_ROLE_1_CAN_ACCESS_INVENTORIES = "true";
            SERVER_ROLE_1_CAN_EDIT_WORLD = "true";
            SERVER_ROLE_1_CAN_EDIT_BASE = "true";
            SERVER_ROLE_1_CAN_EXTEND_BASE = "true";
          };
          environmentFiles = [ envFile ];
          extraOptions = [
            # Upstream's stop_grace_period: the server saves the world on SIGTERM.
            "--stop-timeout=90"
            # Upstream's documented hardening (docs/SECURITY_HARDENING.md): the bootstrap
            # needs only these to chown its volume, drop to the server uid and signal its
            # children.
            "--security-opt=no-new-privileges"
            "--cap-drop=ALL"
            "--cap-add=DAC_OVERRIDE"
            "--cap-add=CHOWN"
            "--cap-add=SETUID"
            "--cap-add=SETGID"
            "--cap-add=KILL"
          ];
        };

        # podman DNATs a published port ahead of the guest's INPUT chain, so this is not
        # what lets players in today -- it states the intent and keeps the port open if
        # the container ever moves to host networking.
        networking.firewall.allowedUDPPorts = [ port ];
      };
  };
}
