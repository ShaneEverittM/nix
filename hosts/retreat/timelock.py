"""timelock - keep a secret behind a CPU-bound delay (Rivest-Shamir-Wagner puzzle).

  timelock lock   [NAME] [--minutes 30] [--stdin]   create a puzzle (generates a password)
  timelock open   [NAME]                            solve it; prints the secret when done
  timelock cancel [NAME]                            stop a running solve and discard its progress
  timelock status [NAME]                            show puzzle and solve progress
  timelock calibrate [--seconds 10]                 measure this CPU's squarings per second

Opening needs T sequential modular squarings, which extra cores cannot speed up.
Locking is instant because the creator briefly knows the factors of the modulus.
Ctrl-C during `open` pauses (progress is kept); `cancel` throws progress away.
"""

import argparse
import fcntl
import hashlib
import json
import os
import secrets
import signal
import string
import sys
import time
from pathlib import Path

import gmpy2
from cryptography.exceptions import InvalidTag
from cryptography.hazmat.primitives.ciphers.aead import ChaCha20Poly1305
from gmpy2 import mpz

VERSION = 1
MODULUS_BITS = 2048
CHUNK = 1 << 14  # squarings per powmod call
CHECKPOINT_EVERY = 5.0  # seconds
STATE = Path(os.environ.get("TIMELOCK_DIR", Path.home() / ".local/share/timelock"))


def die(msg):
    print(f"timelock: {msg}", file=sys.stderr)
    sys.exit(1)


def fmt_duration(seconds):
    seconds = int(round(seconds))
    h, rem = divmod(seconds, 3600)
    m, s = divmod(rem, 60)
    if h:
        return f"{h}h{m:02d}m"
    if m:
        return f"{m}m{s:02d}s"
    return f"{s}s"


def paths(name):
    if not name.replace("-", "").replace("_", "").isalnum():
        die(f"bad name {name!r}: use letters, digits, - and _")
    return {
        "puzzle": STATE / f"{name}.puzzle.json",
        "prev": STATE / f"{name}.puzzle.prev.json",
        "checkpoint": STATE / f"{name}.checkpoint.json",
        "lock": STATE / f"{name}.lock",
    }


def write_private(path, data):
    """Atomically write a 0600 file."""
    tmp = path.with_name(path.name + ".tmp")
    fd = os.open(tmp, os.O_WRONLY | os.O_CREAT | os.O_TRUNC, 0o600)
    with os.fdopen(fd, "w") as f:
        f.write(data)
        f.flush()
        os.fsync(f.fileno())
    os.replace(tmp, path)


def random_prime(bits):
    while True:
        candidate = mpz(secrets.randbits(bits) | (0b11 << (bits - 2)) | 1)
        prime = gmpy2.next_prime(candidate)
        if prime.bit_length() == bits:
            return prime


def square_n(x, count, n):
    """x^(2^count) mod n, done as `count` sequential squarings."""
    return gmpy2.powmod(x, mpz(1) << count, n)


def measure_rate(seconds):
    n = random_prime(MODULUS_BITS // 2) * random_prime(MODULUS_BITS // 2)
    x = mpz(secrets.randbelow(int(n) - 3) + 2)
    done = 0
    start = time.perf_counter()
    while (elapsed := time.perf_counter() - start) < seconds:
        x = square_n(x, CHUNK, n)
        done += CHUNK
    return done / elapsed


def derive_key(b):
    raw = int(b).to_bytes((MODULUS_BITS + 7) // 8, "big")
    return hashlib.sha256(b"timelock-v1-key\0" + raw).digest()


def aad(n, a, t):
    return f"timelock-v{VERSION}|{int(n):x}|{int(a):x}|{t}".encode()


def load_puzzle(p):
    if not p["puzzle"].exists():
        die(f"no puzzle at {p['puzzle']} (run `timelock lock` first)")
    puzzle = json.loads(p["puzzle"].read_text())
    if puzzle.get("version") != VERSION:
        die(f"unsupported puzzle version {puzzle.get('version')}")
    return puzzle


def puzzle_id(puzzle):
    return hashlib.sha256((puzzle["n"] + puzzle["a"] + str(puzzle["t"])).encode()).hexdigest()[:16]


def load_checkpoint(p, puzzle):
    try:
        cp = json.loads(p["checkpoint"].read_text())
    except (FileNotFoundError, json.JSONDecodeError):
        return None
    if cp.get("puzzle_id") != puzzle_id(puzzle) or not 0 <= cp.get("done", -1) <= puzzle["t"]:
        return None
    return cp


def solver_pid(p):
    """PID of a running solver for this puzzle, or None."""
    try:
        with open(p["lock"], "r+") as f:
            try:
                fcntl.flock(f, fcntl.LOCK_EX | fcntl.LOCK_NB)
            except BlockingIOError:
                return int(f.read().strip() or 0) or None
    except FileNotFoundError:
        pass
    return None


# --- commands ---------------------------------------------------------------


def cmd_calibrate(args):
    print(f"measuring for {args.seconds:g}s on one core...", file=sys.stderr)
    rate = measure_rate(args.seconds)
    print(f"{rate:,.0f} squarings/s ({MODULUS_BITS}-bit modulus)")
    print(f"30 minutes = {int(rate * 1800):,} squarings")


def cmd_lock(args):
    p = paths(args.name)
    STATE.mkdir(mode=0o700, parents=True, exist_ok=True)
    if solver_pid(p):
        die("a solve is running for this puzzle; `timelock cancel` it first")
    if p["puzzle"].exists() and not args.force:
        die(
            f"{p['puzzle']} already exists.\n"
            "  Re-locking replaces it, so the service must be switched to the NEW secret.\n"
            "  Pass --force to replace it (the old puzzle is kept as .prev.json)."
        )

    if args.stdin:
        secret = sys.stdin.readline().rstrip("\n")
        if not secret:
            die("empty secret on stdin")
    else:
        alphabet = string.ascii_letters + string.digits
        secret = "-".join("".join(secrets.choice(alphabet) for _ in range(6)) for _ in range(5))

    if args.squarings:
        t, rate = args.squarings, None
    else:
        print("calibrating (5s)...", file=sys.stderr)
        rate = measure_rate(5)
        t = int(rate * args.minutes * 60)

    prime_p, prime_q = random_prime(MODULUS_BITS // 2), random_prime(MODULUS_BITS // 2)
    n = prime_p * prime_q
    phi = (prime_p - 1) * (prime_q - 1)
    a = mpz(secrets.randbelow(int(n) - 3) + 2)
    # Trapdoor: reduce the exponent 2^t modulo phi(n), then one cheap exponentiation.
    b = gmpy2.powmod(a, gmpy2.powmod(2, t, phi), n)
    del prime_p, prime_q, phi

    nonce = secrets.token_bytes(12)
    ciphertext = ChaCha20Poly1305(derive_key(b)).encrypt(nonce, secret.encode(), aad(n, a, t))
    del b

    puzzle = {
        "version": VERSION,
        "name": args.name,
        "created": time.strftime("%Y-%m-%dT%H:%M:%S%z"),
        "n": f"{int(n):x}",
        "a": f"{int(a):x}",
        "t": t,
        "rate_at_lock": rate,
        "nonce": nonce.hex(),
        "ciphertext": ciphertext.hex(),
    }
    if p["puzzle"].exists():
        os.replace(p["puzzle"], p["prev"])
    p["checkpoint"].unlink(missing_ok=True)
    write_private(p["puzzle"], json.dumps(puzzle, indent=1) + "\n")

    eta = f" (~{fmt_duration(t / rate)} on this CPU)" if rate else ""
    print(f"locked {args.name!r}: {t:,} squarings{eta}", file=sys.stderr)
    print(f"puzzle: {p['puzzle']}", file=sys.stderr)
    if not args.stdin:
        print(
            "\nNew secret - shown once, set it on the service now, then clear your terminal:\n",
            file=sys.stderr,
        )
        print(secret)


def cmd_open(args):
    p = paths(args.name)
    puzzle = load_puzzle(p)
    n, t = mpz(puzzle["n"], 16), puzzle["t"]

    lock_file = open(p["lock"], "a+")
    try:
        fcntl.flock(lock_file, fcntl.LOCK_EX | fcntl.LOCK_NB)
    except BlockingIOError:
        die("a solve is already running for this puzzle (see `timelock status`)")
    lock_file.seek(0)
    lock_file.truncate()
    lock_file.write(str(os.getpid()))
    lock_file.flush()

    cp = load_checkpoint(p, puzzle)
    if cp:
        x, done = mpz(cp["x"], 16), cp["done"]
        print(f"resuming at {done / t:.1%}", file=sys.stderr)
    else:
        x, done = mpz(puzzle["a"], 16), 0

    stop = None

    def on_signal(signum, _frame):
        nonlocal stop
        stop = signum

    signal.signal(signal.SIGINT, on_signal)
    signal.signal(signal.SIGTERM, on_signal)

    def checkpoint():
        write_private(
            p["checkpoint"],
            json.dumps(
                {
                    "puzzle_id": puzzle_id(puzzle),
                    "done": done,
                    "x": f"{int(x):x}",
                    "saved": time.time(),
                }
            ),
        )

    tty = sys.stderr.isatty()
    start = last_cp = last_print = time.perf_counter()
    start_done = done
    while done < t and stop is None:
        step = min(CHUNK, t - done)
        x = square_n(x, step, n)
        done += step
        now = time.perf_counter()
        if now - last_cp >= CHECKPOINT_EVERY:
            checkpoint()
            last_cp = now
        if now - last_print >= (0.5 if tty else 60):
            rate = (done - start_done) / (now - start)
            line = f"{done / t:6.1%}  {rate:,.0f} sq/s  {fmt_duration((t - done) / rate)} left"
            print(
                f"\r{line}   " if tty else line,
                end="" if tty else "\n",
                file=sys.stderr,
                flush=True,
            )
            last_print = now
    if tty:
        print("\r" + " " * 60 + "\r", end="", file=sys.stderr)

    if done < t:
        if stop == signal.SIGTERM:  # sent by `cancel`, which wipes the checkpoint
            print(f"stopped at {done / t:.1%}", file=sys.stderr)
            sys.exit(143)
        checkpoint()
        print(
            f"paused at {done / t:.1%}; `timelock open` resumes, `timelock cancel` discards",
            file=sys.stderr,
        )
        sys.exit(130)

    try:
        secret = ChaCha20Poly1305(derive_key(x)).decrypt(
            bytes.fromhex(puzzle["nonce"]),
            bytes.fromhex(puzzle["ciphertext"]),
            aad(n, mpz(puzzle["a"], 16), t),
        )
    except InvalidTag:
        p["checkpoint"].unlink(missing_ok=True)
        die("solved, but decryption failed: the puzzle or checkpoint is corrupt or tampered with")
    p["checkpoint"].unlink(missing_ok=True)
    print(f"opened {args.name!r} in {fmt_duration(time.perf_counter() - start)}.", file=sys.stderr)
    print("When you are done, rotate the secret: `timelock lock --force`.\n", file=sys.stderr)
    print(secret.decode())


def cmd_cancel(args):
    p = paths(args.name)
    pid = solver_pid(p)
    if pid:
        os.kill(pid, signal.SIGTERM)
        for _ in range(100):
            if not solver_pid(p):
                break
            time.sleep(0.1)
        else:
            die(f"solver (pid {pid}) did not stop")
    had_progress = p["checkpoint"].exists()
    p["checkpoint"].unlink(missing_ok=True)
    if pid or had_progress:
        print("cancelled: solver stopped and progress discarded" if pid else "progress discarded")
    else:
        print("nothing to cancel")


def cmd_status(args):
    p = paths(args.name)
    puzzle = load_puzzle(p)
    t, rate = puzzle["t"], puzzle.get("rate_at_lock")
    eta = f", ~{fmt_duration(t / rate)} at lock-time speed" if rate else ""
    print(f"puzzle   {args.name!r}, created {puzzle['created']}")
    print(f"work     {t:,} squarings{eta}")
    pid = solver_pid(p)
    cp = load_checkpoint(p, puzzle)
    if pid:
        print(f"solver   RUNNING (pid {pid})")
    else:
        print("solver   not running")
    if cp:
        left = f", ~{fmt_duration((t - cp['done']) / rate)} left" if rate else ""
        age = fmt_duration(time.time() - cp["saved"])
        print(f"progress {cp['done'] / t:.1%}{left} (checkpoint {age} old)")
    else:
        print("progress none")


def main():
    parser = argparse.ArgumentParser(
        prog="timelock", description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter
    )
    sub = parser.add_subparsers(dest="cmd", required=True)

    def named(name, func):
        sp = sub.add_parser(name)
        sp.add_argument("name", nargs="?", default="unifi")
        sp.set_defaults(func=func)
        return sp

    sp = named("lock", cmd_lock)
    sp.add_argument("--minutes", type=float, default=30)
    sp.add_argument("--squarings", type=int, help="set the work directly instead of calibrating")
    sp.add_argument(
        "--stdin", action="store_true", help="read the secret from stdin instead of generating one"
    )
    sp.add_argument("--force", action="store_true", help="replace an existing puzzle")
    named("open", cmd_open)
    named("cancel", cmd_cancel)
    named("status", cmd_status)
    sp = sub.add_parser("calibrate")
    sp.add_argument("--seconds", type=float, default=10)
    sp.set_defaults(func=cmd_calibrate)

    args = parser.parse_args()
    args.func(args)


if __name__ == "__main__":
    main()
