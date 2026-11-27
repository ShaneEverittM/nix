# Plex Media Server, native (nixpkgs `services.plex`), serving the home LAN and the
# tailnet.
#
# ACCESS. Unlike beszel and sure this is NOT behind `tailscale serve`: the clients that
# matter (TVs, consoles, streaming sticks) cannot join a tailnet and find the server by
# LAN discovery, so Plex's ports are opened in the host firewall. That makes it reachable
# from the LAN and, since the firewall is not per-interface, from tailnet devices at
# http://retreat:32400/web. It is not reachable from the internet: the router forwards
# only the game-server ports, and Plex's own "Remote Access" (Settings -> Remote Access)
# should stay disabled so it does not ask the router for a UPnP mapping. Away from home,
# use Tailscale.
#
# It runs on the host rather than in a microVM like the game servers (./gameservers.nix):
# those are internet-facing, this is not, and it wants the iGPU.
#
# FIRST RUN. A fresh server only lets a client on the same machine claim it, and this box
# has no browser. From a workstation:
#   ssh -L 32400:localhost:32400 retreat
# then open http://localhost:32400/web, sign in, and add libraries pointing at
# /srv/media/movies and /srv/media/tv. Nothing about the account lives in this flake.
#
# MEDIA lives in /srv/media, its own subvolume, owned by the login user so files can be
# copied in over SSH/rsync without sudo; Plex only reads it. It must not live under
# /home: the unit runs with ProtectHome, and `home` is in the btrbk timeline. /srv/media
# is deliberately in neither the snapshots nor the push to rebirth (./btrbk.nix lists its
# subvolumes explicitly, so leaving it out is all that takes) -- it is large and
# re-obtainable.
#
# STATE is /var/lib/plex: the library database, metadata, watch history and the server's
# identity. Also not backed up off-box. Plex keeps its own rotating database backups
# inside that directory, which cover a corrupt database but not a dead disk; losing it
# means re-claiming the server and re-scanning, with watch state gone.
_:

let
  identity = import ../../lib/identity.nix;
  mediaDir = "/srv/media";
in
{
  services.plex = {
    enable = true;
    # TCP 32400 (the server) plus the LAN discovery/companion ports (GDM, DLNA).
    openFirewall = true;
  };

  # Hardware transcoding on the AMD iGPU (VA-API via /dev/dri/renderD128). The device
  # nodes are group render/video; the module already leaves them visible to the unit
  # (accelerationDevices = [ "*" ]). Plex only uses this with a Plex Pass -- without one
  # these lines are inert and transcodes run on the CPU.
  users.users.plex.extraGroups = [
    "render"
    "video"
  ];
  # The Mesa VA-API driver, at /run/opengl-driver where the plex unit's LD_LIBRARY_PATH
  # looks. Off by default on this box since the desktop went; no display stack comes
  # back with it.
  hardware.graphics.enable = true;

  # Plex sends its own WARN/ERROR lines to syslog at matching priorities, and most of
  # them are chatter about clients and optional features rather than about the server:
  # they were four fifths of this host's warning-and-up journal. The patterns below drop
  # exactly the ones seen and understood here, so a line of any other shape still shows.
  # Dropped means not journalled at all; Plex's own log files under /var/lib/plex keep
  # everything.
  systemd.services.plex.serviceConfig.LogFilterPatterns = [
    # A client's notification websocket being torn down mid-frame, e.g. an app that is
    # closed or a TV that goes to sleep.
    "~WebSocket: (closing connection due to (fragmentation|large frame)|Ignoring message since we.re closing the connection|Received unmasked data, shutting down connection|Unexpected opcode )"
    # A transcode job that had already finished when its client asked after it.
    "~JobManager: Could not find job for handle "
    "~FFMPEG. - deprecated pixel format used, make sure you did set range correctly"
    # Clients asking for legacy metadata agents (TheTVDB, IMDb, ...) that current servers
    # no longer ship.
    "~Request for plug-in .com.plexapp.agents.[a-z]+. but it doesn.t exist"
    "~Unknown metadata type: folder"
    # Newer clients sending query fields this server version does not know.
    "~QueryParser: Invalid field .* found, ignoring"
    # Seek-bar preview thumbnails that were never generated for an item.
    "~Error opening file .*/Indexes/index-sd.bif.* - No such file or directory"
  ];

  systemd.tmpfiles.rules = [
    "d /srv 0755 root root - -"
    # `v` makes a subvolume on btrfs and only acts when the path doesn't exist yet.
    "v ${mediaDir} 0755 ${identity.username} users - -"
    "d ${mediaDir}/movies 0755 ${identity.username} users - -"
    "d ${mediaDir}/tv 0755 ${identity.username} users - -"
  ];
}
