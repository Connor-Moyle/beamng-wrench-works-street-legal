-- Street Legal: hill duels (extension name: sl_hillduel; the Hill duels part: Mods > Street Legal > Parts of the game > Hill duels).
-- Rules in sl/core/hillduel. At night the three hill roads carry a marker at their start; the game's prompt there offers a duel against a
-- rival of the player's standing for a bet; the duel runs on the grid runner (sl_gridrace: the rival's own car on the grid next to the player,
-- the countdown, the road) and is scored by points (lead and chase) while it runs; the result pays the bet and the reputation.

local M = {}

local rules = require('sl/core/hillduel')
local gridRules = require('sl/core/gridrace')
local strings = require('sl/core/strings')
local features = require('sl/core/features')
local stateLib = require('sl/core/state')
local roster = require('sl/core/roster')
local rngLib = require('sl/core/rng')

local function career() return sl_career and sl_career.isActive() and sl_career.getState() or nil end
local function night() return sl_career and sl_career.isNight and sl_career.isNight() == true end
local function toast(text) guihooks.trigger('slPhoneToast', { text = text }) end
local function home() return sl_career.LEVEL == 'west_coast_usa' end

-- the roads' starts, read once per level from the race files
local starts, startsLevel = {}, nil
local function startOf(road)
  if startsLevel ~= sl_career.LEVEL then starts, startsLevel = {}, sl_career.LEVEL end
  if starts[road.id] == nil then
    local ok, data = pcall(jsonReadFile, gridRules.roundDir(road.track) .. 'race.race.json')
    starts[road.id] = ok and rules.startOf(data) or false
  end
  return starts[road.id] or nil
end

-- the rival and the bet of a road tonight (the same for the night)
local function offerFor(s, road)
  local rng = rngLib.new(rngLib.hash('duel:' .. road.id .. ':' .. s.day .. ':' .. tostring(s.seed)))
  local r = rules.rival(s.racers, s.rep, rng)
  return r, r and rules.bet(r) or 0
end

-- ---- the pins and the prompt
local function pins(level, elements)
  local s = career()
  if not s or not night() or not home() or level ~= sl_career.LEVEL then return end
  for _, road in ipairs(rules.ROADS) do
    local p = startOf(road)
    if p then
      local pos = vec3(p.x, p.y, p.z)
      elements[#elements + 1] = {
        id = 'slDuel:' .. road.id, data = { type = 'other', id = 'slDuel:' .. road.id, duelRoad = road.id, name = strings.t('hillduel.hill_duel_1', road.title), date = 0 },
        clusterType = 'missionMarker', clusterInBigMap = true, clusterInPlayMode = true, interactableInPlayMode = true, quickTravelAvailable = false,
        markerInfo = {
          missionMarker = { pos = pos, rot = quat(0, 0, 0, 1), icon = 'mission_arrival_triangle' },
          bigmapMarker = { pos = pos, icon = 'mission_arrival_triangle', name = strings.t('hillduel.hill_duel_1', road.title), description = strings.t('hillduel.pin_desc') },
        },
      }
    end
  end
end
function M.onGetRawPoiListForLevel(level, elements)
  local ok, err = pcall(pins, level, elements)
  if not ok then log('E', 'sl_hillduel', 'pins: ' .. tostring(err)) end
end
local function refreshPins() if gameplay_rawPois and gameplay_rawPois.clear then gameplay_rawPois.clear() end end
function M.onStreetLegalPhase() refreshPins() end
function M.onStreetLegalStarted() refreshPins() end

local function prompt(elemData, activityData)
  local s = career()
  if not s or not night() then return end
  for _, elem in ipairs(elemData or {}) do
    local road = type(elem.duelRoad) == 'string' and rules.road(elem.duelRoad)
    if road then
      local r, bet = offerFor(s, road)
      if r then
        table.insert(activityData, {
          icon = 'poi_arrival_round', heading = strings.t('hillduel.hill_duel_1', road.title), preheadings = { strings.t('hillduel.hill_duel') },
          sorting = { type = 'slDuel', id = road.id },
          buttonLabel = strings.t('hillduel.duel_against_1_for_2', roster.displayName(r), bet),
          buttonFun = function() local ok, text = M.start(road.id) if not ok and text then toast(text) end end,
          buttonSoundClass = 'bng_hover_generic',
        })
      end
    end
  end
end

function M.onActivityAcceptGatherData(elemData, activityData)
  local ok, err = pcall(prompt, elemData, activityData)
  if not ok then log('E', 'sl_hillduel', 'prompt: ' .. tostring(err)) end
end

-- ---- the duel
local duel = nil        -- { road, rival, bet, score, said, started }

local function tick(ctx, dt)
  local d = duel
  if not d or not ctx or not ctx.race or not ctx.race.states then return end
  local me = ctx.race.states[ctx.playerId]
  local themId = ctx.ais and ctx.ais[1] and ctx.ais[1].id
  local them = themId and ctx.race.states[themId]
  if not me or not them then return end
  d.started = true
  local ahead = nil
  if me.placement and them.placement and me.placement ~= them.placement then ahead = me.placement < them.placement and 'me' or 'them' end
  local pm, pt = ctx.race:getVehiclePosition(ctx.playerId), ctx.race:getVehiclePosition(themId)
  local gap = pm and pt and (pm - pt):length() or 0
  rules.tick(d.score, ahead, gap, me.isOnRoad ~= false, them.isOnRoad ~= false, dt)
  if d.score.t - (d.said or 0) >= 5 then d.said = d.score.t if ui_message then ui_message(rules.text(d.score), 4, 'streetLegal') end end
end

local function finished(res)
  local d = duel
  duel = nil
  local s = career()
  if not d or not s then return end
  if res.aborted then
    -- called off before the start (the rival did not build, the fade failed): nothing; after the start (leaving the car, a switch): the bet is lost, a duel is not walked out of
    if d.started then
      local lost = math.min(d.bet, math.max(0, s.money or 0))
      if lost > 0 then sl_career.addMoney(-lost, strings.t('hillduel.hill_duel')) end
      toast(strings.t('hillduel.walked_out_1', lost))
    else
      toast(strings.t('hillduel.called_off'))
    end
    extensions.hook('onStreetLegalChanged')
    return
  end
  local won = rules.winner(d.score, res.place) == 'me'
  local money, rep = rules.payout(won, d.bet)
  if money < 0 then money = -math.min(d.bet, math.max(0, s.money or 0)) end      -- (a loss is floored by the wallet)
  if money > 0 then sl_career.payOut(money, strings.t('hillduel.hill_duel')) elseif money < 0 then sl_career.addMoney(money, strings.t('hillduel.hill_duel')) end
  stateLib.addRep(s, rep)
  if sl_career.afterRace then pcall(sl_career.afterRace, d.rival.id, won, math.abs(d.score.me - d.score.them)) end
  extensions.hook('onStreetLegalHillDuelResult', d.road.id, won, { me = d.score.me, them = d.score.them })      -- (the season's duel round)
  toast(won and strings.t('hillduel.you_won_1_2_3', rules.text(d.score), d.bet, rep) or strings.t('hillduel.you_lost_1_2', rules.text(d.score), d.bet))
  extensions.hook('onStreetLegalChanged')
end

function M.start(roadId)
  local s = career()
  if not s then return false, strings.t('needs.no_career') end
  if not night() then return false, strings.t('hillduel.at_night') end
  if duel or not (sl_gridrace and sl_gridrace.start) or sl_gridrace.running() then return false, strings.t('career.not_now') end
  if sl_career.freeToStart and sl_career.freeToStart() then return false, sl_career.freeToStart() end
  local road = rules.road(roadId)
  if not road then return false, strings.t('hillduel.no_such_road') end
  local r, bet = offerFor(s, road)
  if not r then return false, strings.t('clubs.nobody_to_race') end
  if s.money < bet then return false, strings.t('carcare.it_is_d_you_have', bet, s.money) end
  duel = { road = road, rival = r, bet = bet, score = rules.newScore(), said = 0 }
  local ok, text = sl_gridrace.start({ dir = gridRules.roundDir(road.track), name = road.title, laps = road.laps, rival = r.id, grid = 1, onTick = tick }, finished)
  if not ok then duel = nil return false, text end
  if ui_message then ui_message(strings.t('hillduel.duel_1_against_2_3', road.title, roster.displayName(r), bet), 6, 'streetLegal') end
  return true, text
end

function M.onStreetLegalStopped() duel = nil starts, startsLevel = {}, nil end
function M.onClientEndMission() duel = nil starts, startsLevel = {}, nil end
function M.status() if not duel then return 'no duel' end return duel.road.title .. ' against ' .. roster.displayName(duel.rival) .. ': ' .. rules.text(duel.score) end
-- for the tester: a duel now (night only), the road by id: cell, alley, mountain
function M.debugStart(roadId) local ok, text = M.start(roadId or 'cell') return tostring(ok) .. ' ' .. tostring(text) end

features.gate('hillduel', M, nil, nil, { 'start' })      -- (the part off: no pins, no prompt, no start)

return M
