#!/usr/bin/env python3
"""rfnm_boards.py — tiny shared parser for the SDK's boards.toml. Stdlib only.

Python API:
    import rfnm_boards
    cfg   = rfnm_boards.load()          # whole config dict
    board = rfnm_boards.get("blue0")    # one [board.<name>] table

CLI (for shell tools):
    python3 tools/rfnm_boards.py path                       # resolved boards.toml path
    python3 tools/rfnm_boards.py list                       # board names, one per line
    python3 tools/rfnm_boards.py host <field> [default]     # [host] field
    python3 tools/rfnm_boards.py get <board> <field> [default]   # dotted, e.g. power.backend
    python3 tools/rfnm_boards.py first-rootfs               # first board's rootfs (sysroot)
    python3 tools/rfnm_boards.py audit                      # [audit] map as "deployed<TAB>artifact"

Without a [default], a missing file/board/field is a hard error (exit 1, message on
stderr) — tools fail loudly instead of running with empty strings.

boards.toml search order: $RFNM_BOARDS_TOML, ./boards.toml, <sdk root>/boards.toml
(sdk root = parent directory of tools/).
"""
import os
import sys

try:
    import tomllib  # python >= 3.11
except ImportError:
    tomllib = None


def _mini_toml(text):
    """Fallback parser for the boards.toml subset: [a.b] tables, key = value with
    string / int / float / bool values, quoted keys, # comments. Not general TOML."""
    root, cur = {}, None
    root_cur = root

    def unquote(tok):
        tok = tok.strip()
        if len(tok) >= 2 and tok[0] == tok[-1] and tok[0] in "\"'":
            return tok[1:-1]
        return tok

    def value(tok):
        tok = tok.strip()
        if tok and tok[0] in "\"'":
            return unquote(tok)
        if tok in ("true", "false"):
            return tok == "true"
        try:
            return int(tok)
        except ValueError:
            pass
        try:
            return float(tok)
        except ValueError:
            raise ValueError("unparseable value: %r" % tok)

    def strip_comment(line):
        out, q = [], None
        for c in line:
            if q:
                out.append(c)
                if c == q:
                    q = None
            elif c in "\"'":
                q = c
                out.append(c)
            elif c == "#":
                break
            else:
                out.append(c)
        return "".join(out).strip()

    for raw in text.splitlines():
        line = strip_comment(raw)
        if not line:
            continue
        if line.startswith("[") and line.endswith("]"):
            parts = [unquote(p) for p in line[1:-1].split(".")]
            cur = root
            for p in parts:
                cur = cur.setdefault(p, {})
            root_cur = cur
            continue
        if "=" not in line:
            raise ValueError("bad line: %r" % raw)
        k, _, v = line.partition("=")
        root_cur[unquote(k)] = value(v)
    return root


def find_toml():
    cand = [os.environ.get("RFNM_BOARDS_TOML"),
            os.path.join(os.getcwd(), "boards.toml"),
            os.path.join(os.path.dirname(os.path.dirname(os.path.abspath(__file__))), "boards.toml")]
    for p in cand:
        if p and os.path.isfile(p):
            return p
    return None


def load(path=None):
    path = path or find_toml()
    if not path:
        raise FileNotFoundError(
            "boards.toml not found (looked at $RFNM_BOARDS_TOML, ./boards.toml, SDK root)."
            " Copy boards.toml.example to boards.toml and edit it.")
    with open(path, "rb") as fh:
        raw = fh.read()
    if tomllib:
        return tomllib.loads(raw.decode())
    return _mini_toml(raw.decode())


def get(board, cfg=None):
    cfg = cfg or load()
    boards = cfg.get("board", {})
    if board not in boards:
        raise KeyError("board %r not in boards.toml (have: %s)" % (board, ", ".join(sorted(boards)) or "none"))
    return boards[board]


def _dig(table, dotted):
    cur = table
    for part in dotted.split("."):
        if not isinstance(cur, dict) or part not in cur:
            raise KeyError(dotted)
        cur = cur[part]
    return cur


def _die(msg):
    sys.stderr.write("rfnm_boards: %s\n" % msg)
    sys.exit(1)


def _print(v):
    if isinstance(v, bool):
        v = "true" if v else "false"
    print(v)


def main(argv):
    if len(argv) < 1:
        _die("usage: rfnm_boards.py path|list|host|get|first-rootfs|audit ... (see --help in module docstring)")
    cmd, args = argv[0], argv[1:]
    try:
        if cmd == "path":
            p = find_toml()
            if not p:
                _die("boards.toml not found — copy boards.toml.example to the SDK root")
            print(p)
            return
        cfg = load()
        if cmd == "list":
            for name in cfg.get("board", {}):
                print(name)
        elif cmd == "host":
            if not args:
                _die("usage: rfnm_boards.py host <field> [default]")
            try:
                _print(_dig(cfg.get("host", {}), args[0]))
            except KeyError:
                if len(args) > 1:
                    print(args[1])
                else:
                    _die("[host] has no field %r" % args[0])
        elif cmd == "get":
            if len(args) < 2:
                _die("usage: rfnm_boards.py get <board> <field> [default]")
            table = get(args[0], cfg)
            try:
                _print(_dig(table, args[1]))
            except KeyError:
                if len(args) > 2:
                    print(args[2])
                else:
                    _die("board %r has no field %r" % (args[0], args[1]))
        elif cmd == "first-rootfs":
            for name, table in cfg.get("board", {}).items():
                rootfs = table.get("rootfs", "")
                if rootfs:
                    print(os.path.expanduser(rootfs))
                    return
            _die("no board in boards.toml has a rootfs configured")
        elif cmd == "audit":
            for k, v in cfg.get("audit", {}).items():
                print("%s\t%s" % (k, v))
        else:
            _die("unknown command %r" % cmd)
    except (FileNotFoundError, KeyError, ValueError) as e:
        _die(e.args[0] if e.args else str(e))


if __name__ == "__main__":
    main(sys.argv[1:])
