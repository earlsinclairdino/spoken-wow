"""Run the addons' Lua tests without luajit, through lupa's Lua 5.1 (`pip install lupa`).

For a machine with Python and no luajit -- Windows, mostly. `make test-player` is the real
runner; this runs the same files the same way, each in a fresh Lua state, and exits non-zero if
any fails.

    python tests/run-lupa.py                  # every tests/lua/*_test.lua, the captions suite,
                                              # and settings_fit_test in every language
    python tests/run-lupa.py partysync_       # only the files whose name contains this
    python tests/run-lupa.py -v queue_test    # with each file's own output
"""
import glob
import locale
import os
import sys

# Python's Windows locale makes Lua's %s match byte 0xA0, which breaks the Chinese caption
# test. The client runs in the C locale.
locale.setlocale(locale.LC_CTYPE, "C")

from lupa import lua51  # noqa: E402

REPO = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
LANGUAGES = ["enUS", "deDE", "esES", "frFR", "ptBR", "ruRU", "koKR", "zhCN", "zhTW"]


def run(path, args, verbose):
    lua = lua51.LuaRuntime()
    table = {0: path}
    for i, value in enumerate(args):
        table[i + 1] = value
    lua.globals().arg = lua.table_from(table)
    lua.execute("os.exit = function(code) error({ exit = code }) end")
    if not verbose:
        lua.execute("print = function() end")
    result = lua.execute(
        "local ok, err = pcall(dofile, %r) "
        "if ok then return 0 end "
        "if type(err) == 'table' then return err.exit == nil and 0 or err.exit end "
        "return 'error: ' .. tostring(err)" % path)
    # Not `result in (0, None)`: 1 == True in Python, and an exit code of 1 must not pass.
    ok = result is None or (type(result) in (int, float) and result == 0)
    return ok, result


def main():
    args = sys.argv[1:]
    verbose = "-v" in args
    args = [a for a in args if a != "-v"]
    only = args[0] if args else ""
    os.chdir(REPO)
    runs = [(p.replace("\\", "/"), []) for p in sorted(glob.glob("tests/lua/*_test.lua"))
            if "settings_fit_test" not in p]
    runs += [("tests/lua/settings_fit_test.lua", [lang]) for lang in LANGUAGES]
    runs.append(("tests/captions/verify.lua", []))
    failed = 0
    for path, extra in runs:
        if only and only not in path:
            continue
        ok, result = run(path, extra, verbose)
        label = path + (" " + " ".join(extra) if extra else "")
        print(("PASS " if ok else "FAIL ") + label + ("" if ok else "  [%s]" % result))
        failed += 0 if ok else 1
    sys.exit(1 if failed else 0)


if __name__ == "__main__":
    main()
