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

# Per-unit, per-turn state driven by the player step: entrenchment while
# stationary (§5.3), healing (§5.6), and class-bounded movement (§5.2).

# ── Entrenchment (§5.3) ──────────────────────────────────────────────────────

func test_entrenchment_grows_while_stationary() -> void:
	var gs = make_gs()
	gs.get_player(1).treasury = 100000  # stay solvent so the unit is not disbanded
	var u = make_warrior(gs, 1, 5, 5)
	u.entrenchment = 0; u.stationary_turns = 0
	var per: int = gs.db.get_constant("entrenchment_per_turn", 5)
	TurnEngine.player_step(gs, 1, hooks())
	assert_eq(u.entrenchment, per, "One stationary turn grants one increment of entrenchment")
	TurnEngine.player_step(gs, 1, hooks())
	assert_eq(u.entrenchment, per * 2, "A second stationary turn stacks entrenchment")

func test_entrenchment_capped() -> void:
	var gs = make_gs()
	gs.get_player(1).treasury = 100000
	var u = make_warrior(gs, 1, 5, 5)
	var cap: int = gs.db.get_constant("entrenchment_cap", 25)
	for _i in range(20):
		TurnEngine.player_step(gs, 1, hooks())
	assert_eq(u.entrenchment, cap, "Entrenchment never exceeds the data cap")

func test_moving_unit_does_not_entrench() -> void:
	var gs = make_gs()
	var u = make_warrior(gs, 1, 5, 5)
	u.has_moved = true  # simulate having moved this turn
	TurnEngine.player_step(gs, 1, hooks())
	assert_eq(u.entrenchment, 0, "A unit that moved this turn gains no entrenchment")
	assert_eq(u.stationary_turns, 0, "Stationary counter stays at zero for a moved unit")

# ── Healing (§5.6) ───────────────────────────────────────────────────────────

func test_stationary_unit_heals_in_neutral_territory() -> void:
	var gs = make_gs()
	var u = make_warrior(gs, 1, 5, 5)
	u.health = 50
	var rate: int = gs.db.get_constant("healing_neutral_territory", 5)
	TurnEngine.player_step(gs, 1, hooks())
	assert_eq(u.health, 50 + rate, "Stationary unit heals at the neutral-territory rate")

func test_unit_heals_faster_in_own_settlement() -> void:
	var gs = make_gs()
	make_settlement(gs, 1, 5, 5)
	var u = make_warrior(gs, 1, 5, 5)
	u.health = 40
	var rate: int = gs.db.get_constant("healing_in_settlement", 30)
	TurnEngine.player_step(gs, 1, hooks())
	assert_eq(u.health, 40 + rate, "Garrisoned unit heals at the settlement rate")

func test_moving_unit_does_not_heal() -> void:
	var gs = make_gs()
	var u = make_warrior(gs, 1, 5, 5)
	u.health = 50; u.has_moved = true
	TurnEngine.player_step(gs, 1, hooks())
	assert_eq(u.health, 50, "A unit that moved this turn does not heal")

func test_healing_caps_at_full() -> void:
	var gs = make_gs()
	var u = make_warrior(gs, 1, 5, 5)
	u.health = 95
	TurnEngine.player_step(gs, 1, hooks())
	assert_eq(u.health, 100, "Healing never exceeds full health")

# ── Class-bounded movement (§5.2) ────────────────────────────────────────────

func _move_distance_for(unit_type, sx, sy, tx, ty):
	# Spawn a unit of the given class on an open grassland map and try to move it
	# far in a single command; return how many tiles it actually advanced.
	var facade = setup_facade(7, "standard",
		[{"name": "A", "leader_id": "", "traits": [], "starting_gold": 50}], ["time"])
	var gs = facade.get_state()
	for tile in gs.map.all_tiles():
		tile.terrain_id = "grassland"
	var pid = gs.players[0].id
	gs.current_player_id = pid
	var u = make_unit(gs, unit_type, pid, sx, sy)
	facade.apply_command(Commands.move_stack(pid, sx, sy, tx, ty))
	return gs.map.distance(sx, sy, u.x, u.y)

func test_movement_is_bounded_by_class() -> void:
	# Warrior: movement 100 = 1 tile per turn on flat land.
	var warrior_dist = _move_distance_for("warrior", 5, 5, 20, 5)
	assert_eq(warrior_dist, 1, "Warrior should advance exactly 1 tile, not the full path")
	# Scout: movement 200 = 2 tiles, and faster than a warrior.
	var scout_dist = _move_distance_for("scout", 5, 5, 20, 5)
	assert_eq(scout_dist, 2, "Scout should advance exactly 2 tiles per turn")
	assert_true(scout_dist > warrior_dist, "Scout should out-range the warrior")

# ── Issue 5: Move cancels Fortify (§3.3) ──────────────────────────────────────

func test_move_clears_fortify_flag() -> void:
	# A fortified unit that receives a move order should lose its fortified state.
	var facade = setup_facade(7, "standard",
		[{"name": "A", "leader_id": "", "traits": [], "starting_gold": 50}], ["time"])
	var gs = facade.get_state()
	for tile in gs.map.all_tiles():
		tile.terrain_id = "grassland"
	var pid = gs.players[0].id
	gs.current_player_id = pid
	var u = make_unit(gs, "warrior", pid, 5, 5)
	# Fortify the unit.
	facade.apply_command(Commands.unit_fortify(pid, u.id))
	assert_true(u.is_fortified, "Unit should be fortified after UNIT_FORTIFY")
	# End the turn to reset state, then move.
	gs.current_player_id = pid
	u.has_moved = false; u.movement_left = u.movement_total
	facade.apply_command(Commands.move_stack(pid, 5, 5, 6, 5))
	assert_false(u.is_fortified, "Moving should clear the fortified flag (Issue 5)")

func test_fortify_persists_if_unit_does_not_move() -> void:
	# If no move is issued, is_fortified must remain true across the turn.
	var gs = make_gs(1)
	gs.get_player(1).treasury = 100000
	var u = make_warrior(gs, 1, 5, 5)
	u.is_fortified = true
	TurnEngine.player_step(gs, 1, hooks())
	assert_true(u.is_fortified, "Fortify flag must survive a turn with no move order")

# ── Issue 9: Sleep Until Healed / Fortify Until Healed (§3.3) ─────────────────

func test_sleep_until_healed_sets_stance() -> void:
	var gs = make_gs(1)
	gs.get_player(1).treasury = 100000
	var u = make_warrior(gs, 1, 5, 5)
	u.health = 50
	var facade = bare_facade(gs)
	gs.current_player_id = 1
	var ok: bool = facade.apply_command(Commands.mission_sleep_until_healed(1, u.id))
	assert_true(ok, "MISSION_SLEEP_UNTIL_HEALED should be accepted")
	assert_true(u.is_sleep_until_healed, "is_sleep_until_healed should be set")
	assert_false(u.is_fortified, "sleep stance should not set is_fortified")

func test_fortify_until_healed_sets_stance_and_fortify() -> void:
	var gs = make_gs(1)
	gs.get_player(1).treasury = 100000
	var u = make_warrior(gs, 1, 5, 5)
	u.health = 50
	var facade = bare_facade(gs)
	gs.current_player_id = 1
	var ok: bool = facade.apply_command(Commands.mission_fortify_until_healed(1, u.id))
	assert_true(ok, "MISSION_FORTIFY_UNTIL_HEALED should be accepted")
	assert_true(u.is_fortify_until_healed, "is_fortify_until_healed should be set")
	assert_true(u.is_fortified, "fortify stance should also set is_fortified for the defence bonus")

func test_fortify_until_healed_rejected_for_civilians() -> void:
	var gs = make_gs(1)
	var u = make_unit(gs, "worker", 1, 5, 5)
	u.health = 50
	var facade = bare_facade(gs)
	gs.current_player_id = 1
	var ok: bool = facade.apply_command(Commands.mission_fortify_until_healed(1, u.id))
	assert_false(ok, "Civilian units cannot use Fortify Until Healed")

func test_sleep_until_healed_heals_each_turn() -> void:
	var gs = make_gs(1)
	gs.get_player(1).treasury = 100000
	var u = make_warrior(gs, 1, 5, 5)
	u.health = 50
	u.is_sleep_until_healed = true
	var before: int = u.health
	TurnEngine.player_step(gs, 1, hooks())
	assert_true(u.health > before, "A unit in sleep-until-healed stance should heal each turn")

func test_sleep_until_healed_wakes_at_full_health() -> void:
	var gs = make_gs(1)
	gs.get_player(1).treasury = 100000
	var u = make_warrior(gs, 1, 5, 5)
	u.health = 95  # close to full; one neutral-territory heal tick will reach 100
	u.is_sleep_until_healed = true
	TurnEngine.player_step(gs, 1, hooks())
	# After healing to 100, the stance should be cleared.
	assert_false(u.is_sleep_until_healed,
		"sleep_until_healed should clear automatically once fully healed")
	assert_false(u.is_fortified, "No fortify bonus should linger after sleep stance clears")

func test_fortify_until_healed_wakes_and_clears_fortify_at_full_health() -> void:
	var gs = make_gs(1)
	gs.get_player(1).treasury = 100000
	var u = make_warrior(gs, 1, 5, 5)
	u.health = 95
	u.is_fortify_until_healed = true
	u.is_fortified = true
	TurnEngine.player_step(gs, 1, hooks())
	assert_false(u.is_fortify_until_healed,
		"fortify_until_healed should clear once fully healed")
	assert_false(u.is_fortified,
		"is_fortified should be cleared when the fortify-until-healed stance ends")

func test_sleep_until_healed_skipped_by_idle_cycle() -> void:
	# The idle-unit cycling (NEXT_IDLE_UNIT) must not surface a unit in this stance.
	var gs = make_gs(1)
	var u = make_warrior(gs, 1, 5, 5)
	u.health = 50
	u.is_sleep_until_healed = true
	var facade = bare_facade(gs)
	facade._selection = load("res://src/api/selection_state.gd").new()
	gs.current_player_id = 1
	facade.cycle_idle_units(false)
	assert_true(facade.get_selection().head_unit() < 0,
		"A sleep-until-healed unit must not be cycled as idle")

func test_sleeping_unit_skipped_by_idle_cycle() -> void:
	# A plain Sleep order (is_sleeping) removes the unit from the idle cycle, just
	# like Fortify, until it is woken or given another order.
	var gs = make_gs(1)
	var u = make_warrior(gs, 1, 5, 5)
	u.is_sleeping = true
	var facade = bare_facade(gs)
	facade._selection = load("res://src/api/selection_state.gd").new()
	gs.current_player_id = 1
	facade.cycle_idle_units(false)
	assert_true(facade.get_selection().head_unit() < 0,
		"A sleeping unit must not be cycled as idle")

# ── Fortify restricted to land combat units (Issue 3) ────────────────────────────
# Only land combat units (domain "land", non-civilian classification, base_strength
# > 0) may fortify — both the direct UNIT_FORTIFY command and the
# MISSION_FORTIFY_UNTIL_HEALED mission are gated. Mounted units may fortify but gain
# no defensive bonus from it.

func test_fortify_accepted_for_land_melee() -> void:
	var gs = make_gs(1)
	var u = make_warrior(gs, 1, 5, 5)  # land melee
	var facade = bare_facade(gs)
	gs.current_player_id = 1
	assert_true(facade.apply_command(Commands.unit_fortify(1, u.id)),
		"A land melee unit (warrior) may fortify")
	assert_true(u.is_fortified, "The warrior is fortified after the accepted command")

func test_fortify_rejected_for_civilian() -> void:
	var gs = make_gs(1)
	var u = make_unit(gs, "settler", 1, 5, 5)  # civilian
	var facade = bare_facade(gs)
	gs.current_player_id = 1
	assert_false(facade.apply_command(Commands.unit_fortify(1, u.id)),
		"A civilian (settler) may not fortify")
	assert_false(u.is_fortified, "Rejected fortify leaves the settler unfortified")
	# A worker (also civilian) is likewise rejected.
	var w = make_unit(gs, "worker", 1, 6, 6)
	assert_false(facade.apply_command(Commands.unit_fortify(1, w.id)),
		"A worker (civilian) may not fortify")

func test_fortify_rejected_for_sea_combat_unit() -> void:
	# A galley is a naval COMBAT unit (domain sea, base_strength > 0) — still barred
	# from fortifying because fortify is land-combat-only.
	var gs = make_gs(1)
	var u = make_unit(gs, "galley", 1, 5, 5)
	var facade = bare_facade(gs)
	gs.current_player_id = 1
	assert_false(facade.apply_command(Commands.unit_fortify(1, u.id)),
		"A naval combat unit (galley) may not fortify")
	assert_false(u.is_fortified, "Rejected fortify leaves the galley unfortified")

func test_fortify_rejected_for_air_unit() -> void:
	# A fighter is an air unit (domain air, base_strength > 0) — barred from fortify.
	var gs = make_gs(1)
	var u = make_unit(gs, "fighter", 1, 5, 5)
	var facade = bare_facade(gs)
	gs.current_player_id = 1
	assert_false(facade.apply_command(Commands.unit_fortify(1, u.id)),
		"An air unit (fighter) may not fortify")
	assert_false(u.is_fortified, "Rejected fortify leaves the fighter unfortified")

func test_fortify_until_healed_rejected_for_naval_and_air() -> void:
	# The MISSION_FORTIFY_UNTIL_HEALED path is gated identically (land combat only).
	var gs = make_gs(1)
	var galley = make_unit(gs, "galley", 1, 5, 5); galley.health = 50
	var fighter = make_unit(gs, "fighter", 1, 6, 6); fighter.health = 50
	var facade = bare_facade(gs)
	gs.current_player_id = 1
	assert_false(facade.apply_command(Commands.mission_fortify_until_healed(1, galley.id)),
		"A naval unit may not Fortify Until Healed")
	assert_false(facade.apply_command(Commands.mission_fortify_until_healed(1, fighter.id)),
		"An air unit may not Fortify Until Healed")

func test_fortified_land_unit_gains_defensive_bonus() -> void:
	# A fortified (entrenched) land melee unit defends with MORE than its base.
	var gs = make_gs()
	var f = bare_facade(gs)
	var u = make_warrior(gs, 1, 5, 5)  # base 10 on grassland (no terrain bonus)
	var unfortified: int = f.unit_effective_strength(u.id)
	u.entrenchment = 20  # +20%
	var fortified: int = f.unit_effective_strength(u.id)
	assert_true(fortified > unfortified,
		"A fortified land melee unit defends with more than its unfortified strength")

func test_mounted_fortify_confers_no_defensive_bonus() -> void:
	# A mounted unit may fortify, but the entrenchment contributes ZERO to its
	# effective strength — equal fortified and unfortified — while a melee unit with
	# the same entrenchment on the same tile DOES get the bonus.
	var gs = make_gs()
	var f = bare_facade(gs)
	var knight = make_unit(gs, "knight", 1, 5, 5)  # mounted
	var unmounted_base: int = f.unit_effective_strength(knight.id)
	knight.entrenchment = 20
	var mounted_fortified: int = f.unit_effective_strength(knight.id)
	assert_eq(mounted_fortified, unmounted_base,
		"A fortified mounted unit gains no defensive bonus (entrenchment contributes 0)")

	# Control: a melee unit (axeman, same base strength 10 region) on flat ground
	# with the same entrenchment DOES benefit, proving the zeroing is mounted-only.
	var axeman = make_unit(gs, "axeman", 1, 6, 6)  # melee
	var axe_base: int = f.unit_effective_strength(axeman.id)
	axeman.entrenchment = 20
	var axe_fortified: int = f.unit_effective_strength(axeman.id)
	assert_true(axe_fortified > axe_base,
		"A melee unit with the same entrenchment does gain the fortify bonus")

func test_unit_can_fortify_predicate() -> void:
	# Direct check of the sim-side land-combat predicate.
	var gs = make_gs(1)
	var db = gs.db
	assert_true(make_unit(gs, "warrior", 1, 1, 1).can_fortify(db), "warrior (land melee) can fortify")
	assert_true(make_unit(gs, "knight", 1, 2, 2).can_fortify(db), "knight (land mounted) can fortify")
	assert_false(make_unit(gs, "settler", 1, 3, 3).can_fortify(db), "settler (civilian) cannot fortify")
	assert_false(make_unit(gs, "galley", 1, 4, 4).can_fortify(db), "galley (naval) cannot fortify")
	assert_false(make_unit(gs, "fighter", 1, 5, 5).can_fortify(db), "fighter (air) cannot fortify")
