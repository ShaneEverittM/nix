# Enshrouded dedicated server, run from the community container image
# (https://github.com/mornedhels/enshrouded-server) under podman.
#
# WHY A CONTAINER. Keen ships the server as a Windows binary only. The image bundles
# SteamCMD, GE-Proton and the 32-bit libraries both expect, and runs
# `proton run enshrouded_server.exe` -- a plain process tree on this kernel, no VM. Doing
# the same natively would mean an FHS wrapper around steamcmd and Proton for no gain.
#
# LAYOUT (all under /var/lib/enshrouded):
#   game/        the image's /opt/enshrouded volume: the SteamCMD download (several GB,
#                re-downloadable), the Proton prefix, and server/enshrouded_server.json,
#                which the image rewrites from the environment below on every start.
#   savegame/    the world. Its own subvolume, bind-mounted over the server's default
#                ./savegame, so btrbk snapshots the world without the game install.
#   secrets.env  role passwords, generated on first start (see SECRETS).
# The image runs the server as uid/gid 4711 and chowns its volume to match; nothing on the
# host owns that id, which is what upstream intends.
#
# ACCESS. One UDP port, 15637 (Steam query *and* game traffic on current builds), open on
# every interface like the Minecraft port. Players outside the LAN/tailnet additionally
# need that port forwarded on the router. Joining asks for a role password.
#
# SECRETS. None in this public flake. `enshrouded-secrets` writes secrets.env (root, 0600)
# on first start with a random password per role and never touches it again:
#     sudo cat /var/lib/enshrouded/secrets.env
# To change a password edit that file and restart the unit.
#
# UPDATES. Client and server must be on the same game build, so the image polls Steam every
# 30 minutes and updates itself, but only while nobody is connected. The *image* is pinned;
# bump `imageVersion` deliberately.
#
# BACKUPS. savegame/ is in the btrbk timeline (local snapshots + the push to rebirth). The
# server is not quiesced around the snapshot, so a snapshot is crash-consistent; the game
# writes a save as a whole small file, and the timeline keeps older ones if the newest is
# torn. The image's own zip backups are left off.
#
# IMPORTING A WORLD (a client-hosted save). Current builds store a world as one file,
# `world<N>.ksd`; the server loads slot 0.
#     systemctl stop podman-enshrouded
#     install -o 4711 -g 4711 -m 0644 world1.ksd /var/lib/enshrouded/savegame/world0.ksd
#     systemctl start podman-enshrouded
# Start the server once *before* importing and check that it wrote world0.ksd there: the
# rename to slot 0 is inferred from that layout, not documented by Keen. Characters are
# stored on each player's own machine and need no transfer.
#
# OPERATING IT:
#   logs      journalctl -u podman-enshrouded -f
#   restart   systemctl restart podman-enshrouded      (stop saves the world; allow 90 s)
#   update    podman exec enshrouded supervisorctl start enshrouded-force-update
#
# MEMORY. Upstream recommends 16 GB; in practice the server sits at a few GB with a small
# group. It runs alongside whichever Minecraft pack is up, so watch it under the earlyoom
# thresholds in ./configuration.nix the first time both are busy.
{
  config,
  lib,
  pkgs,
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
in
{
  virtualisation.podman.enable = true;
  virtualisation.oci-containers.backend = "podman";

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

  # First-start password generation. Never rewrites an existing file, so the passwords
  # players were given keep working across rebuilds.
  systemd.services.enshrouded-secrets = {
    description = "Generate the Enshrouded server's role passwords on first start";
    wantedBy = [ "multi-user.target" ];
    path = [ pkgs.openssl ];
    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
      UMask = "0077";
    };
    script = ''
      # tmpfiles normally has this in place already; do not depend on the ordering.
      mkdir -p ${stateDir}
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
  };

  virtualisation.oci-containers.containers.enshrouded = {
    image = "docker.io/mornedhels/enshrouded-server:${imageVersion}";
    ports = [ "${toString port}:${toString port}/udp" ];
    volumes = [
      "${stateDir}/game:/opt/enshrouded"
      # Nested over the server's default save directory (the image installs the server to
      # /opt/enshrouded/server and leaves saveDirectory at ./savegame).
      "${saveDir}:/opt/enshrouded/server/savegame"
    ];
    environment = {
      SERVER_NAME = config.networking.hostName;
      SERVER_SLOT_COUNT = "8";
      SERVER_QUERYPORT = toString port;
      PUID = uid;
      PGID = uid;

      UPDATE_CRON = "*/30 * * * *";
      UPDATE_CHECK_PLAYERS = "true";

      # Roles are the server's only access control (the old single server password is
      # ignored by the game). Passwords come from envFile.
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
      # Upstream's documented hardening (docs/SECURITY_HARDENING.md): the bootstrap needs
      # only these to chown its volume, drop to the server uid and signal its children.
      "--security-opt=no-new-privileges"
      "--cap-drop=ALL"
      "--cap-add=DAC_OVERRIDE"
      "--cap-add=CHOWN"
      "--cap-add=SETUID"
      "--cap-add=SETGID"
      "--cap-add=KILL"
    ];
  };

  # podman DNATs a published port ahead of the INPUT chain, so this is not what lets
  # players in today -- it states the intent and keeps the port open if the container ever
  # moves to host networking.
  networking.firewall.allowedUDPPorts = [ port ];
}
