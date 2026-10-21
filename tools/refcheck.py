"""Offline check that the mods' Lua only refers to things that exist: every global a game-engine (GE) or
vehicle file reads must be defined by the game, by one of our mods or by the file itself (or be read behind
a guard); a call into another mod must be to something it exports (or be guarded); every hook handler
(M.onXxx) must have something that fires it; every settings key read must be one of the defs.
Run: python tools/refcheck.py [repo ...]   (default: this repo and Wrench Works)
Needs lupa (LuaJIT): pip install lupa. Prints the findings and 'refcheck ok', or exits 1."""
import os, re, sys, glob
from lupa.luajit21 import LuaRuntime

HERE = os.path.dirname(os.path.abspath(__file__))
SL = os.path.dirname(HERE)
DEV = os.path.dirname(SL)
GAME = os.environ.get('BEAMNG_LUA', r'I:\SteamLibrary\steamapps\common\BeamNG.drive\lua')
MODS = [SL] + [os.path.join(DEV, d) for d in ('Beam NG SLRR MOD', 'SLRR map for beam ng', 'SLRR Drivers', 'Enhanced Skid Marks')]
CHECKED = sys.argv[1:] or [SL, os.path.join(DEV, 'Beam NG SLRR MOD')]

# globals the C++ side binds (no Lua definition to find)
C_GLOBALS = set('''be scenetree Engine FS TorqueScript TorqueScriptLua Lua obj v jit ffi bit
vec3 quat Point2F Point3F ColorF ColorI MatrixF QuatF castRayStatic castRay castRayDebug
getPlayerVehicle getObjectByID getPlayerVehicleID getGameState getLevelName getMissionFilename
log dump dumps print setExtensionUnloadMode getCurrentLevelIdentifier getRootPath getUserPath
Sim BeamEngine Vehicle TSStatic ScriptObject debugDrawer getTime nop'''.split())
# hooks the engine (C++) fires, with no Lua caller to grep for
C_HOOKS = set('''onUpdate onPreRender onDrawDebug onExtensionLoaded onExtensionUnloaded onInit onPhysicsStep
onVehicleSpawned onVehicleDestroyed onVehicleSwitched onVehicleResetted onVehicleActiveChanged onVehicleGroupSpawned
onClientPreStartMission onClientStartMission onClientPostStartMission onClientEndMission onMissionLoaded
onFirstUpdate onFileChanged onFilesChanged onSerialize onDeserialized onSettingsChanged onAnyMissionChanged
onWorldReadyState onCouplerAttached onCouplerDetached onBeamBroke onBeamDeformed onAiModeChange
onVehicleSubmitInfo onGuiUpdate onEditorActivated onEditorDeactivated onFreeroamMissionStarted
onSpawnCCallback onUiChangedState onResetGameplay onPauseChanged onCameraModeChanged
onVehicleJbeamLoaded onPlayersChanged onMouseLocked onScreenshot onKeyPressed'''.split())
# handlers for hooks a partner mod will fire once its feature lands (dead until then)
PENDING_HOOKS = {'onSlrrMeetTheme'}  # Drivers & Pedestrians' themed meets (X54, connor-51, not started)
LUA_STD = set('''assert collectgarbage dofile error getmetatable ipairs load loadfile loadstring next pairs pcall
print rawequal rawget rawlen rawset require select setmetatable tonumber tostring type unpack xpcall _G _VERSION
coroutine debug io math os package string table bit jit ffi newproxy gcinfo module'''.split())

WALK = r'''
local ju = require("jit.util")
return function(src, name)
  local f, err = loadstring(src, "=" .. name)
  if not f then return nil, err end
  local gets, sets = {}, {}
  local function walk(fn)
    local info = ju.funcinfo(fn)
    for pc = 0, info.bytecodes - 1 do
      local ins = ju.funcbc(fn, pc)
      local op = ins % 256
      local d = math.floor(ins / 65536)
      if op == 54 or op == 55 then
        local t = op == 54 and gets or sets
        t[#t + 1] = { ju.funck(fn, -d - 1), ju.funcinfo(fn, pc).currentline }
      end
    end
    local i = -1
    while true do
      local k = ju.funck(fn, i)
      if k == nil then break end
      if type(k) == "proto" then walk(k) end
      i = i - 1
    end
  end
  walk(f)
  return gets, sets
end
'''


def lua_files(root):
    return sorted(glob.glob(os.path.join(root, '**', '*.lua'), recursive=True))


def read(f):
    try:
        return open(f, encoding='utf-8', errors='replace').read()
    except OSError:
        return ''


def ext_name(path, extdir):
    return os.path.relpath(path, extdir).replace('\\', '/')[:-4].replace('/', '_')


def line_of(src, pos):
    return src.count('\n', 0, pos) + 1


DEF_RX = re.compile(r'^(?:function\s+([A-Za-z_]\w*)\s*[(.:]|([A-Za-z_]\w*)\s*=[^=]|_G\.([A-Za-z_]\w*)\s*=|_G\[["\']([A-Za-z_]\w*)["\']\]\s*=)', re.M)
HOOK_RX = re.compile(r'''(?:hook|hookNotify|hookUpdate|hookExcept|hookExceptNotify)\s*\(\s*["']([A-Za-z_]\w*)["']''')
HANDLER_RX = re.compile(r'^(?:function\s+M\.|M\.)(on[A-Z]\w*)\s*[=(]', re.M)
EXPORT_RX = re.compile(r'^\s*(?:function\s+M\.|M\.)(\w+)\s*[=(]', re.M)


def defined_in(sources):
    """names a set of Lua sources define at the top level (function x(, x = , _G.x =, x = require)"""
    names = set()
    for src in sources:
        for m in DEF_RX.finditer(src):
            names.add(next(g for g in m.groups() if g))
        names.update(re.findall(r'rawset\s*\(\s*_G\s*,\s*["\']([A-Za-z_]\w*)', src))
        names.update(re.findall(r'^\s*([A-Za-z_]\w*)\s*=\s*require\s*[("]', src, re.M))  # vehicle/main.lua's modules
    return names


def guarded(src, expr):
    """the expression is read behind a check somewhere in the file: if X / X and / not X / X ~= nil / type(X)"""
    e = re.escape(expr)
    return re.search(r'(?:\bif\s+|\band\s+|\bnot\s+)%s\b|\b%s\s*(?:and\b|then\b|[~=]=)|type\(%s\)' % (e, e, e), src) is not None


def main():
    walker = LuaRuntime().execute(WALK)
    game = {sub: {f: read(f) for f in lua_files(os.path.join(GAME, sub))} for sub in ('ge', 'vehicle', 'common')}
    known = {'ge': defined_in(game['ge'].values()) | defined_in(game['common'].values()),
             'vehicle': defined_in(game['vehicle'].values()) | defined_in(game['common'].values())}
    game_used = {}
    for sub in known:
        known[sub] |= C_GLOBALS | LUA_STD
        for d in (os.path.join(GAME, sub, 'extensions'), os.path.join(GAME, 'common', 'extensions')):
            known[sub] |= {ext_name(f, d) for f in lua_files(d)}
        game_used[sub] = set()
        for src in list(game[sub].values()) + list(game['common'].values()):
            game_used[sub].update(re.findall(r'(?<![.:\w])([A-Za-z_]\w*)\s*[(.:]', src))
    mod_src, exports = {}, {}
    for mod in MODS:
        for sub in known:
            for extdir in glob.glob(os.path.join(mod, '*', 'lua', sub, 'extensions')) + glob.glob(os.path.join(mod, 'lua', sub, 'extensions')):
                for f in lua_files(extdir):
                    known[sub].add(ext_name(f, extdir))
                    exports[ext_name(f, extdir)] = set(EXPORT_RX.findall(read(f)))
        for f in lua_files(mod):
            mod_src[f] = read(f)
    # hooks: fired by the game's Lua, by any of our mods (also as a name in a string or a direct call), or by C++
    fired = set(C_HOOKS)
    for src in list(game['ge'].values()) + list(game['vehicle'].values()) + list(game['common'].values()) + list(mod_src.values()):
        fired.update(HOOK_RX.findall(src))
        fired.update(re.findall(r'''["'](on[A-Z]\w*)["']''', src))
        fired.update(re.findall(r'\.(on[A-Z]\w*)\s*\(', src))
    problems = []
    for repo in CHECKED:
        for sub in known:
            dirs = glob.glob(os.path.join(repo, '*', 'lua', sub, 'extensions'))
            if sub == 'ge':
                dirs += glob.glob(os.path.join(repo, '*', 'scripts'))
            for d in dirs:
                for f in lua_files(d):
                    src = read(f)
                    rel = os.path.relpath(f, repo)
                    me = ext_name(f, d)
                    gets, sets = walker(src, os.path.basename(f))
                    if gets is None:
                        problems.append('%s: does not compile: %s' % (rel, sets))
                        continue
                    own = {sets[i][1] for i in range(1, len(sets) + 1)}
                    seen = set()
                    for i in range(1, len(gets) + 1):
                        name, line = gets[i][1], gets[i][2]
                        if name in known[sub] or name in own or name in seen:
                            continue
                        seen.add(name)
                        if guarded(src, name):
                            continue  # another mod's global, read behind a guard
                        if name in game_used[sub]:
                            continue  # the game's own Lua uses it: bound by C++
                        problems.append('%s:%d: global %r is not defined by the game or any mod' % (rel, line, name))
                    # a call into another mod must be to something it exports, unless the call checks for it first
                    for m in re.finditer(r'\b(s(?:l|lrr)\w*)\.(\w+)', re.sub(r'--[^\n]*', lambda c: ' ' * len(c.group()), src)):
                        ext, field = m.groups()
                        if ext not in exports or ext == me or field in exports[ext] or (ext, field) in seen:
                            continue
                        seen.add((ext, field))
                        if guarded(src, '%s.%s' % (ext, field)):
                            continue
                        problems.append('%s:%d: %s.%s: %s does not export it' % (rel, line_of(src, m.start()), ext, field, ext))
                    for m in HANDLER_RX.finditer(src):
                        if m.group(1) not in fired and m.group(1) not in PENDING_HOOKS:
                            problems.append('%s:%d: handler %s: nothing fires that hook' % (rel, line_of(src, m.start()), m.group(1)))
        # the UI pages (phone, dashboard, garage) call Lua functions the extensions must export
        for f in glob.glob(os.path.join(repo, 'mod', 'ui', '**', '*.js'), recursive=True) + glob.glob(os.path.join(repo, 'mod', 'ui', '**', '*.html'), recursive=True):
            src = read(f)
            seen = set()
            for m in re.finditer(r'\b(s(?:l|lrr)_\w+)\.(\w+)\s*\(', src):
                ext, field = m.groups()
                if ext in exports and field not in exports[ext] and (ext, field) not in seen:
                    seen.add((ext, field))
                    problems.append('%s:%d: %s.%s: %s does not export it' % (os.path.relpath(f, repo), line_of(src, m.start()), ext, field, ext))
        # a car command that calls back into a game extension must guard it ("if sl_hud then sl_hud.f() end"): the extension may be off or failed to load
        for f in lua_files(os.path.join(repo, 'mod')):
            src = read(f)
            for m in re.finditer(r'''queueGameEngineLua\(\s*(?:string\.format\(\s*)?["'](?:sl_\w+|slrr_\w+|carSurfaceFx\w*)\.''', src):
                problems.append('%s:%d: queueGameEngineLua calls an extension without "if ext then"' % (os.path.relpath(f, repo), line_of(src, m.start())))
        # settings keys read must be defined (sl_options in Street Legal, slrr/garageSettings in Wrench Works)
        for opt, getter in ((os.path.join(repo, 'mod', 'lua', 'ge', 'extensions', 'sl', 'options.lua'), r'sl_options\.get'),
                            (os.path.join(repo, 'mod', 'lua', 'ge', 'extensions', 'slrr', 'garageSettings.lua'), r'\bsettings\.get')):
            if not os.path.exists(opt):
                continue
            defs = set(re.findall(r"key\s*=\s*'(\w+)'", read(opt)))
            for f in lua_files(os.path.join(repo, 'mod')):
                src = read(f)
                for m in re.finditer(getter + r'''\(\s*["'](\w+)["']''', src):
                    if m.group(1) not in defs:
                        problems.append('%s:%d: %s: no such setting' % (os.path.relpath(f, repo), line_of(src, m.start()), m.group(0)))
    for p in problems:
        print(p)
    if problems:
        print('refcheck: %d problems' % len(problems))
        sys.exit(1)
    print('refcheck ok')


if __name__ == '__main__':
    main()
