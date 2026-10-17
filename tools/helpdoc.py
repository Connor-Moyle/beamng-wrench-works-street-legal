"""Makes docs/PLAYER_GUIDE.md from the in-game help (mod/lua/ge/extensions/sl/core/help.lua), so the guide and the phone's Help never differ.

    python tools/helpdoc.py            write docs/PLAYER_GUIDE.md
    python tools/helpdoc.py --check    exit 1 when the file is not what the help says (the offline suite runs this)
Needs lupa (pip install lupa).
"""
import os
import sys

HERE = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
HELP = os.path.join(HERE, 'mod', 'lua', 'ge', 'extensions', 'sl', 'core', 'help.lua')
OUT = os.path.join(HERE, 'docs', 'PLAYER_GUIDE.md')


def render():
    from lupa.luajit21 import LuaRuntime
    lua = LuaRuntime()
    with open(HELP, encoding='utf-8') as f:
        module = lua.execute(f.read())
    return str(module.markdown()) + '\n'


def main():
    text = render()
    if '--check' in sys.argv:
        have = open(OUT, encoding='utf-8', newline='').read().replace('\r\n', '\n') if os.path.isfile(OUT) else ''
        if have != text:
            print('docs/PLAYER_GUIDE.md is out of date: run python tools/helpdoc.py')
            return 1
        print('PLAYER_GUIDE.md is up to date')
        return 0
    os.makedirs(os.path.dirname(OUT), exist_ok=True)
    with open(OUT, 'w', encoding='utf-8', newline='\n') as f:
        f.write(text)
    print('wrote ' + OUT)
    return 0


if __name__ == '__main__':
    sys.exit(main())
