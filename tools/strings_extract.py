"""Moves the player-facing messages of the Lua modules into the strings table (#51). Run once per batch; safe to run again (it finds nothing new).

    python tools/strings_extract.py            do it
    python tools/strings_extract.py --dry      only count

What it moves (the cases where the text is the whole argument, so nothing else in the line can change):
    return false, 'text'      return true, 'text'      tell('text')      toast('text')      sl_career.sendText(who, 'text'[, n])
The literal becomes strings.t('module.some_words') and the text goes into sl/core/strings.lua between the BEGIN/END extracted markers, under that key.
Needs lupa (the literal is read by LuaJIT, so every escape is the real one).
"""
import os
import re
import sys

HERE = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
EXT = os.path.join(HERE, 'mod', 'lua', 'ge', 'extensions', 'sl')
STRINGS = os.path.join(EXT, 'core', 'strings.lua')
BEGIN, END = '  -- BEGIN extracted (tools/strings_extract.py)', '  -- END extracted'
Q = chr(39)
LIT = Q + '((?:[^' + Q + chr(92) + chr(10) + ']|' + chr(92) + chr(92) + '.)+)' + Q
PATTERNS = [
    re.compile(r'(return\s+(?:true|false)\s*,\s*)' + LIT + r'(?=\s*(?:end\b|$|\)|;))'),
    re.compile(r'(\b(?:tell|toast)\(\s*)' + LIT + r'(?=\s*(?:\)|,))'),
    re.compile(r'(sl_career\.sendText\(\s*[^,()]+,\s*)' + LIT + r'(?=\s*(?:\)|,))'),
]


def lua_value(runtime, lit):
    return runtime.eval('(function() return ' + Q + lit + Q + ' end)()')


def slug(text, taken):
    words = re.findall(r'[a-z0-9]+', text.lower())[:5]
    base = '_'.join(words) or 'text'
    key, n = base, 2
    while key in taken:
        key, n = base + '_' + str(n), n + 1
    return key


def lua_quote(text):
    return '"' + text.replace(chr(92), chr(92) * 2).replace('"', chr(92) + '"').replace(chr(10), chr(92) + 'n') + '"'


def main():
    dry = '--dry' in sys.argv
    from lupa.luajit21 import LuaRuntime
    rt = LuaRuntime()
    s = open(STRINGS, encoding='utf-8', newline='').read()
    nl = '\r\n' if '\r\n' in s else '\n'
    if BEGIN not in s:
        s = s.replace("}" + nl + nl + "-- the Text size setting", BEGIN + nl + END + nl + "}" + nl + nl + "-- the Text size setting", 1)
    i, j = s.index(BEGIN), s.index(END)
    existing = {}
    for m in re.finditer(r'\["([^"]+)"\] = (".*?(?<!\\)"),', s[i:j]):
        existing[m.group(1)] = m.group(2)
    keys_by_text = {}
    for k, q in existing.items():
        keys_by_text[rt.eval(q)] = k
    taken = set(existing) | set(re.findall(r"\['([^']+)'\]", s))
    new_entries = {}
    changed_files = 0
    moved = 0
    for folder, _, names in os.walk(EXT):
        for name in sorted(names):
            if not name.endswith('.lua') or os.path.join(folder, name) == STRINGS:
                continue
            path = os.path.join(folder, name)
            src = open(path, encoding='utf-8', newline='').read()
            module = os.path.splitext(name)[0]
            count = 0

            def repl(m):
                nonlocal count, moved
                lit = m.group(2)
                text = lua_value(rt, lit)
                if ' ' not in text or len(re.findall('[A-Za-z]', text)) < 6 or '{' in text:
                    return m.group(0)
                key = keys_by_text.get(text)
                if not key:
                    key = module + '.' + slug(text, taken | set(new_entries))
                    keys_by_text[text] = key
                    new_entries[key] = text
                count += 1
                moved += 1
                return m.group(1) + "strings.t('" + key + "')"

            out = src
            for pat in PATTERNS:
                out = pat.sub(repl, out)
            if count and not dry:
                if "require('sl/core/strings')" not in out:
                    anchor = re.search(r"^local M = \{\}[^\n]*\n", out, re.M)
                    if not anchor:
                        print('no "local M = {}" in ' + name + ': skipped')
                        moved -= count
                        continue
                    out = out[:anchor.end()] + "\nlocal strings = require('sl/core/strings')\n" + out[anchor.end():]
                open(path, 'w', encoding='utf-8', newline='').write(out)
            if count:
                changed_files += 1
                print('%-22s %3d texts' % (name, count))
    if dry:
        print('dry run: %d texts in %d files' % (moved, changed_files))
        return 0
    block = ''.join('  [' + lua_quote(k) + '] = ' + lua_quote(v) + ',' + nl for k, v in sorted(new_entries.items()))
    s = s[:j] + block + s[j:]
    open(STRINGS, 'w', encoding='utf-8', newline='').write(s)
    print('%d texts moved from %d files, %d new keys' % (moved, changed_files, len(new_entries)))
    return 0


if __name__ == '__main__':
    sys.exit(main())
