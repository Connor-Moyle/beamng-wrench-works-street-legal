-- Wrench Works: Street Legal: the Mods menu page for the rivals and the car auctions (extension name: sl_storymenu; docs/MODS_MENU.md on Wrench Works' branch mods-menu)
-- Registers with slrr_settings (Wrench Works) when it is there; the values are in /settings/street_legal/tuning.json, read by sl/tuning. All settings live in
-- that menu only: nothing of this is on the phone or the laptop.

local M = {}

local FILE = '/settings/street_legal/tuning.json'

local function json(path) return { kind = 'json', file = FILE, path = path } end

function M.schema()
  return {
    mod = 'street_legal_story', title = 'Street Legal: rivals and car auctions', icon = 'wrench', order = 22,
    tabs = {
      { id = 'rivals', title = 'Rivals', description = 'The named racers who text you, challenge you and stand between you and the next tier.' },
      { id = 'ladder', title = 'The climb', description = 'How fast the tiers and the stakes rise.' },
      { id = 'auctions', title = 'Car auctions', description = 'The online auction on the phone and laptop, and the live auction at the junkyard.' },
    },
    fields = {
      { id = 'enabled', tab = 'rivals', group = 'Rivals', type = 'bool', label = 'Named rivals',
        tooltip = 'Six racers with names, personalities and cars who text you and challenge you. Off: no rival texts and no tier gate; the street races work as they did before.',
        default = true, store = json('rivals.enabled'), apply = 'live' },
      { id = 'escalateChance', tab = 'rivals', group = 'How often', type = 'slider', min = 0, max = 1, step = 0.05, scale = 100, unit = '%', label = 'Bigger bet offers',
        tooltip = 'The chance each night that a rival you have raced a few times offers a higher stake. Lower means fewer offers.',
        default = 0.35, store = json('rivals.escalateChance'), apply = 'live' },
      { id = 'tauntChance', tab = 'rivals', group = 'How often', type = 'slider', min = 0, max = 1, step = 0.05, scale = 100, unit = '%', label = 'Taunts and words of respect',
        tooltip = 'The chance each night of a text from a rival you have raced, when nothing else is due. At zero they only write about the races.',
        default = 0.3, store = json('rivals.tauntChance'), apply = 'live' },
      { id = 'reactionChance', tab = 'rivals', group = 'How often', type = 'slider', min = 0, max = 1, step = 0.05, scale = 100, unit = '%', label = 'Texts after a race',
        tooltip = 'The chance a rival texts you after you race them. At zero they stay quiet after races.',
        default = 0.7, store = json('rivals.reactionChance'), apply = 'live' },
      { id = 'offerDays', tab = 'rivals', group = 'Pink slips', type = 'int', min = 1, max = 10, label = 'Days a pink slip offer stays open',
        tooltip = 'A rival who offers pink slips waits this many days for your answer. Nothing happens to your car unless you accept.',
        default = 3, store = json('rivals.offerDays'), apply = 'live' },
      { id = 'note', tab = 'rivals', type = 'note',
        label = 'A rival never puts your car at risk by himself: a pink slip race is only an offer on his card in Street cred, and you can race for money instead or walk away.' },
      { id = 'bossWins', tab = 'ladder', group = 'Bosses', type = 'int', min = 1, max = 8, label = 'Wins before a boss calls you out',
        tooltip = 'How many races you must win at a tier (or above) before its boss asks for you. Higher means a longer climb.',
        default = 3, store = json('rivals.bossWins'), apply = 'live', advanced = true },
      { id = 'bossCooldown', tab = 'ladder', group = 'Bosses', type = 'int', min = 0, max = 10, label = 'Days a boss waits after beating you',
        tooltip = 'After you lose a boss showdown he will not ask again for this many days.',
        default = 3, store = json('rivals.bossCooldown'), apply = 'live', advanced = true },
      { id = 'stepRaces', tab = 'ladder', group = 'Stakes', type = 'int', min = 1, max = 8, label = 'Races before a rival raises the stake',
        tooltip = 'Each time you have raced a rival this many times, his bet steps up: pocket money, his top bet, high stakes.',
        default = 3, store = json('rivals.stepRaces'), apply = 'live' },
      { id = 'upgradeDays', tab = 'ladder', group = 'Their cars', type = 'int', min = 2, max = 15, label = 'Days between rival car upgrades',
        tooltip = 'Rivals improve their cars with the days, and after you beat them. Lower means they get quicker sooner.',
        default = 5, store = json('rivals.upgradeDays'), apply = 'live' },
      { id = 'lots', tab = 'auctions', group = 'Online auction', type = 'int', min = 3, max = 10, label = 'Lots on the online auction',
        tooltip = 'How many cars are up for auction on the phone and laptop at once.',
        default = 6, store = json('auctions.lots'), apply = 'live' },
      { id = 'weekday', tab = 'auctions', group = 'Junkyard auction', type = 'int', min = 0, max = 6, label = 'Auction day (day number modulo 7)',
        tooltip = 'The live auction at the junkyard happens on every seventh day. This picks which day of the seven.',
        default = 5, store = json('auctions.weekday'), apply = 'live', advanced = true },
      { id = 'fromHour', tab = 'auctions', group = 'Junkyard auction', type = 'int', min = 6, max = 18, label = 'Opens at (hour)',
        tooltip = 'The hour the junkyard auction opens.', default = 10, store = json('auctions.fromHour'), apply = 'live' },
      { id = 'toHour', tab = 'auctions', group = 'Junkyard auction', type = 'int', min = 8, max = 20, label = 'Closes at (hour)',
        tooltip = 'The hour the junkyard auction ends. Lots still running finish.', default = 13, store = json('auctions.toHour'), apply = 'live' },
      { id = 'yardLots', tab = 'auctions', group = 'Junkyard auction', type = 'int', min = 3, max = 8, label = 'Cars in the yard',
        tooltip = 'How many cars stand in the junkyard bays on auction day.', default = 6, store = json('auctions.yardLots'), apply = 'live' },
      { id = 'liveSeconds', tab = 'auctions', group = 'Junkyard auction', type = 'slider', min = 30, max = 180, step = 5, unit = 's', label = 'Time on each lot',
        tooltip = 'How long a lot is open at the live auction. A bid in the last seconds adds a few more.',
        default = 75, store = json('auctions.liveSeconds'), apply = 'live' },
    },
  }
end

function M.onSlrrSettingsReady() if slrr_settings and slrr_settings.register then slrr_settings.register(M.schema()) end end
M.onExtensionLoaded = M.onSlrrSettingsReady      -- (does nothing if the registry is not loaded yet)

return M
