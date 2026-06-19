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

# Integration playthrough — the final gate, run after the unit suites (see
# run_tests.sh / .github/workflows/build.yml). Instead of isolating one rule,
# each test drives a slice of a real game through the SimFacade command channel,
# exercising most of the interaction families end to end:
#
#   • founding, economy sliders, research, production & city management
#   • unit commands and missions (fortify, skip, build road, pillage, upgrade, disband)
#   • war declaration and combat resolution, then peace
#   • diplomacy (trades of gold & tech) and espionage
#   • Great People actions and governing-policy switches
#   • save / load determinism mid-game (the state-hash gate)
#   • one sparing use of the debug console to set up a late-game condition that
#     would otherwise take hundreds of turns of research to reach
#
# Players are handed whatever starting cities/units/gold a scenario needs (the
# brief allows this). Direct value modification is avoided except where a
# condition is genuinely impractical to simulate — and there it goes through the
# real DebugConsole, so that surface is integration-tested too.

# A fresh two-player game on a uniform 16×16 grassland map (predictable movement
# and adjacency), armed with a Hooks registry so end_turn runs the full pipeline.
func _new_game(seed_val = 7):
	var gs = make_gs(2, seed_val, 16, 16)   # make_gs paints every tile grassland
	gs.current_player_id = 1
	var f = bare_facade(gs)
	f._hooks = hooks()
	return [gs, f]

# Advance one player's turn through the real command path.
func _end_turn(f, gs, pid):
	gs.current_player_id = pid
	f.apply_command(Commands.end_turn(pid))

# ── Economy: found, sliders, research, specialists ───────────────────────────────

func test_playthrough_setup_economy_and_research() -> void:
	var ng = _new_game(11); var gs = ng[0]; var f = ng[1]
	var pid = 1

	# Found a capital from a settler.
	var settler = make_unit(gs, "settler", pid, 10, 10)
	assert_true(f.apply_command(Commands.found_settlement(pid, settler.id, "Capital")),
		"settler founds the capital")
	assert_eq(gs.settlements.size(), 1, "one city exists")
	assert_null(gs.get_unit(settler.id), "the settler is consumed")
	var city = gs.settlements[0]
	city.population = 3

	# Economic sliders (must sum to 100; default policies impose no increment).
	assert_true(f.apply_command(Commands.set_sliders(pid, 30, 50, 10, 10)),
		"economic sliders accepted")
	assert_eq(gs.get_player(pid).slider_research, 50, "research slider applied")

	# Pick a research target and run several turns; the target must survive the
	# pipeline (it completes only if commerce funds it — economy-dependent, so we
	# assert the durable invariant rather than a turn count).
	assert_true(f.apply_command(Commands.set_research(pid, "mining")),
		"research target set")
	for _i in range(5):
		_end_turn(f, gs, pid)
		_end_turn(f, gs, 2)
	var p = gs.get_player(pid)
	assert_true(p.current_research_id == "mining" or p.has_tech("mining"),
		"research target persists across turns (or completed)")

	# Assign a specialist (bounded by population).
	assert_true(f.apply_command(Commands.assign_specialist(pid, city.id, "scientist", 1)),
		"specialist assignment accepted")
	assert_eq(int(city.specialists.get("scientist", 0)), 1, "one scientist seated")

# ── Production & city management (queue + rush via Slavery) ───────────────────────

func test_playthrough_production_and_city_management() -> void:
	var ng = _new_game(12); var gs = ng[0]; var f = ng[1]
	var pid = 1
	var city = make_settlement(gs, pid, 8, 8, 4)

	# Queue a unit, then enable Slavery (needs no tech) and population-rush it.
	assert_true(f.apply_command(Commands.set_production(pid, city.id,
		[{"type": "unit", "id": "warrior"}])), "production queue set")
	assert_true(f.apply_command(Commands.set_policy(pid, "labor", "slavery")),
		"Slavery civic adopted")
	assert_eq(gs.get_player(pid).policies.get("labor", ""), "slavery", "labor civic recorded")

	var before = gs.units.size()
	assert_true(f.apply_command(Commands.rush_production(pid, city.id, "population")),
		"population rush permitted by Slavery")
	# The rushed item completes during the owner's settlement step.
	_end_turn(f, gs, pid)
	assert_true(gs.units.size() > before, "the rushed warrior was produced")

# ── Unit commands & missions ─────────────────────────────────────────────────────

func test_playthrough_unit_commands_and_missions() -> void:
	var ng = _new_game(13); var gs = ng[0]; var f = ng[1]
	var pid = 1
	gs.get_player(pid).treasury = 1000   # starting gold (scenario setup, not a hack)

	# Fortify, then a skip-turn mission.
	var guard = make_warrior(gs, pid, 3, 3)
	assert_true(f.apply_command(Commands.unit_fortify(pid, guard.id)), "fortify accepted")
	assert_true(guard.is_fortified, "unit is fortified")

	var scout = make_unit(gs, "scout", pid, 4, 4)
	assert_true(f.apply_command(Commands.mission_skip_turn(pid, scout.id)), "skip-turn accepted")
	assert_true(scout.has_moved, "skipped unit is marked moved")

	# Worker: build-road mission, then pillage an existing improvement.
	var worker = make_unit(gs, "worker", pid, 5, 5)
	assert_true(f.apply_command(Commands.mission_build_road(pid, worker.id)), "build-road accepted")
	assert_eq(worker.building_improvement, "road", "worker is laying a road")

	var w2 = make_unit(gs, "worker", pid, 6, 6)
	gs.map.get_tile(6, 6).improvement_id = "mine"
	assert_true(f.apply_command(Commands.mission_pillage(pid, w2.id)), "pillage accepted")
	assert_eq(gs.map.get_tile(6, 6).improvement_id, "", "pillage cleared the improvement")

	# Upgrade a warrior to an axeman (costs gold), then disband a spare unit.
	var vet = make_warrior(gs, pid, 7, 7)
	assert_true(f.apply_command(Commands.unit_upgrade(pid, vet.id)), "upgrade accepted")
	assert_eq(gs.get_unit(vet.id).unit_type_id, "axeman", "warrior upgraded to axeman")

	var spare = make_warrior(gs, pid, 9, 9)
	assert_true(f.apply_command(Commands.unit_disband(pid, spare.id)), "disband accepted")
	assert_null(gs.get_unit(spare.id), "disbanded unit removed")

# ── War & combat ─────────────────────────────────────────────────────────────────

func test_playthrough_war_and_combat() -> void:
	var ng = _new_game(14); var gs = ng[0]; var f = ng[1]

	var attacker = make_warrior(gs, 1, 5, 5)
	var defender = make_warrior(gs, 2, 6, 5)

	# Declare war (alliance level), then attack into the enemy tile.
	assert_true(f.apply_command(Commands.declare_war(1, 2)), "war declared")
	assert_true(gs.are_at_war(1, 2), "alliances are at war")

	var hp_before = attacker.health + defender.health   # 200 at full
	gs.current_player_id = 1
	assert_true(f.apply_command(Commands.move_stack(1, 5, 5, 6, 5)),
		"attack-move into the enemy tile is accepted")
	var survivors = gs.units.size()
	var hp_after = 0
	for u in gs.units:
		hp_after += u.health
	assert_true(survivors < 2 or hp_after < hp_before,
		"combat resolved: a unit died or took damage")

	# A negotiated peace ends the war.
	assert_true(f.apply_command(Commands.make_peace(1, 2)), "peace accepted")
	assert_false(gs.are_at_war(1, 2), "war is over")

# ── Diplomacy: trades & espionage ────────────────────────────────────────────────

func test_playthrough_diplomacy_trade_and_espionage() -> void:
	var ng = _new_game(15); var gs = ng[0]; var f = ng[1]
	gs.get_player(1).treasury = 200
	gs.get_player(2).treasury = 0
	gs.get_player(2).technologies = ["mining"]

	# Player 1 proposes a gold-for-tech trade; player 2 accepts on their turn.
	gs.current_player_id = 1
	assert_true(f.apply_command(Commands.propose_trade(1, 2,
		{"gold": 80}, {"techs": ["mining"]}, false)), "trade proposed")
	var tid = int(gs.alliances[0].pending_trades[0]["id"])
	gs.current_player_id = 2
	assert_true(f.apply_command(Commands.accept_trade(2, tid)), "trade accepted")
	assert_eq(gs.get_player(1).treasury, 120, "proposer paid 80 gold")
	assert_true(gs.get_player(1).has_tech("mining"), "proposer received the tech")

	# Espionage: with enough intel points, steal an unknown tech.
	gs.get_player(2).technologies = ["mining", "pottery"]
	var cost = gs.db.get_constant("intel_mission_cost", 100)
	gs.get_player(1).intel_points = {2: cost}
	gs.current_player_id = 1
	assert_true(f.apply_command(Commands.espionage_mission(1, 2, "steal_tech")),
		"espionage mission runs when points suffice")
	assert_eq(int(gs.get_player(1).intel_points.get(2, 0)), 0, "the mission spent its intel points")

# ── Great People & governing policies ────────────────────────────────────────────

func test_playthrough_great_people_and_policies() -> void:
	var ng = _new_game(16); var gs = ng[0]; var f = ng[1]
	var pid = 1

	# Two Great People trigger the first Golden Age (base cost is 2 GPs), both
	# directed through the GP_ACTION command path.
	gs.current_player_id = pid
	var artist = make_gp(gs, "great_artist", pid, 5, 5)
	assert_true(f.apply_command(Commands.gp_action(pid, artist.id, "start_golden_age", {})),
		"first Great Person banked toward a Golden Age")
	assert_eq(gs.get_player(pid).golden_age_turns, 0, "one GP is not yet enough")
	var engineer = make_gp(gs, "great_engineer", pid, 5, 5)
	assert_true(f.apply_command(Commands.gp_action(pid, engineer.id, "start_golden_age", {})),
		"second Great Person completes the Golden Age")
	assert_true(gs.get_player(pid).golden_age_turns > 0, "a Golden Age is running")

	# Switch a governing policy (Hereditary Rule needs Monarchy; grant the prereq as
	# scenario setup so the switch is the thing under test).
	gs.get_player(pid).technologies.append("monarchy")
	assert_true(f.apply_command(Commands.set_policy(pid, "government", "hereditary_rule")),
		"governing policy switched")
	assert_eq(gs.get_player(pid).policies.get("government", ""), "hereditary_rule",
		"the new civic is recorded")

# ── Save / load determinism (the state-hash gate) ────────────────────────────────

func test_playthrough_save_load_determinism_midgame() -> void:
	var ng = _new_game(17); var gs = ng[0]; var f = ng[1]

	# Build a non-trivial mid-game: a city, some units, a few turns of pipeline.
	make_settlement(gs, 1, 8, 8, 3)
	make_warrior(gs, 1, 4, 4)
	make_unit(gs, "worker", 2, 9, 9)
	for _i in range(3):
		_end_turn(f, gs, 1)
		_end_turn(f, gs, 2)

	var mid_hash = f.state_hash()
	var save_str = f.save()

	# Continue the original game.
	for _i in range(2):
		_end_turn(f, gs, 1)
		_end_turn(f, gs, 2)
	var continued_hash = f.state_hash()

	# Load the save into a brand-new facade (the start-menu "Load Game" path) and
	# confirm it reproduces the pre-save hash, then resumes to the same future.
	var f2 = load("res://src/api/sim_facade.gd").new()
	f2.init_for_load(make_db())
	assert_true(f2.load_save(save_str), "save loads into a fresh facade")
	assert_eq(f2.state_hash(), mid_hash, "loaded hash matches the pre-save hash")
	var gs2 = f2.get_state()
	for _i in range(2):
		_end_turn(f2, gs2, 1)
		_end_turn(f2, gs2, 2)
	assert_eq(f2.state_hash(), continued_hash,
		"resumed game stays deterministic with the original")

# Save/load determinism with the §9 random-event lifecycle mid-flight: an
# in-progress timed event and a parked human choice are serialized state, so a
# roundtrip must reproduce the hash and resume identically.
func test_playthrough_save_load_determinism_midevent() -> void:
	var ng = _new_game(23); var gs = ng[0]; var f = ng[1]
	make_settlement(gs, 1, 8, 8, 3).health = 100
	make_warrior(gs, 1, 4, 4)
	make_settlement(gs, 2, 12, 12, 2).health = 100

	# Stand up the lifecycle state directly: a timed plague on player 1 (mid-duration)
	# and an unresolved choice the human still owes.
	Events.apply_event_begin(gs.db.get_event("great_plague"), gs.get_player(1), gs)
	Events.tick_active_events(gs.get_player(1), gs)   # burn one turn of the timer
	gs.pending_event_choices.append(
		{"event_id": "wandering_nomads", "player_id": 1, "trigger_id": "trig_wandering_nomads"})

	for _i in range(2):
		_end_turn(f, gs, 1)
		_end_turn(f, gs, 2)

	var mid_hash = f.state_hash()
	var save_str = f.save()
	for _i in range(2):
		_end_turn(f, gs, 1)
		_end_turn(f, gs, 2)
	var continued_hash = f.state_hash()

	var f2 = load("res://src/api/sim_facade.gd").new()
	f2.init_for_load(make_db())
	assert_true(f2.load_save(save_str), "mid-event save loads into a fresh facade")
	assert_eq(f2.state_hash(), mid_hash, "loaded hash matches the pre-save hash (active events intact)")
	var gs2 = f2.get_state()
	# The parked human choice survived the load and can still be resolved.
	assert_false(f2.get_pending_event(1).empty(), "the human's parked event choice survives the load")
	for _i in range(2):
		_end_turn(f2, gs2, 1)
		_end_turn(f2, gs2, 2)
	assert_eq(f2.state_hash(), continued_hash,
		"resumed game with active events stays deterministic with the original")

# ── §7 Diplomacy: active deals + attitude memory survive save/load (Phase 7) ────

func test_playthrough_save_load_determinism_middeal() -> void:
	var ng = _new_game(31); var gs = ng[0]; var f = ng[1]
	make_settlement(gs, 1, 8, 8, 3).health = 100
	make_settlement(gs, 2, 12, 12, 2).health = 100
	gs.get_player(1).treasury = 500
	gs.get_player(2).treasury = 500

	# A standing recurring deal (player 1 pays player 2 each world step) and a live
	# diplomatic grievance — both serialized relational state added in Phase 7.
	gs.deals.append({
		"id": gs.next_trade_id(),
		"a_alliance": 1, "b_alliance": 2,
		"proposer_player_id": 1, "accepter_player_id": 2,
		"recurring": {"give": {"gold_per_turn": 4}, "receive": {"gold_per_turn": 1}},
		"start_turn": gs.turn_number, "min_duration": 30
	})
	Diplomacy.record(gs, gs.db, 2, 1, "declared_war")  # player 2 resents player 1

	for _i in range(2):
		_end_turn(f, gs, 1)
		_end_turn(f, gs, 2)

	var mid_hash = f.state_hash()
	var save_str = f.save()
	for _i in range(2):
		_end_turn(f, gs, 1)
		_end_turn(f, gs, 2)
	var continued_hash = f.state_hash()

	var f2 = load("res://src/api/sim_facade.gd").new()
	f2.init_for_load(make_db())
	assert_true(f2.load_save(save_str), "mid-deal save loads into a fresh facade")
	assert_eq(f2.state_hash(), mid_hash,
		"loaded hash matches the pre-save hash (deal + memory intact)")
	var gs2 = f2.get_state()
	assert_eq(gs2.deals.size(), 1, "the active deal survives the load")
	assert_true(Diplomacy.memory_total(gs2.get_player(2), 1) < 0,
		"the diplomatic grievance survives the load")
	for _i in range(2):
		_end_turn(f2, gs2, 1)
		_end_turn(f2, gs2, 2)
	assert_eq(f2.state_hash(), continued_hash,
		"resumed game with an active deal + memory stays deterministic with the original")

# ── Debug console: one sparing value-mod for a late-game condition ───────────────

func test_playthrough_debug_console_unlocks_lategame_condition() -> void:
	var ng = _new_game(18); var gs = ng[0]; var f = ng[1]
	var pid = 1
	var city = make_settlement(gs, pid, 8, 8, 4)
	gs.get_player(pid).treasury = 100000

	var console = DebugConsole.new()
	console.init(f, DebugLog.new())

	# Universal Suffrage requires Democracy (cost ~2800 — hundreds of turns to
	# research in a fixture). Granting just that prerequisite through the real
	# DebugConsole is the one justified value-mod: it lets us exercise the
	# gold-rush path (gated on Universal Suffrage's `can_rush_with_gold`).
	console.execute("tech " + str(pid) + " democracy")
	assert_true(gs.get_player(pid).has_tech("democracy"), "debug console granted the prereq tech")

	assert_true(f.apply_command(Commands.set_policy(pid, "government", "universal_suffrage")),
		"Universal Suffrage adopted once its tech is known")
	assert_true(f.apply_command(Commands.set_production(pid, city.id,
		[{"type": "unit", "id": "warrior"}])), "production queued")
	assert_true(f.apply_command(Commands.rush_production(pid, city.id, "treasury")),
		"gold rush permitted by Universal Suffrage")

	var before = gs.units.size()
	_end_turn(f, gs, pid)
	assert_true(gs.units.size() > before, "the gold-rushed unit was produced")

# ── Victory: a win condition fires through the real pipeline ──────────────────────
# The other playthrough slices stop short of ending the game; this one drives a
# board to a cultural victory and ends a full round so the world step's §10 win
# check (turn_engine `WORLD_CHECK_WIN`) actually fires and the facade raises
# `game_won`. Cultural is the natural fit for an end-to-end check: a city's
# `culture_ring` is recomputed each turn from its accumulated `culture_total`, so
# pre-seeded legendary cities survive the pipeline (unlike raw tile ownership,
# which the influence pass rewrites).
func test_playthrough_reaches_a_cultural_victory() -> void:
	var ng = _new_game(21); var gs = ng[0]; var f = ng[1]
	gs.enabled_win_conditions = ["cultural", "time"]

	var thresholds = gs.db.constants.get("culture_ring_thresholds", [])
	var legendary = int(thresholds[thresholds.size() - 1]) + 1   # past the top ring
	var need = int(gs.db.win_conditions["cultural"].get("cities_at_max_culture", 3))

	# Player 1 owns the required number of legendary cities; player 2 has one
	# fledgling town that never threatens to flip them.
	for i in range(need):
		var s = make_settlement(gs, 1, 3 + i * 3, 5, 6)
		s.culture_total = legendary
	make_settlement(gs, 2, 14, 14, 2)

	watch_signals(f)
	assert_eq(gs.winning_alliance_id, -1, "the game is still running before the round")

	# End a whole round so the last end-turn triggers world_step → win check.
	_end_turn(f, gs, 1)
	_end_turn(f, gs, 2)

	assert_eq(gs.winning_alliance_id, gs.get_player(1).alliance_id,
		"the cultural alliance wins through the real turn pipeline")
	assert_signal_emitted(f, "game_won", "the facade raised game_won on victory")
