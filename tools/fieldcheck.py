"""Offline check that every <game extension>.<field> the mods read exists in the game's own Lua (refcheck.py
checks the globals; this checks what is read off them: gameplay_missions_missions.get() was a nil field hidden by
a pcall, and the map listed no missions). A game extension is a file under lua/ge/extensions (or common); its
exports are its M.<name> definitions. Modules that build M in a loop or through a metatable are skipped.
Run: python tools/fieldcheck.py [repo ...]   (default: all four mods). Prints the findings and 'fieldcheck ok', or exits 1."""
import os, re, sys, glob

HERE = os.path.dirname(os.path.abspath(__file__))
SL = os.path.dirname(HERE)
DEV = os.path.dirname(SL)
GAME = os.environ.get('BEAMNG_LUA', r'I:\SteamLibrary\steamapps\common\BeamNG.drive\lua')
MODS = sys.argv[1:] or [SL] + [os.path.join(DEV, d) for d in ('Beam NG SLRR MOD', 'SLRR map for beam ng', 'SLRR Drivers')]
EXPORT_RX = re.compile(r'^\s*(?:function\s+M\.|M\.)(\w+)\s*[=(]', re.M)
OPAQUE_RX = re.compile(r'setmetatable\s*\(\s*M\b|^\s*M\s*=\s*\w+\s*$|do\s+M\[', re.M)


def read(f):
    return open(f, encoding='utf-8', errors='replace').read()


def exports_in(root):
    out = {}
    for f in glob.glob(os.path.join(root, '**', '*.lua'), recursive=True):
        name = os.path.relpath(f, root)[:-4].replace(os.sep, '_').replace('/', '_')
        src = read(f)
        out[name] = (set(EXPORT_RX.findall(src)), OPAQUE_RX.search(src) is not None, os.path.relpath(f, GAME))
    return out


def main():
    ge = exports_in(os.path.join(GAME, 'ge', 'extensions'))
    ge.update(exports_in(os.path.join(GAME, 'common', 'extensions')))
    veh = exports_in(os.path.join(GAME, 'vehicle'))
    problems = []
    for mod in MODS:
        for f in glob.glob(os.path.join(mod, '**', '*.lua'), recursive=True):
            if os.sep + 'build' + os.sep in f or os.sep + 'node_modules' + os.sep in f:
                continue
            src = re.sub(r'--\[\[.*?\]\]', ' ', read(f), flags=re.S)
            src = re.sub(r'--[^\n]*', '', src)
            table = veh if os.sep + 'vehicle' + os.sep in f else ge
            seen = set()
            for m in re.finditer(r'(?<![.:\w])([A-Za-z_]\w*)\.(\w+)', src):
                g, fld = m.groups()
                if g not in table or (g, fld) in seen:
                    continue
                seen.add((g, fld))
                ex, opaque, path = table[g]
                if fld in ex or opaque:
                    continue
                line = src.count('\n', 0, m.start()) + 1
                problems.append('%s:%d: %s.%s is not exported by %s' % (os.path.relpath(f, DEV), line, g, fld, path))
    for p in problems:
        print(p)
    if problems:
        print('fieldcheck: %d problems' % len(problems))
        sys.exit(1)
    print('fieldcheck ok')


if __name__ == '__main__':
    main()
