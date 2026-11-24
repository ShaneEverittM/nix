# `timelock`: keeps a secret behind a CPU-bound delay (a Rivest-Shamir-Wagner time-lock
# puzzle). Used for credentials that should be reachable, but never quickly: `timelock
# open` has to do a fixed number of sequential modular squarings -- about 30 minutes on
# this box by default -- before the secret comes out, and extra cores do not shorten it.
#
# WHY HERE. This box is the admin machine rather than a daily driver, so it is where the
# wait happens. The delay is the whole control: it holds against root too, because the
# secret is not on this machine in any recoverable form, only the puzzle is.
#
# NOTHING SECRET IS IN THIS FLAKE, and none may be added. The puzzles are state, in
# ~/.local/share/timelock (0600), and a puzzle file is itself sensitive: whoever holds a
# copy can open it after the same delay. Keep the off-box copy somewhere access-controlled.
#
# The delay is calibrated at `timelock lock` time against this CPU, and is CPU time: a
# faster machine opens the same puzzle sooner, a busy core later.
#
# The script (./timelock.py) needs gmpy2 for GMP-speed squaring -- with Python's own
# integers a solve would be several times slower than what an attacker's would be, which
# is delay given away -- and cryptography for the AEAD that wraps the secret.
{ pkgs, ... }:

let
  python = pkgs.python3.withPackages (p: [
    p.gmpy2
    p.cryptography
  ]);

  timelock = pkgs.writeTextFile {
    name = "timelock";
    executable = true;
    destination = "/bin/timelock";
    text = ''
      #!${pkgs.runtimeShell}
      exec ${python}/bin/python3 ${./timelock.py} "$@"
    '';
    # Round-trip a tiny puzzle at build time. A nixpkgs bump that broke either library
    # would otherwise first show up as a credential that cannot be opened.
    checkPhase = ''
      export TIMELOCK_DIR=$TMPDIR/timelock-check
      echo round-trip | $out/bin/timelock lock check --stdin --squarings 50000
      [ "$($out/bin/timelock open check)" = round-trip ]
    '';
  };
in
{
  environment.systemPackages = [ timelock ];
}
