# Sunshine: remote desktop for this box, streamed to Moonlight clients. Picked over RDP
# because it hardware-encodes on the iGPU (VAAPI) and is built for low latency on a LAN.
#
# Reachability is LAN-first: at home, point Moonlight at `retreat.local` (or let its
# mDNS discovery find the box) and the stream never leaves the wired segment; away from
# home, add the tailnet name as a second host in Moonlight. Pairing is a one-time PIN
# typed into the web UI, and the web UI's own login is created on first visit, so no
# credential lives in this public repo.
#
# The box runs headless, which Sunshine alone can't cope with -- it mirrors a live
# Plasma session on a real DRM output. So this module also supplies both halves of that:
# a Plasma session started on demand (`systemctl start remote-desktop`, typically over
# SSH) and a forced-on "virtual monitor" connector.
{
  config,
  lib,
  pkgs,
  ...
}:

let
  # Sunshine's default, restated (and fed back in as settings.port). Every other port is
  # an offset from this one.
  basePort = 47989;

  # Moonlight's control + media ports (HTTPS, HTTP, RTSP / video, control, audio, mic,
  # RTSP). Everything a client needs once paired.
  streamTCP = map (o: basePort + o) [
    (-5)
    0
    21
  ];
  streamUDP = map (o: basePort + o) [
    9
    10
    11
    13
    21
  ];
  # The admin web UI: pairing PINs, app list, and -- on a fresh install -- "whoever
  # gets here first sets the password".
  webUI = basePort + 1;

  # The connector that plays the phantom monitor. A DisplayPort one, because the
  # generated EDID below is a bare base block: on HDMI that reads as a DVI-class sink
  # capped at a 165 MHz pixel clock, which rules out 4K, while a forced DP connector
  # gets an assumed 4-lane HBR2 link from amdgpu -- enough for 4K60. A real monitor
  # plugged into this port is ignored in favour of that EDID, so physical screens go on
  # HDMI or the other DP port.
  virtualOutput = "DP-1";

  user = (import ../../lib/identity.nix).username;

  # The VT the on-demand session takes. SDDM's greeter owns tty1.
  vt = 8;

  plasma = pkgs.kdePackages.plasma-workspace;

  # `systemctl --user` for the account, callable from the system unit below: it runs
  # outside any login environment, so it has to find the user manager's bus itself.
  userctl = pkgs.writeShellScript "remote-desktop-userctl" ''
    export XDG_RUNTIME_DIR="/run/user/$(${pkgs.coreutils}/bin/id -u)"
    exec ${config.systemd.package}/bin/systemctl --user "$@"
  '';
in
{
  services.sunshine = {
    enable = true;
    # KMS capture reads the scanout buffer straight from DRM, which needs CAP_SYS_ADMIN.
    # It's the capture path that works on KWin/Wayland with no per-connection consent
    # prompt (unattended access is the whole point).
    capSysAdmin = true;
    # ...and it has to be pinned. Left to auto-detect, this Sunshine goes on from KMS to
    # probe XDG-portal capture, whose consent dialog nobody can answer on a headless,
    # locked session: startup blocks there forever, before any port is opened (and the
    # process then ignores SIGTERM until the 10 s watchdog aborts it).
    settings.port = basePort;
    settings.capture = "kms";
    # Auto-detect picks the Vulkan Video encoder ahead of VAAPI on this iGPU, and its
    # frame pacing is visibly uneven (window open/close animations stutter as if frames
    # were doubled). VAAPI on radeonsi is the long-established encode path.
    settings.encoder = "vaapi";
    # Opened per-interface below instead: the module's switch opens every port,
    # web UI included, on every interface (podman bridges and all).
    openFirewall = false;
  };

  # The web UI's CSRF check only accepts requests whose Origin is a localhost URL unless
  # others are listed in csrf_allowed_origins, so every form (starting with "set a
  # password") fails when the page is opened by the box's real name. The name that
  # matters is the full tailnet one, which this public repo must not contain -- so the
  # config Sunshine actually reads is assembled at service start: the settings above,
  # plus the origins for the MagicDNS short name and whatever tailnet name tailscaled
  # reports. Off the tailnet that lookup comes back empty and only the short name is
  # allowed. Settings live in the attrset above: the web UI's Configuration tab writes
  # to this per-start copy, so anything saved there is gone on the next restart
  # (pairing, apps, and the web UI login are separate state under ~/.config/sunshine).
  systemd.user.services.sunshine.serviceConfig = {
    RuntimeDirectory = "sunshine";
    ExecStartPre = pkgs.writeShellScript "sunshine-config" ''
      origins="https://${config.networking.hostName}:${toString webUI}"
      tailnet_name=$(${pkgs.tailscale}/bin/tailscale status --json 2>/dev/null \
        | ${pkgs.jq}/bin/jq -r '.Self.DNSName // empty | rtrimstr(".")' 2>/dev/null) || true
      if [ -n "$tailnet_name" ]; then
        origins="$origins,https://$tailnet_name:${toString webUI}"
      fi
      {
        ${pkgs.coreutils}/bin/cat ${
          (pkgs.formats.keyValue { }).generate "sunshine.conf" config.services.sunshine.settings
        }
        echo "csrf_allowed_origins = $origins"
      } > "$RUNTIME_DIRECTORY/sunshine.conf"
    '';
    ExecStart = lib.mkForce "${config.security.wrapperDir}/sunshine %t/sunshine/sunshine.conf";
  };

  networking.firewall.interfaces = {
    # The wired LAN port in use. Streaming only -- the web UI stays off the LAN.
    enp3s0 = {
      allowedTCPPorts = streamTCP;
      allowedUDPPorts = streamUDP;
    };
    # The tailnet is device-authenticated, so it also gets the web UI:
    # https://<tailnet name>:47990 for pairing.
    tailscale0 = {
      allowedTCPPorts = streamTCP ++ [ webUI ];
      allowedUDPPorts = streamUDP;
    };
  };

  # Sunshine is a user service hanging off graphical-session.target, so with nobody
  # logged in there is nothing to connect to. Rather than auto-login (a desktop session,
  # and everything it autostarts, running around the clock on what is mostly a server),
  # this unit *is* a login: PAMName + TTYPath make logind register a real seat0 session
  # on its own VT, as a display manager would, and Plasma starts inside it. Sunshine
  # comes up with the session and goes away with it.
  #
  #   ssh retreat systemctl start remote-desktop    # then connect Moonlight
  #   ssh retreat systemctl stop remote-desktop     # log out; back to the greeter
  #
  # Deliberately not wantedBy anything: it only ever runs when asked for.
  systemd.services.remote-desktop = {
    description = "On-demand Plasma session for Sunshine remote desktop";
    after = [
      "systemd-user-sessions.service"
      "display-manager.service"
    ];

    environment = {
      XDG_SESSION_TYPE = "wayland";
      XDG_SESSION_CLASS = "user";
      XDG_SESSION_DESKTOP = "KDE";
      XDG_CURRENT_DESKTOP = "KDE";
    };

    serviceConfig = {
      User = user;
      WorkingDirectory = "~";
      PAMName = "remote-desktop";

      TTYPath = "/dev/tty${toString vt}";
      TTYReset = true;
      TTYVHangup = true;
      TTYVTDisallocate = true;
      StandardInput = "tty-fail";
      StandardOutput = "journal";
      StandardError = "journal";
      UtmpIdentifier = "tty${toString vt}";
      UtmpMode = "user";

      # One Plasma session per user: the user manager has a single
      # graphical-session.target, so a second session on top of a console login would
      # fight over it. A non-zero exit here skips the start cleanly (not a failure).
      ExecCondition = pkgs.writeShellScript "remote-desktop-condition" ''
        if ${userctl} is-active --quiet graphical-session.target; then
          echo "a graphical session is already running; not starting another" >&2
          exit 1
        fi
      '';

      ExecStartPre = [
        # logind only hands the DRM device to the session on the foreground VT. `+` = root.
        "+${pkgs.kbd}/bin/chvt ${toString vt}"
        # Session units are start-limited across logins; a previous run's crashes must
        # not veto this one.
        "-${userctl} reset-failed"
      ];
      # A login shell, so the session gets the same /etc/profile environment (PATH,
      # session variables) a display manager's session wrapper would have given it.
      ExecStart = "${pkgs.bash}/bin/bash -l -c 'exec ${plasma}/libexec/plasma-dbus-run-session-if-needed ${plasma}/bin/startplasma-wayland'";
      ExecStopPost = [
        # `systemctl stop` kills startplasma before it can wind the session down itself,
        # so stop the user-side units (Sunshine included) explicitly.
        "-${userctl} stop graphical-session.target"
        "+-${pkgs.kbd}/bin/chvt 1"
      ];
    };
  };

  # The unit's PAM stack: account + a pam_systemd session, which is what turns the
  # service into a logind session with a seat.
  security.pam.services.remote-desktop.startSession = true;

  # Let the account start and stop this one unit without a password prompt -- there is
  # no polkit agent to answer one over SSH. Reaching this at all already took the SSH key.
  security.polkit.extraConfig = ''
    polkit.addRule(function (action, subject) {
      if (
        action.id == "org.freedesktop.systemd1.manage-units" &&
        action.lookup("unit") == "remote-desktop.service" &&
        subject.user == "${user}"
      ) {
        return polkit.Result.YES;
      }
    });
  '';

  # The session opens on the lock screen, so a paired Moonlight client (or anyone at
  # the console while it is up) still needs the account password. This is the system
  # KConfig layer and applies to console logins through SDDM as well; a user-level
  # kscreenlockerrc can override it.
  environment.etc."xdg/kscreenlockerrc".text = ''
    [Daemon]
    LockOnStart=true
  '';

  # With no monitor attached every connector reads "disconnected" and KWin has no
  # output for Sunshine to capture. Force one on. amdgpu refuses to force a connector
  # without an EDID to build its emulated sink from, and the kernel's built-in EDIDs
  # were removed in 6.10, so generate one: 3840x2160@60, CVT reduced blanking (533.25
  # MHz, inside the forced link's budget -- 4K120 is not). To stream at another
  # resolution, change the modeline -- or drop this block and use a hardware dummy
  # plug, which does the same job from outside the kernel.
  hardware.display = {
    edid.modelines.headless4k = "533.25  3840 3888 3920 4000  2160 2163 2168 2222  +hsync -vsync";
    outputs.${virtualOutput} = {
      edid = "headless4k.bin";
      mode = "e";
    };
  };
}
