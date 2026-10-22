-- Wrench Works: Street Legal: the numbers a player may tune, read from sl_options (the Mods menu, ESC > Mods, shows the entries with a `tab`)
-- `get('rivals.escalateChance', 0.35)`: the path names the setting, the default is what the module was written with (used when sl_options is not there).

local M = {}

local KEYS = {
  ['rivals.enabled'] = 'slRivals', ['rivals.escalateChance'] = 'slRivalEscalate', ['rivals.tauntChance'] = 'slRivalTaunt', ['rivals.reactionChance'] = 'slRivalReactions',
  ['rivals.offerDays'] = 'slRivalOfferDays', ['rivals.bossWins'] = 'slBossWins', ['rivals.bossCooldown'] = 'slBossCooldown', ['rivals.stepRaces'] = 'slRivalStepRaces',
  ['rivals.upgradeDays'] = 'slRivalUpgradeDays', ['rivals.rapSheet'] = 'slRapSheet', ['auctions.lots'] = 'slAuctionLots', ['auctions.weekday'] = 'slAuctionDay', ['auctions.fromHour'] = 'slAuctionFrom',
  ['auctions.toHour'] = 'slAuctionTo', ['auctions.yardLots'] = 'slYardLots', ['auctions.liveSeconds'] = 'slAuctionLive',
}
M.KEYS = KEYS

function M.get(path, default)
  local key = KEYS[path]
  local v = key and sl_options and sl_options.get and sl_options.get(key)
  if v == nil then return default end
  if type(default) == 'number' then return tonumber(v) or default end
  if type(default) == 'boolean' then return v == true end
  return v
end

function M.refresh() end

return M
