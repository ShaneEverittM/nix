# Sure: self-hosted personal finance (https://github.com/we-promise/sure), run from the
# upstream container image and reachable only over Tailscale.
#
# This is upstream's compose.example.yml transcribed to NixOS oci-containers (podman), so
# the app sees exactly the topology it is tested against:
#
#   sure-web     Rails app, published on loopback 127.0.0.1:3000 only
#   sure-worker  Sidekiq (same image) -- syncs, imports, scheduled price fetches
#   sure-db      Postgres 16
#   sure-redis   Redis (Sidekiq's queue)
#   sure-backup  upstream's own `bin/sure-backup` on a daily schedule (same image)
#
# Not packaged natively on purpose: it is a Rails app with a JS build and no nixpkgs
# module, and upstream only supports the image. Everything else about it is declarative.
#
# ACCESS. The only way in is the `tailscale serve` proxy at the bottom:
# https://<this node's tailnet name>:8443. Nothing is opened in the firewall. Rails is
# told to assume TLS because the proxy terminates it (RAILS_ASSUME_SSL), which is what
# upstream documents for a TLS-terminating reverse proxy; without it logins fail the
# CSRF origin check.
#
# SECRETS. None in this public flake, and none to create by hand: `sure-secrets`
# generates /var/lib/sure/config/.env (root, 0600) on first start with a random
# SECRET_KEY_BASE and database password, and never touches it again. SECRET_KEY_BASE
# also seeds the keys that encrypt provider tokens at rest, so that file is as
# irreplaceable as the database -- which is why it rides along in every backup bundle.
#
# BACKUPS. Snapshotting a live Postgres data directory is only crash-consistent, so the
# database is not what btrbk captures. Instead `sure-backup` writes a self-contained
# bundle (pg_dump + uploaded files + the .env above) to /var/lib/sure/backups every
# night, and *that* directory is its own subvolume in the btrbk timeline, so bundles are
# snapshotted locally and replicated to rebirth with everything else. The bundles hold
# the secrets in plain text; both ends are 0700 root and stay on machines we own.
#
# OPERATING IT (all as root; `<v>/<name>` comes from `list`):
#   backup now      podman exec sure-backup bin/sure-backup create
#   list backups    podman exec sure-backup bin/sure-backup list
#   restore         systemctl stop podman-sure-web podman-sure-worker
#                   podman exec -it sure-backup bin/sure-backup restore <v>/<name>
#                   systemctl start podman-sure-web podman-sure-worker
#   upgrade         take a backup, bump `sureVersion` below, switch. Migrations run when
#                   sure-web starts. Rolling back is a restore plus the old version here.
# A bundle's own restore.sh rebuilds a docker-compose install on a new machine; it does
# not know about this module, so on NixOS use `restore` as above.
{
  config,
  lib,
  pkgs,
  ...
}:

let
  # Pinned, not `stable`: an upgrade runs database migrations, so it should be a
  # deliberate edit with a backup taken first, not a side effect of a restart.
  sureVersion = "0.7.6-hotfix.1";
  sureImage = "ghcr.io/we-promise/sure:${sureVersion}";

  stateDir = "/var/lib/sure";
  envFile = "${stateDir}/config/.env";
  backupDir = "${stateDir}/backups";

  network = "sure";
  podman = lib.getExe config.virtualisation.podman.package;

  dbEnv = {
    POSTGRES_USER = "sure_user";
    POSTGRES_DB = "sure_production";
    # POSTGRES_PASSWORD comes from envFile.
  };

  railsEnv = dbEnv // {
    # SECRET_KEY_BASE comes from envFile.
    SELF_HOSTED = "true";
    RAILS_FORCE_SSL = "false";
    RAILS_ASSUME_SSL = "true";
    DB_HOST = "sure-db";
    DB_PORT = "5432";
    REDIS_URL = "redis://sure-redis:6379/1";
  };

  containers = [
    "sure-db"
    "sure-redis"
    "sure-web"
    "sure-worker"
    "sure-backup"
  ];
in
{
  virtualisation.podman.enable = true;
  virtualisation.oci-containers.backend = "podman";

  # Containers on a user-defined podman network find each other by name through
  # aardvark-dns, which listens on the bridge address -- i.e. on the host's INPUT path, so
  # the NixOS firewall has to let the containers reach it. Scoped to podman's own bridges.
  networking.firewall.interfaces."podman+".allowedUDPPorts = [ 53 ];

  systemd.tmpfiles.rules = [
    "d ${stateDir} 0700 root root - -"
    "d ${stateDir}/config 0700 root root - -"
    # A subvolume so btrbk can snapshot it (see the header); `v` only acts when the path
    # doesn't exist yet, and degrades to a plain directory off btrfs.
    "v ${backupDir} 0700 root root - -"
  ];

  # Volume-relative path, the form btrbk wants (the volume is "/", see ./btrbk.nix).
  services.btrbk.instances.local.settings.volume."/".subvolume.${lib.removePrefix "/" backupDir} = {
    snapshot_name = "sure-backups";
  };

  systemd.services = {
    # First-start secret generation. Never rewrites an existing file: a new
    # SECRET_KEY_BASE would make already-encrypted data unreadable.
    sure-secrets = {
      description = "Generate Sure's secrets on first start";
      wantedBy = [ "multi-user.target" ];
      path = [ pkgs.openssl ];
      serviceConfig = {
        Type = "oneshot";
        RemainAfterExit = true;
        UMask = "0077";
      };
      script = ''
        # tmpfiles normally has this in place already; do not depend on the ordering.
        mkdir -p ${stateDir}/config
        if [ ! -s ${envFile} ]; then
          printf 'SECRET_KEY_BASE=%s\nPOSTGRES_PASSWORD=%s\n' \
            "$(openssl rand -hex 64)" "$(openssl rand -hex 24)" > ${envFile}.tmp
          mv ${envFile}.tmp ${envFile}
        fi
      '';
    };

    sure-network = {
      description = "Create the podman network Sure's containers share";
      wantedBy = [ "multi-user.target" ];
      serviceConfig = {
        Type = "oneshot";
        RemainAfterExit = true;
      };
      script = ''
        ${podman} network exists ${network} || ${podman} network create ${network}
      '';
    };
  }
  # Every container needs the network and the secrets file in place first.
  // lib.genAttrs (map (c: "podman-${c}") containers) (_: {
    after = [
      "sure-network.service"
      "sure-secrets.service"
    ];
    requires = [
      "sure-network.service"
      "sure-secrets.service"
    ];
  });

  virtualisation.oci-containers.containers = {
    sure-db = {
      image = "docker.io/library/postgres:16";
      networks = [ network ];
      environment = dbEnv;
      environmentFiles = [ envFile ];
      volumes = [ "sure-postgres:/var/lib/postgresql/data" ];
    };

    sure-redis = {
      # Upstream runs `redis:latest`; pinned to the current major so a restart can't
      # cross a major version on its own.
      image = "docker.io/library/redis:8";
      networks = [ network ];
      volumes = [ "sure-redis:/data" ];
    };

    sure-web = {
      image = sureImage;
      networks = [ network ];
      environment = railsEnv;
      environmentFiles = [ envFile ];
      volumes = [ "sure-storage:/rails/storage" ];
      # Loopback only -- the tailscale serve proxy below is the sole consumer.
      ports = [ "127.0.0.1:3000:3000" ];
      # Ordering only (there is no health gate): if Postgres is still starting, the app
      # exits and systemd restarts it until the database answers.
      dependsOn = [
        "sure-db"
        "sure-redis"
      ];
    };

    sure-worker = {
      image = sureImage;
      networks = [ network ];
      environment = railsEnv;
      environmentFiles = [ envFile ];
      volumes = [ "sure-storage:/rails/storage" ];
      cmd = [
        "bundle"
        "exec"
        "sidekiq"
      ];
      dependsOn = [
        "sure-db"
        "sure-redis"
      ];
    };

    sure-backup = {
      image = sureImage;
      networks = [ network ];
      user = "0";
      entrypoint = "bin/sure-backup";
      environment = dbEnv // {
        POSTGRES_HOST = "sure-db";
        # UTC. 06:00 UTC is 22:00/23:00 Pacific, so the bundle exists before btrbk's
        # midnight run snapshots and replicates it.
        BACKUP_SCHEDULE = "0 6 * * *";
        BACKUP_KEEP_DAYS = "7";
        INSTANCE_ID = config.networking.hostName;
      };
      environmentFiles = [ envFile ];
      volumes = [
        "${backupDir}:/backups"
        "sure-storage:/rails/storage"
        # The bundle copies this directory in, which is how the secrets get backed up.
        "${stateDir}/config:/config:ro"
      ];
      dependsOn = [ "sure-db" ];
    };
  };

  publicTailscale.serve.sure = {
    description = "Expose Sure (localhost:3000) over Tailscale HTTPS";
    httpsPort = 8443;
    target = "http://localhost:3000";
  };
}
