"""How much of the player-facing text is in the strings table yet (#51). A rough count, not a gate: it follows the move.

    python tools/strings_audit.py          per file: texts through the table (T(...)) and quoted texts still in the code
A "text" here is a quoted string of 12 or more characters with a space and letters, outside comments, that is not an HTML/CSS/selector fragment.
"""
import os
import re
import sys

HERE = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
FILES = [
    'mod/ui/modModules/slPhone/slPhone.js', 'mod/ui/modModules/slLaptop/slLaptop.js', 'mod/ui/modModules/slHud/slHud.js',
    'mod/lua/ge/extensions/sl/career.lua', 'mod/lua/ge/extensions/sl/phone.lua', 'mod/lua/ge/extensions/sl/police.lua', 'mod/lua/ge/extensions/sl/jobs.lua',
    'mod/lua/ge/extensions/sl/classifieds.lua', 'mod/lua/ge/extensions/sl/dealers.lua', 'mod/lua/ge/extensions/sl/crews.lua', 'mod/lua/ge/extensions/sl/clubs.lua',
]
LITERAL = re.compile(r"'((?:[^'\\n]|\.){12,})'")


def texts(path):
    n_table = n_code = 0
    with open(path, encoding='utf-8') as f:
        for line in f:
            code = re.sub(r'(--|//).*$', '', line) if not re.search(r"'[^']*(//|--)[^']*'", line) else line
            n_table += len(re.findall(r"\bT\('|strings\.t\('|\$scope\.t\('", code))
            for m in LITERAL.finditer(code):
                t = m.group(1)
                if ' ' in t and re.search('[A-Za-z]{3}', t) and not re.search(r'[<>{};=]|^[.#]|data-a|px|rgba?\(', t):
                    n_code += 1
    return n_table, n_code


def main():
    total_t = total_c = 0
    for rel in FILES:
        path = os.path.join(HERE, rel)
        if not os.path.isfile(path):
            continue
        t, c = texts(path)
        total_t, total_c = total_t + t, total_c + c
        print('%-52s table %4d   in the code %4d' % (rel, t, c))
    print('%-52s table %4d   in the code %4d   (%d%% moved)' % ('TOTAL', total_t, total_c, round(100 * total_t / max(1, total_t + total_c))))


if __name__ == '__main__':
    sys.exit(main() or 0)
