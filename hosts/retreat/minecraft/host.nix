# Host half of the Minecraft servers: everything that has to stay on this side of the VM
# boundary. ./service.nix is the guest half; ../gameservers.nix is the generic layer that
# turns each `publicGameServers.servers.<name>` declared here into a microVM.
#
# STORAGE STAYS ON THE HOST. Each pack tree is a host directory shared into its guest
# over virtiofs at the same path, and each world is still its own NOCOW btrfs subvolume
# *here*. That is the whole snapshot story: btrbk (../btrbk.nix) keeps snapshotting and
# replicating those subvolumes exactly as it did when the JVM ran on the host, a guest
# holds no backup credentials, and destroying a guest loses nothing. The price is a
# share, not an image, between the two kernels -- so the quiesce has to end with the
# guest flushing through to the host (see the listener in ./service.nix).
#
# The trees live under /var/lib/minecraft, not in a home directory: a share exposes
# everything beneath its source, and nobody's home belongs inside a public-facing guest.
{
  config,
  lib,
  pkgs,
  ...
}:

let
  cfg = config.publicMinecraft;
  snapshotted = lib.filterAttrs (_: srv: srv.snapshotWorld) cfg.servers;

  # Packs that share a public port share a network slot, which is what makes them
  # mutually exclusive (see ../gameservers.nix). Slots are numbered by port, in order.
  ports = lib.unique (lib.sort lib.lessThan (lib.mapAttrsToList (_: srv: srv.port) cfg.servers));
  slotOf = srv: (lib.lists.findFirstIndex (p: p == srv.port) null ports) + 1;
  hostAddr = srv: "10.77.${toString (slotOf srv)}.1";
  guestAddr = srv: "10.77.${toString (slotOf srv)}.2";

  # The host's side of a freeze/thaw: one word to the guest's listener, its transcript
  # back. Never fails the btrbk run -- home still needs its snapshot whatever state a
  # game server is in -- so every path exits 0 and problems are reported by shouting.
  snapshotSaves =
    name: srv:
    pkgs.writeShellApplication {
      name = "${name}-snapshot-saves";
      runtimeInputs = with pkgs; [
        coreutils
        gnugrep
        gnused
        socat
        systemd
      ];
      text = ''
        mode="''${1:?usage: ${name}-snapshot-saves freeze|thaw}"

        # A stopped guest shut its server down with SIGTERM, which saves: the world on
        # disk is already a clean checkpoint. That is the norm for a disabled pack.
        if ! systemctl is-active --quiet microvm@${name}.service; then
          echo "${name} guest not running -- world already at rest, skipping $mode"
          exit 0
        fi

        # -t: how long to keep reading after our one line is sent. It has to outlast the
        # guest's own worst case (save-all flush on a big world; three save-on retries).
        out="$(printf '%s\n' "$mode" |
          timeout 200 socat -t 180 - TCP:${guestAddr srv}:${toString cfg.snapshotControl.port},connect-timeout=10 2>&1)" ||
          out="$out
        <no answer from the guest>"
        printf '%s\n' "$out" | sed 's/^/  /'

        if printf '%s' "$out" | grep -q "^DONE $mode\$" &&
          ! printf '%s' "$out" | grep -qE 'WARNING|ERROR'; then
          exit 0
        fi
        case "$mode" in
          freeze) echo "WARNING: ${name} was not quiesced -- this snapshot of its world is only crash-consistent" ;;
          thaw) echo "ERROR: ${name} may still have autosave OFF -- restart it ('gameserver restart ${name}') if this persists" ;;
        esac
        exit 0
      '';
    };
in
{
  imports = [
    ./options.nix
    ../gameservers.nix
  ];

  config = lib.mkIf (cfg.servers != { }) {
    # Owner of the pack trees, by the same fixed number the guests use. No login, no
    # home: to work on a pack by hand, `sudo -u minecraft -s` in its directory.
    users.users.minecraft = {
      isSystemUser = true;
      inherit (cfg) uid;
      group = "minecraft";
    };
    users.groups.minecraft.gid = cfg.uid;

    systemd.tmpfiles.rules = [
      "d /var/lib/minecraft 0755 root root - -"
    ]
    ++ lib.concatLists (
      lib.mapAttrsToList (_: srv: [
        # The pack tree itself: a plain directory, populated by hand. 0750: the server
        # writes its files 0600 anyway (UMask in the unit), and nothing else on the
        # host has business in here -- server.properties holds the RCON password.
        "d ${srv.serverDir} 0750 ${srv.user} ${srv.user} - -"
        # The world as its own NOCOW subvolume, created empty *before* first launch so the
        # .mca region files never fragment under CoW -- NOCOW is inherited only by files
        # created after the attribute is set, which is why creating it here (empty, at boot,
        # ahead of the guest) is the only way to get it right without a manual ritual. `v`
        # makes a btrfs subvolume and only acts when the path doesn't already exist, so a
        # live world is untouched. It also guarantees btrbk's subvolume list can't name
        # something that doesn't exist yet, which would fail the whole run -- home included.
        #
        # This has to happen here and not in the guest: through virtiofs the guest could
        # only ever make a plain directory.
        #
        # Resetting a world later is still NOT a plain `rm -rf world` -- that either fails
        # on the subvolume or removes it and a reflexive `mkdir world` silently gives back a
        # CoW directory. Delete the subvolume and let these lines recreate it:
        #     gameserver stop <name>
        #     btrfs subvolume delete <serverDir>/world
        #     systemd-tmpfiles --create        # remakes the subvolume, NOCOW, correct owner
        "v ${srv.serverDir}/world 0750 ${srv.user} ${srv.user} - -"
        "h ${srv.serverDir}/world - - - - +C"
      ]) cfg.servers
    );

    # e2fsprogs supplies chattr/lsattr -- not in the base system profile, and needed to
    # check the NOCOW state of a world subvolume (`lsattr -d <dir>`).
    environment.systemPackages = [ pkgs.e2fsprogs ];

    publicGameServers.servers = lib.mapAttrs (name: srv: {
      slot = slotOf srv;
      inherit (srv) memory vcpu autoStart;
      forwardTCP = [ srv.port ];
      shares = [ srv.serverDir ];
      guest = {
        imports = [ ./service.nix ];
        publicMinecraft = {
          inherit (cfg) uid;
          # worldSubvolume is read-only and derives from serverDir on its own.
          servers.${name} = removeAttrs srv [ "worldSubvolume" ];
          snapshotControl = {
            enable = srv.snapshotWorld;
            inherit (cfg.snapshotControl) port;
            allowFrom = hostAddr srv;
          };
        };
      };
    }) cfg.servers;

    # ---- clean snapshots -------------------------------------------------------
    # Extends the unit generated by services.btrbk.instances.local in ../btrbk.nix: one
    # freeze/thaw pair per snapshotted pack, run in sequence around the btrbk run.
    #
    # `+` runs these as root: btrbk-local.service is User=btrbk, which may not query
    # the guests' units.
    #
    # ExecStopPost (not ExecStop) because it must also run when btrbk fails or is killed --
    # that is the whole reason the thaw is a systemd hook instead of a line in a script.
    systemd.services.btrbk-local.serviceConfig = {
      ExecStartPre = lib.mapAttrsToList (
        name: srv: "+${snapshotSaves name srv}/bin/${name}-snapshot-saves freeze"
      ) snapshotted;
      ExecStopPost = lib.mapAttrsToList (
        name: srv: "+${snapshotSaves name srv}/bin/${name}-snapshot-saves thaw"
      ) snapshotted;
    };
  };
}
