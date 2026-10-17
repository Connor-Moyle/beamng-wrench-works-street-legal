-- Street Legal: the player-facing text, in one place (#51). Pure: no game calls (tested by tools/luatest.js).
-- Lua says  strings.t('phase.dayOver')  or  strings.t('wait.until', '19:00');  the UI gets this whole table once (sl_phone.requestStrings, event slStrings)
-- and says  T('app.races', 'Races')  (the second argument is only what shows before the table has arrived). {1}, {2} are filled from the extra arguments.
-- Keys are  area.name . A text that is not here yet is still in its module: tools/strings_audit.py counts those, so the move can be followed.
-- To translate or reword the career, change this file only.

local M = {}

M.TEXT = {
  -- the phone's apps and pages
  ['app.races'] = 'Races', ['app.garage'] = 'My cars', ['app.bank'] = 'Bank', ['app.me'] = 'Street cred', ['app.jobs'] = 'Jobs', ['app.wait'] = 'Wait',
  ['app.settings'] = 'Settings', ['app.help'] = 'Help', ['app.club'] = 'Club', ['app.turf'] = 'Turf', ['app.carmarket'] = 'Car market',
  ['app.partmarket'] = 'Part market', ['app.phone'] = 'Phone', ['app.messages'] = 'Messages', ['app.contacts'] = 'Contacts', ['app.cab'] = 'Cab',
  ['app.contact'] = 'Contact', ['app.ad'] = 'Ad', ['app.revline'] = 'Revline', ['app.bid'] = 'Swap & Bid',
  -- day and night
  ['phase.day'] = 'Day', ['phase.night'] = 'Night', ['phase.startNight'] = 'Start the night', ['phase.startDay'] = 'Start the day',
  ['phase.dayOver'] = 'The day is over. Start the night at a garage or in the Wait app.',
  ['phase.nightOver'] = 'The night is over. Start the day at a garage or in the Wait app.',
  ['phase.nightBegins'] = 'The night begins.', ['phase.newDay'] = 'A new day: day {1}.',
  ['wait.hour1'] = 'One hour', ['wait.hour3'] = 'Three hours', ['wait.hour6'] = 'Six hours',
  ['wait.until'] = 'You wait until {1}.', ['wait.dayEnds'] = ' The day is over.', ['wait.nightEnds'] = ' The night is over.',
  ['wait.stops'] = 'The clock stops at the end of the {1}. Waiting never goes past it; {2} to go on. Not in a race, on a job or with the police after you.',
  ['wait.endDay'] = 'day (19:00)', ['wait.endNight'] = 'night (04:00)',
  -- status words (shown with the colour, never by colour alone)
  ['status.ok'] = 'OK', ['status.warn'] = 'Damaged', ['status.bad'] = 'Wrecked', ['status.engine'] = 'ENGINE', ['status.tyre'] = 'Burst tyre',
  ['status.yours'] = 'Yours', ['status.start'] = 'start', ['status.finish'] = 'finish', ['status.ahead'] = 'ahead', ['status.behind'] = 'behind',
  ['hud.atRisk'] = '+{1} rep at risk', ['hud.heat'] = 'Heat {1}',
  -- laptop
  ['laptop.mycars'] = 'My cars', ['laptop.myparts'] = 'My parts', ['laptop.carmarket'] = 'Car market', ['laptop.partmarket'] = 'Part market',
  ['laptop.club'] = 'Club', ['laptop.help'] = 'Help', ['laptop.bank'] = 'Bank / insurance', ['laptop.cred'] = 'Street cred',
  ['laptop.partshop'] = 'Part customization', ['laptop.tuning'] = 'Tuning', ['laptop.painting'] = 'Painting', ['laptop.repair'] = 'Repair',
  -- settings
  ['settings.textSize'] = 'Text size',
  ['settings.textSizeDesc'] = 'How big the text is on the phone, the laptop and the HUD. On a pad the phone is never smaller than Large.',
  ['settings.textNormal'] = 'Normal', ['settings.textLarge'] = 'Large', ['settings.textHuge'] = 'Huge',
  -- BEGIN extracted (tools/strings_extract.py)
  ["activities.out_of_the_race_of"] = "Out of the Race of Champions. The entry fee is gone; enter again when you are ready.",
  ["activities.track_events_run_in_the"] = "Track events run in the day.",
  ["bank.hardcore_career_nobody_will_insure"] = "Hardcore career: nobody will insure you.",
  ["bank.insurance_cancelled"] = "Insurance cancelled.",
  ["bank.no_career_running"] = "No career running.",
  ["bank.nothing_to_pay_with"] = "Nothing to pay with.",
  ["bank.pay_off_the_loan_you"] = "Pay off the loan you have first.",
  ["bank.second_missed_payment_next_week"] = "Second missed payment. Next week the bank takes your car. Pay something now (phone, Bank).",
  ["bank.the_bank_says_your_loan"] = "The bank says your loan is paid off. Good.",
  ["bank.you_are_insured_already"] = "You are insured already.",
  ["bank.you_owe_the_bank_nothing"] = "You owe the bank nothing.",
  ["bank.your_insurance_lapsed_not_enough"] = "Your insurance lapsed: not enough for the premium.",
  ["cab.the_cab_got_tired_of"] = "The cab got tired of waiting. Your fare is back.",
  ["cab.your_cab_is_here_hazards"] = "Your cab is here, hazards on. Walk up to it.",
  ["carcare.go_to_the_car_first"] = "Go to the car first.",
  ["carcare.no_such_car"] = "No such car.",
  ["carcare.nothing_to_buy"] = "Nothing to buy.",
  ["carcare.that_car_is_not_here"] = "That car is not here.",
  ["carcare.the_trunk_is_full"] = "The trunk is full.",
  ["carcare.there_is_none_in_the"] = "There is none in the trunk.",
  ["career.a_cab_is_already_waiting"] = "A cab is already waiting for you.",
  ["career.cabs_are_for_people_on"] = "Cabs are for people on foot. Park the car and get out first.",
  ["career.not_enough_money"] = "Not enough money.",
  ["career.not_now"] = "Not now.",
  ["career.nothing_of_yours_is_impounded"] = "Nothing of yours is impounded.",
  ["career.nothing_to_raise"] = "Nothing to raise.",
  ["career.one_moment"] = "One moment.",
  ["career.that_race_is_not_on"] = "That race is not on.",
  ["career.that_race_is_off"] = "That race is off.",
  ["career.the_cab_does_not_know"] = "The cab does not know that place.",
  ["career.this_is_the_best_garage"] = "This is the best garage in town.",
  ["classifieds.close_the_lot_screen_you"] = "Close the lot screen you have open first.",
  ["classifieds.finish_the_job_you_are"] = "Finish the job you are on first.",
  ["classifieds.it_is_listed_already"] = "It is listed already.",
  ["classifieds.not_enough_for_the_deposit"] = "Not enough for the deposit.",
  ["classifieds.not_even_2"] = "Not even $2?",
  ["classifieds.not_while_you_are_in"] = "Not while you are in the garage.",
  ["classifieds.pick_up_a_copy_at"] = "Pick up a copy at any gas station.",
  ["classifieds.that_auction_is_over"] = "That auction is over.",
  ["classifieds.that_car_is_not_yours"] = "That car is not yours any more.",
  ["classifieds.that_listing_is_gone"] = "That listing is gone.",
  ["classifieds.that_offer_is_gone"] = "That offer is gone.",
  ["classifieds.that_part_is_not_on"] = "That part is not on your shelf.",
  ["classifieds.that_stall_has_sold_it"] = "That stall has sold it.",
  ["classifieds.there_are_bids_on_it"] = "There are bids on it: the auction runs to the end.",
  ["classifieds.wrench_works_is_not_running"] = "Wrench Works is not running.",
  ["classifieds.you_are_the_highest_bidder"] = "You are the highest bidder already.",
  ["classifieds.you_could_not_pay_that"] = "You could not pay that if you won.",
  ["classifieds.you_need_to_be_in"] = "You need to be in one of your cars to go and fetch it.",
  ["classifieds.you_need_wrench_works_running"] = "You need Wrench Works running to take it home.",
  ["clubs.bring_one_of_your_cars"] = "Bring one of your cars.",
  ["clubs.nobody_to_race"] = "Nobody to race.",
  ["clubs.nothing_on_in_that_league"] = "Nothing on in that league today.",
  ["clubs.the_night_league_races_after"] = "The night league races after dark.",
  ["clubs.you_have_done_that_one"] = "You have done that one today.",
  ["crews.the_crew_leaders_have_noticed"] = "The crew leaders have noticed you. They want a turf war: three nights, three races, one each on their own streets. Win them all and the city is yours.",
  ["crews.they_beat_you_the_crews"] = "They beat you. The crews are laughing. Give it a week and try again.",
  ["dealers.that_car_has_gone"] = "That car has gone.",
  ["drag.drag_strip_the_other_lane"] = "Drag strip: the other lane has no spawn, a practice run.",
  ["drag.nobody_showed_up_at_the"] = "Nobody showed up at the strip.",
  ["fleet.it_is_at_the_garage"] = "It is at the garage already.",
  ["fleet.it_is_in_the_police"] = "It is in the police impound.",
  ["fleet.swap_cars_at_your_garage"] = "Swap cars at your garage.",
  ["fleet.you_have_that_one_out"] = "You have that one out already.",
  ["fleet.your_garage_is_not_on"] = "Your garage is not on this map.",
  ["jobs.first_upgrade_on_the_car"] = "First upgrade on the car. Now we are getting somewhere. (The new-in-town favours stop here.)",
  ["jobs.job_dropped_word_gets_round"] = "Job dropped. Word gets round: -5 reputation.",
  ["jobs.not_in_the_middle_of"] = "Not in the middle of a race.",
  ["jobs.not_with_those_injuries_rest"] = "Not with those injuries. Rest up first.",
  ["jobs.that_job_has_gone"] = "That job has gone.",
  ["jobs.the_job_you_were_on"] = "The job you were on got called off while you were away. No harm done; the board has more.",
  ["jobs.you_are_not_on_a"] = "You are not on a job.",
  ["jobs.you_need_to_be_in"] = "You need to be in one of your cars.",
  ["lockdown.hardcore_nobody_pulls_you_out"] = "Hardcore: nobody pulls you out. Phone > My cars > Tow it home.",
  ["lockdown.on_foot_nothing_to_pull"] = "On foot: nothing to pull out.",
  ["lockdown.stop_first_then_call_for"] = "Stop first, then call for a pull back to the road.",
  ["races.nobody_showed_up"] = "Nobody showed up.",
  ["rally.bring_a_car"] = "Bring a car.",
  ["replay.could_not_save_the_clip"] = "Could not save the clip.",
  ["replay.no_race_recorded"] = "No race recorded.",
  ["replay.that_replay_is_gone"] = "That replay is gone.",
  ["replay.the_replay_would_not_open"] = "The replay would not open.",
  ["services.fresh_oil_in"] = "Fresh oil in.",
  ["services.the_engine_is_rebuilt_like"] = "The engine is rebuilt. Like new.",
  ["station.drive_your_car_up_to"] = "Drive your car up to wash it.",
  ["station.fill_what_drive_one_of"] = "Fill what? Drive one of your cars up to the pump.",
  ["station.that_will_not_buy_any"] = "That will not buy any fuel.",
  ["station.you_need_a_car_to"] = "You need a car to put it in.",
  ["streets.bring_your_own_car"] = "Bring your own car.",
  ["streets.bring_your_own_car_to"] = "Bring your own car to the ROC.",
  ["streets.not_here"] = "Not here.",
  ["streets.out_of_the_roc_the"] = "Out of the ROC. The entry fee is gone; come back when you are ready to pay it again.",
  ["streets.the_roc_is_for_the"] = "The ROC is for the top garage and the top names.",
  ["streets.to_the_roc"] = "To the ROC.",
  ["streets.you_are_the_champion_nobody"] = "You are the champion. Nobody is left to beat.",
  ["tutorial.fair_enough_you_know_your"] = "Fair enough, you know your way around. Call me if you need anything.",
  ["tutorial.no_easy_race_round_here"] = "No easy race round here right now. Any street race will do: look in the Races app.",
  ["upgrades.no_such_thing"] = "No such thing.",
  ["upgrades.the_garage_has_one_already"] = "The garage has one already.",
  -- END extracted
}

-- the Text size setting: the scale of the phone's, the laptop's and the HUD's text. normal 1, large 1.25, huge 1.5; anything else is normal.
M.SCALES = { normal = 1, large = 1.25, huge = 1.5 }
function M.textScale(id) return M.SCALES[id] or 1 end

-- the text for a key, with {1} {2}... filled from the extra arguments; the key itself when it is unknown (so a gap shows)
function M.t(key, ...)
  local s = M.TEXT[key]
  if s == nil then return tostring(key) end
  local args = { ... }
  return (s:gsub('{(%d+)}', function(n) local v = args[tonumber(n)] return v ~= nil and tostring(v) or '' end))
end

return M
