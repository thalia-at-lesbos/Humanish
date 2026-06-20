# Humanish — a turn-based 4X strategy game.
# Copyright (C) 2026 thalia-at-lesbos
# SPDX-License-Identifier: GPL-3.0-or-later
#
# This program is free software: you can redistribute it and/or modify it
# under the terms of the GNU General Public License as published by the Free
# Software Foundation, either version 3 of the License, or (at your option)
# any later version. See the LICENSE file for the full text and warranty
# disclaimer.

extends "res://tests/support/sim_fixture.gd"

# §9 wild-forces AI (provisional): scouts detect players and rouse camps, camps
# muster waves over several turns then cool down, mustered raiders march toward and
# attack players, wave strength scales with the leading player's tech, and all of
# it survives save/load and stays deterministic.

# A raider camp (owner -2) helper.
func _camp(gs, x, y):
	var s = make_settlement(gs, -2, x, y, 1)
	s.name = "Raider Camp"
	return s

# ── Detection / alerting ───────────────────────────────────────────────────────

func test_scout_sighting_a_player_rouses_nearest_camp() -> void:
	var gs = make_gs(2)
	var camp = _camp(gs, 10, 10)
	make_warrior(gs, -2, 10, 10, true)      # scout sitting on the camp
	make_warrior(gs, 1, 12, 10)             # a player unit, distance 2 (within sight)

	WildAI._detect_and_alert(gs, gs.rng)

	assert_true(camp.alert_turns > 0, "Camp should be roused by the sighting")
	assert_eq(camp.alert_target_x, 12, "Alert aims at the sighted player tile (x)")
	assert_eq(camp.alert_target_y, 10, "Alert aims at the sighted player tile (y)")

func test_no_player_in_sight_leaves_camp_idle() -> void:
	var gs = make_gs(2)
	var camp = _camp(gs, 10, 10)
	make_warrior(gs, -2, 10, 10, true)
	make_warrior(gs, 1, 0, 0)               # far outside the detection radius

	WildAI._detect_and_alert(gs, gs.rng)
	assert_eq(camp.alert_turns, 0, "An unseen player must not raise an alert")

func test_player_settlement_also_triggers_detection() -> void:
	var gs = make_gs(2)
	var camp = _camp(gs, 10, 10)
	make_warrior(gs, -2, 11, 10, true)
	make_settlement(gs, 1, 13, 10, 3)       # a player city within sight

	WildAI._detect_and_alert(gs, gs.rng)
	assert_true(camp.alert_turns > 0, "A player city should be detectable too")

# ── Mustering / cooldown ───────────────────────────────────────────────────────

func test_muster_spawns_one_per_turn_then_cools_down() -> void:
	var gs = make_gs(2)
	var camp = _camp(gs, 10, 10)
	camp.alert_turns = 3
	camp.alert_target_x = 5
	camp.alert_target_y = 5

	var cooldown = gs.db.get_constant("wild_alert_cooldown", 8)

	for _i in range(3):
		WildAI._muster(gs, gs.rng)
	var spawned = 0
	for u in gs.units:
		if u.is_wild:
			spawned += 1
	assert_eq(spawned, 3, "A length-3 wave musters exactly three raiders")
	assert_eq(camp.alert_turns, 0, "Wave exhausted")
	assert_eq(camp.alert_cooldown, cooldown, "Cooldown begins once the wave ends")

	# During cooldown no new units appear and the timer winds down.
	WildAI._muster(gs, gs.rng)
	var after = 0
	for u in gs.units:
		if u.is_wild:
			after += 1
	assert_eq(after, 3, "No new spawns while cooling down")
	assert_eq(camp.alert_cooldown, cooldown - 1, "Cooldown ticks each world step")

func test_mustered_raiders_carry_the_wave_target() -> void:
	var gs = make_gs(2)
	var camp = _camp(gs, 10, 10)
	camp.alert_turns = 1
	camp.alert_target_x = 4
	camp.alert_target_y = 7
	WildAI._muster(gs, gs.rng)
	var raider = null
	for u in gs.units:
		if u.is_wild:
			raider = u
	assert_not_null(raider, "A raider was mustered")
	assert_eq(raider.goto_x, 4, "Raider marches toward the wave target (x)")
	assert_eq(raider.goto_y, 7, "Raider marches toward the wave target (y)")
	assert_eq(raider.owner_player_id, -2, "Mustered unit belongs to the wild faction")

# ── Wave unit selection (gap 2 + 3) ────────────────────────────────────────────

func test_wave_unit_scales_with_leading_tech_ignoring_resources() -> void:
	var gs = make_gs(2)
	# No techs yet: only the tech-free warrior qualifies.
	assert_eq(WildAI._strongest_wild_unit_type(gs), "warrior",
		"Stone-age raiders are warriors")

	# Give the leader bronze working (axeman) but NO copper: resource is ignored,
	# so the stronger axeman is still chosen.
	gs.players[0].technologies = ["bronze_working"]
	assert_eq(WildAI._strongest_wild_unit_type(gs), "axeman",
		"Raiders upgrade with tech and ignore the copper requirement")

# ── Marching / combat ──────────────────────────────────────────────────────────

func test_raider_marches_toward_its_goal() -> void:
	var gs = make_gs(2)
	var u = make_warrior(gs, -2, 2, 2, true)
	u.goto_x = 8
	u.goto_y = 2
	WildAI.run(gs, gs.rng)
	assert_true(u.x > 2, "Raider advanced toward its goal (now x=%d)" % u.x)
	assert_eq(u.goto_y, 2, "Goal retained until arrival")

func test_raider_attacks_a_player_unit_in_its_path() -> void:
	var gs = make_gs(2)
	make_warrior(gs, 1, 5, 5)               # player defender
	var raider = make_warrior(gs, -2, 5, 6, true)
	raider.goto_x = 5
	raider.goto_y = 5
	WildAI.run(gs, gs.rng)

	var saw_combat = false
	for e in gs.pending_wild_events:
		if e["kind"] == "combat":
			saw_combat = true
	assert_true(saw_combat, "A raider reaching a player resolves combat")

func test_raider_razes_an_undefended_player_city() -> void:
	# §4.8: an undefended (non-capital) player city is razed outright in a single
	# wild attack — no siege-HP grind. A full-HP, multi-pop city still falls at once.
	var gs = make_gs(2)
	var city = make_settlement(gs, 1, 5, 5, 4)
	city.peak_population = 4
	city.health = -1                         # "full" — proves HP no longer matters
	var raider = make_warrior(gs, -2, 5, 6, true)
	raider.goto_x = 5
	raider.goto_y = 5
	WildAI.run(gs, gs.rng)

	assert_null(gs.get_settlement_at(5, 5), "A healthy undefended city is razed in one attack")
	var razed = false
	for e in gs.pending_wild_events:
		if e["kind"] == "razed":
			razed = true
	assert_true(razed, "A raze event was recorded for the facade to surface")

# ── Capital protection + stacking guard (Issue 11, Issue 15) ──────────────────

# Issue 11 regression: a wild unit that wins combat against a garrison on a city
# tile must NOT advance onto that tile. Without the fix it slid inside the city
# and got stuck — unable to assault from within and unable to move away.
func test_raider_does_not_advance_onto_city_tile_after_killing_garrison() -> void:
	var gs = make_gs(2)
	var city = make_settlement(gs, 1, 5, 5, 2)
	city.peak_population = 2
	city.structures.append("palace")
	# Garrison: a very weak player unit on the city tile.
	var garrison = make_warrior(gs, 1, 5, 5)
	garrison.health = 1  # will die in one hit
	# Strong raider one tile away.
	var raider = make_warrior(gs, -2, 5, 4, true)
	raider.base_strength = 50  # guaranteed to win
	raider.goto_x = 5
	raider.goto_y = 5

	WildAI.run(gs, gs.rng)

	# The garrison should be dead (or at least combat was initiated).
	var combat_happened = false
	for e in gs.pending_wild_events:
		if e["kind"] == "combat":
			combat_happened = true
	assert_true(combat_happened, "Combat should have occurred")
	# The raider must NOT be on the city tile.
	assert_true(raider.x != 5 or raider.y != 5,
		"Wild unit must not advance onto a city tile after killing its garrison (Issue 11)")
	# The city still exists and belongs to the original owner.
	var surviving = gs.get_settlement_at(5, 5)
	assert_not_null(surviving, "City must still exist")
	assert_eq(surviving.owner_player_id, 1, "City must still belong to player 1")

# Issue 15: wild forces cannot attack a player's capital at all. The palace marks
# the seat of government; a palace-bearing city is off-limits — it is never razed
# and a raider stops short of it (treats it as an impassable wall) rather than
# assaulting it. Even a powerful raider on the undefended capital tile's doorstep
# leaves it wholly intact.
func test_wild_unit_cannot_attack_the_capital() -> void:
	var gs = make_gs(2)
	var capital = make_settlement(gs, 1, 5, 5, 3)
	capital.peak_population = 3
	capital.structures.append("palace")
	# A powerful raider adjacent to the undefended capital.
	var raider = make_warrior(gs, -2, 5, 4, true)
	raider.base_strength = 50  # huge — would raze any non-capital city instantly
	raider.goto_x = 5
	raider.goto_y = 5

	WildAI.run(gs, gs.rng)

	# The capital must still exist, intact, and the raider must not be inside it.
	var surviving = gs.get_settlement_at(5, 5)
	assert_not_null(surviving, "Capital must survive a wild assault (Issue 15)")
	assert_eq(surviving.owner_player_id, 1, "Capital must remain owned by player 1")
	assert_true(raider.x != 5 or raider.y != 5, "A raider never enters the capital tile")
	# It should NOT have been razed (no wild raze event for it).
	for e in gs.pending_wild_events:
		if e["kind"] == "razed":
			assert_ne(e.get("settlement_id", -1), capital.id,
				"Capital must not appear in wild raze events")

# Confirm wild units CAN still raze a non-capital city (the protection is scoped
# to the palace-bearing settlement only).
func test_wild_unit_can_raze_a_non_capital_city() -> void:
	var gs = make_gs(2)
	var city = make_settlement(gs, 1, 5, 5, 3)
	city.peak_population = 3
	city.health = -1  # full HP — instant raze does not depend on siege HP
	# No palace — not a capital.
	var raider = make_warrior(gs, -2, 5, 4, true)
	raider.base_strength = 50
	raider.goto_x = 5
	raider.goto_y = 5

	WildAI.run(gs, gs.rng)

	assert_null(gs.get_settlement_at(5, 5), "Non-capital cities can still be razed by wild forces")

# ── Facade surfacing ───────────────────────────────────────────────────────────

func test_facade_drains_wild_events_into_signals() -> void:
	var gs = make_gs(2)
	var f = bare_facade(gs)
	gs.pending_wild_events = [
		{"kind": "razed", "settlement_id": 7, "name": "Pompeii"}]
	watch_signals(f)
	f._drain_wild_events()
	assert_signal_emitted(f, "city_razed")
	assert_true(gs.pending_wild_events.empty(), "Queue cleared after draining")

# ── Persistence + determinism ──────────────────────────────────────────────────

func test_camp_alert_state_survives_save_load() -> void:
	var gs = make_gs(2)
	var camp = _camp(gs, 9, 9)
	camp.alert_turns = 2
	camp.alert_target_x = 3
	camp.alert_target_y = 4
	camp.alert_cooldown = 5

	var restored = load("res://src/sim/game_state.gd").deserialize(gs.serialize(), gs.db)
	var rc = restored.get_settlement_at(9, 9)
	assert_eq(rc.alert_turns, 2, "alert_turns persisted")
	assert_eq(rc.alert_target_x, 3, "alert_target_x persisted")
	assert_eq(rc.alert_target_y, 4, "alert_target_y persisted")
	assert_eq(rc.alert_cooldown, 5, "alert_cooldown persisted")

func test_aggressive_flag_persists_and_widens_reach() -> void:
	var gs = make_gs(2)
	var base = WildAI._scout_sight(gs, gs.db)
	gs.wild_aggressive = true
	assert_true(WildAI._scout_sight(gs, gs.db) > base,
		"Aggressive raiders see further")
	var restored = load("res://src/sim/game_state.gd").deserialize(gs.serialize(), gs.db)
	assert_true(restored.wild_aggressive, "Aggression flag survives save/load")

func test_wild_ai_is_deterministic_under_same_seed() -> void:
	var a = setup_facade(909, "tiny")
	var b = setup_facade(909, "tiny")
	run_turns(a, 12)
	run_turns(b, 12)
	assert_eq(a.state_hash(), b.state_hash(),
		"Identical seeds must yield identical wild-forces play")
