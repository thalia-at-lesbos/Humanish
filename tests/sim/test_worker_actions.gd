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

# Issue 6: Worker improvement commands and
# Issue 13: Scout Explore mission.

# ── Issue 6: Worker improvements ─────────────────────────────────────────────

func test_worker_can_build_improvement() -> void:
	var gs = make_gs(1)
	gs.get_player(1).treasury = 10000
	# Give the player all relevant techs so any improvement is unlocked.
	gs.get_player(1).technologies = gs.db.technologies.keys().duplicate()
	var w = make_unit(gs, "worker", 1, 5, 5)
	gs.map.get_tile(5, 5).terrain_id = "grassland"  # flat landform
	var facade = bare_facade(gs)
	gs.current_player_id = 1
	var ok: bool = facade.apply_command(Commands.build_improvement(1, w.id, "farm"))
	assert_true(ok, "Worker should be able to start building a farm on grassland")
	assert_eq(w.building_improvement, "farm", "Worker building_improvement set to farm")
	assert_true(w.build_turns_left > 0, "Build turns left should be positive")

func test_worker_cannot_build_improvement_on_settlement_tile() -> void:
	var gs = make_gs(1)
	gs.get_player(1).treasury = 10000
	gs.get_player(1).technologies = gs.db.technologies.keys().duplicate()
	gs.map.get_tile(5, 5).terrain_id = "grassland"  # flat landform — farm would otherwise be legal
	# Place a settlement on the worker's tile.
	make_settlement(gs, 1, 5, 5, 3)
	var w = make_unit(gs, "worker", 1, 5, 5)
	var facade = bare_facade(gs)
	gs.current_player_id = 1
	var ok: bool = facade.apply_command(Commands.build_improvement(1, w.id, "farm"))
	assert_false(ok, "Worker cannot build an improvement on a city/settlement tile")
	assert_eq(w.building_improvement, "", "No improvement should be queued on a settlement tile")

func test_worker_cannot_build_improvement_on_wrong_landform() -> void:
	var gs = make_gs(1)
	gs.get_player(1).technologies = gs.db.technologies.keys().duplicate()
	var w = make_unit(gs, "worker", 1, 5, 5)
	# Hills landform — farm requires flat.
	gs.map.get_tile(5, 5).terrain_id = "hills"
	var facade = bare_facade(gs)
	gs.current_player_id = 1
	var ok: bool = facade.apply_command(Commands.build_improvement(1, w.id, "farm"))
	assert_false(ok, "Worker should not build a farm on hills (wrong landform)")

func test_worker_cannot_build_improvement_without_tech() -> void:
	var gs = make_gs(1)
	# Player has no techs; mine requires mining.
	gs.get_player(1).technologies = []
	var w = make_unit(gs, "worker", 1, 5, 5)
	gs.map.get_tile(5, 5).terrain_id = "hills"
	var facade = bare_facade(gs)
	gs.current_player_id = 1
	var ok: bool = facade.apply_command(Commands.build_improvement(1, w.id, "mine"))
	assert_false(ok, "Worker should not build a mine without the mining tech")

func test_non_worker_cannot_build_improvement() -> void:
	var gs = make_gs(1)
	gs.get_player(1).technologies = gs.db.technologies.keys().duplicate()
	var warrior = make_warrior(gs, 1, 5, 5)
	gs.map.get_tile(5, 5).terrain_id = "grassland"
	var facade = bare_facade(gs)
	gs.current_player_id = 1
	var ok: bool = facade.apply_command(Commands.build_improvement(1, warrior.id, "farm"))
	assert_false(ok, "Warriors cannot build improvements")

func test_worker_can_build_mine_on_hills() -> void:
	var gs = make_gs(1)
	gs.get_player(1).technologies = gs.db.technologies.keys().duplicate()
	var w = make_unit(gs, "worker", 1, 5, 5)
	gs.map.get_tile(5, 5).terrain_id = "hills"
	var facade = bare_facade(gs)
	gs.current_player_id = 1
	var ok: bool = facade.apply_command(Commands.build_improvement(1, w.id, "mine"))
	assert_true(ok, "Worker can build a mine on hills")

func test_worker_cannot_build_mine_on_flat() -> void:
	# Mines are hills-only (reference convention). A flat tile (grassland/plains) must
	# reject a mine even with the mining tech.
	var gs = make_gs(1)
	gs.get_player(1).technologies = gs.db.technologies.keys().duplicate()
	var facade = bare_facade(gs)
	gs.current_player_id = 1
	var wg = make_unit(gs, "worker", 1, 5, 5)
	gs.map.get_tile(5, 5).terrain_id = "grassland"  # flat
	assert_false(facade.apply_command(Commands.build_improvement(1, wg.id, "mine")),
		"Worker should not build a mine on grassland (flat)")
	var wp = make_unit(gs, "worker", 1, 7, 7)
	gs.map.get_tile(7, 7).terrain_id = "plains"  # flat
	assert_false(facade.apply_command(Commands.build_improvement(1, wp.id, "mine")),
		"Worker should not build a mine on plains (flat)")

# ── Worker build completion (Jun 9 bug report) ───────────────────────────────

func test_worker_build_completes_and_places_improvement() -> void:
	var gs = make_gs(1)
	gs.get_player(1).treasury = 10000
	gs.get_player(1).technologies = gs.db.technologies.keys().duplicate()
	var w = make_unit(gs, "worker", 1, 5, 5)
	gs.map.get_tile(5, 5).terrain_id = "grassland"  # flat
	var facade = bare_facade(gs)
	gs.current_player_id = 1
	assert_true(facade.apply_command(Commands.build_improvement(1, w.id, "farm")),
		"Worker should start building a farm")
	var build_turns: int = w.build_turns_left
	assert_true(build_turns > 0, "Build should take a positive number of turns")
	# End turns until the build finishes (cap well above build_turns to avoid a
	# hang if completion never fires).
	for _i in range(build_turns + 3):
		if gs.map.get_tile(5, 5).improvement_id == "farm":
			break
		facade.apply_command(Commands.end_turn(1))
	assert_eq(gs.map.get_tile(5, 5).improvement_id, "farm",
		"Farm should be placed on the tile once the worker finishes building")
	assert_eq(w.building_improvement, "",
		"Build state should clear when the improvement completes")
	assert_eq(w.build_turns_left, 0,
		"build_turns_left should be 0 after completion")

# ── Forest/jungle clearing & chop (feature/worker-forest-clearing) ───────────
#
# Completing a non-preserving improvement on a forested/jungle tile strips the
# feature; a felled forest sends chop_yield (base 20) production to the nearest
# owned city — +50% with the chop tech (Mathematics), full inside the player's
# borders and half outside. These drive the completion helper directly to avoid
# the full end-turn pipeline consuming the delivered production.

func _complete_build(gs, w, imp_id) -> void:
	w.building_improvement = imp_id
	w.build_turns_left = 1
	TurnEngine._advance_worker_build(gs, w)

func test_chop_full_inside_borders() -> void:
	var gs = make_gs(1)
	var city = make_settlement(gs, 1, 5, 5, 3)
	var w = make_unit(gs, "worker", 1, 6, 5)
	var tile = gs.map.get_tile(6, 5)
	tile.terrain_id = "grassland"
	tile.feature_id = "forest"
	tile.owner_player_id = 1                           # inside the player's borders
	var before: int = city.production_store
	_complete_build(gs, w, "farm")
	assert_eq(tile.improvement_id, "farm", "Farm should be placed")
	assert_eq(tile.feature_id, "",
		"Forest is cleared when a non-preserving improvement completes")
	assert_eq(city.production_store - before, 20,
		"A forest inside borders delivers the full base yield (20)")

func test_chop_half_outside_borders() -> void:
	var gs = make_gs(1)
	var city = make_settlement(gs, 1, 5, 5, 3)
	var w = make_unit(gs, "worker", 1, 6, 5)
	var tile = gs.map.get_tile(6, 5)
	tile.terrain_id = "grassland"
	tile.feature_id = "forest"
	tile.owner_player_id = -1                          # unowned → outside borders
	var before: int = city.production_store
	_complete_build(gs, w, "farm")
	assert_eq(city.production_store - before, 10,
		"A forest outside borders delivers half the yield (10)")

func test_chop_tech_bonus_inside_borders() -> void:
	var gs = make_gs(1)
	gs.get_player(1).technologies = ["mathematics"]    # the chop tech
	var city = make_settlement(gs, 1, 5, 5, 3)
	var w = make_unit(gs, "worker", 1, 6, 5)
	var tile = gs.map.get_tile(6, 5)
	tile.terrain_id = "grassland"
	tile.feature_id = "forest"
	tile.owner_player_id = 1
	var before: int = city.production_store
	_complete_build(gs, w, "farm")
	# 20 +50% = 30, full inside borders.
	assert_eq(city.production_store - before, 30,
		"Mathematics raises the inside-borders chop to 30")

func test_chop_tech_bonus_outside_borders() -> void:
	var gs = make_gs(1)
	gs.get_player(1).technologies = ["mathematics"]
	var city = make_settlement(gs, 1, 5, 5, 3)
	var w = make_unit(gs, "worker", 1, 6, 5)
	var tile = gs.map.get_tile(6, 5)
	tile.terrain_id = "grassland"
	tile.feature_id = "forest"
	tile.owner_player_id = -1
	var before: int = city.production_store
	_complete_build(gs, w, "farm")
	# 20 +50% = 30, halved outside borders → 15.
	assert_eq(city.production_store - before, 15,
		"Mathematics then the outside-borders halving gives 15")

func test_nearest_city_receives_chop() -> void:
	var gs = make_gs(1)
	var far = make_settlement(gs, 1, 5, 5, 3)         # distance 4
	var near = make_settlement(gs, 1, 8, 5, 3)        # distance 1
	var w = make_unit(gs, "worker", 1, 9, 5)
	var tile = gs.map.get_tile(9, 5)
	tile.terrain_id = "grassland"
	tile.feature_id = "forest"
	tile.owner_player_id = 1
	var far_before: int = far.production_store
	var near_before: int = near.production_store
	_complete_build(gs, w, "farm")
	assert_eq(near.production_store - near_before, 20, "The nearer city receives the chop")
	assert_eq(far.production_store - far_before, 0, "The farther city receives nothing")

func test_camp_preserves_forest_and_gives_no_chop() -> void:
	var gs = make_gs(1)
	var city = make_settlement(gs, 1, 5, 5, 3)
	var w = make_unit(gs, "worker", 1, 6, 5)
	var tile = gs.map.get_tile(6, 5)
	tile.terrain_id = "grassland"
	tile.feature_id = "forest"
	tile.resource_id = "deer"                         # camp wants a resource
	var before: int = city.production_store
	_complete_build(gs, w, "camp")
	assert_eq(tile.feature_id, "forest",
		"A preserves_feature improvement (camp) keeps the forest")
	assert_eq(city.production_store - before, 0,
		"A preserved forest is not chopped")

func test_lumbermill_requires_and_keeps_forest() -> void:
	var gs = make_gs(1)
	var city = make_settlement(gs, 1, 5, 5, 3)
	var w = make_unit(gs, "worker", 1, 6, 5)
	var tile = gs.map.get_tile(6, 5)
	tile.terrain_id = "grassland"
	tile.feature_id = "forest"
	var before: int = city.production_store
	_complete_build(gs, w, "lumbermill")
	assert_eq(tile.feature_id, "forest",
		"A lumbermill keeps the forest it is built on")
	assert_eq(city.production_store - before, 0, "No chop for a preserved forest")

func test_clearing_jungle_yields_no_production() -> void:
	var gs = make_gs(1)
	var city = make_settlement(gs, 1, 5, 5, 3)
	var w = make_unit(gs, "worker", 1, 6, 5)
	var tile = gs.map.get_tile(6, 5)
	tile.terrain_id = "grassland"
	tile.feature_id = "jungle"
	var before: int = city.production_store
	_complete_build(gs, w, "farm")
	assert_eq(tile.feature_id, "",
		"Jungle is cleared by a non-preserving improvement")
	assert_eq(city.production_store - before, 0,
		"Jungle has no chop_yield, so clearing it delivers nothing")

func test_clearing_forest_without_owned_city_does_not_crash() -> void:
	var gs = make_gs(1)                                # no settlements at all
	var w = make_unit(gs, "worker", 1, 6, 5)
	var tile = gs.map.get_tile(6, 5)
	tile.terrain_id = "grassland"
	tile.feature_id = "forest"
	_complete_build(gs, w, "farm")
	assert_eq(tile.feature_id, "",
		"Forest is cleared even when the player has no city to receive the chop")

# ── Standalone chop/clear order (§4.11) ──────────────────────────────────────
#
# A worker can chop/clear a removable feature on its own, placing no improvement.
# The MISSION_CLEAR_FEATURE command sets clearing_feature + a timer; completion
# runs through TurnEngine._advance_worker_chop.

func _chop_done(gs, w, feat_id) -> void:
	w.clearing_feature = feat_id
	w.build_turns_left = 1
	TurnEngine._advance_worker_chop(gs, w)

func test_clear_feature_command_sets_timed_order() -> void:
	var gs = make_gs(1)
	var w = make_unit(gs, "worker", 1, 6, 5)
	var tile = gs.map.get_tile(6, 5)
	tile.terrain_id = "grassland"
	tile.feature_id = "forest"
	var facade = bare_facade(gs)
	gs.current_player_id = 1
	assert_true(facade.apply_command(Commands.mission_clear_feature(1, w.id)),
		"A worker on a removable feature accepts the chop order")
	assert_eq(w.clearing_feature, "forest", "The order records the feature being cleared")
	assert_eq(w.build_turns_left, 4, "Forest clear_turns (4) seeds the timer")
	assert_true(w.has_moved, "Issuing the order consumes the worker's turn")

func test_clear_feature_command_rejected_for_non_worker() -> void:
	var gs = make_gs(1)
	var warrior = make_unit(gs, "warrior", 1, 6, 5)
	gs.map.get_tile(6, 5).feature_id = "forest"
	var facade = bare_facade(gs)
	gs.current_player_id = 1
	assert_false(facade.apply_command(Commands.mission_clear_feature(1, warrior.id)),
		"A non-worker cannot chop")

func test_clear_feature_command_rejected_on_bare_tile() -> void:
	var gs = make_gs(1)
	var w = make_unit(gs, "worker", 1, 6, 5)
	gs.map.get_tile(6, 5).feature_id = ""             # nothing to clear
	var facade = bare_facade(gs)
	gs.current_player_id = 1
	assert_false(facade.apply_command(Commands.mission_clear_feature(1, w.id)),
		"A tile with no removable feature rejects the chop order")

func test_standalone_chop_clears_forest_and_chops_no_improvement() -> void:
	var gs = make_gs(1)
	var city = make_settlement(gs, 1, 5, 5, 3)
	var w = make_unit(gs, "worker", 1, 6, 5)
	var tile = gs.map.get_tile(6, 5)
	tile.terrain_id = "grassland"
	tile.feature_id = "forest"
	tile.owner_player_id = 1
	var before: int = city.production_store
	_chop_done(gs, w, "forest")
	assert_eq(tile.feature_id, "", "The chop fells the forest")
	assert_eq(tile.improvement_id, "", "A standalone chop places no improvement")
	assert_eq(city.production_store - before, 20,
		"The felled forest still delivers its chop yield")
	assert_eq(w.clearing_feature, "", "The chop order clears on completion")

func test_standalone_chop_jungle_yields_nothing() -> void:
	var gs = make_gs(1)
	var city = make_settlement(gs, 1, 5, 5, 3)
	var w = make_unit(gs, "worker", 1, 6, 5)
	var tile = gs.map.get_tile(6, 5)
	tile.terrain_id = "grassland"
	tile.feature_id = "jungle"
	tile.owner_player_id = 1
	var before: int = city.production_store
	_chop_done(gs, w, "jungle")
	assert_eq(tile.feature_id, "", "The chop clears the jungle")
	assert_eq(city.production_store - before, 0, "Jungle delivers no chop production")

func test_moving_cancels_a_chop_order() -> void:
	var gs = make_gs(1)
	gs.get_player(1).technologies = gs.db.technologies.keys().duplicate()
	var w = make_unit(gs, "worker", 1, 6, 5)
	var tile = gs.map.get_tile(6, 5)
	tile.terrain_id = "grassland"
	tile.feature_id = "forest"
	var facade = bare_facade(gs)
	gs.current_player_id = 1
	assert_true(facade.apply_command(Commands.mission_clear_feature(1, w.id)),
		"Chop order accepted")
	w.has_moved = false  # free the worker so it can be moved this test turn
	w.movement_left = w.movement_total
	facade.apply_command(Commands.mission_move_to(1, w.id, 7, 5))
	assert_eq(w.clearing_feature, "",
		"Walking away cancels the chop so it cannot complete on the wrong tile")
	assert_eq(gs.map.get_tile(6, 5).feature_id, "forest",
		"The abandoned forest is left standing")

func test_worker_makes_no_build_progress_on_the_issuing_turn() -> void:
	# On the turn the build is issued the worker has already acted (has_moved),
	# so the first end-turn must not decrement the build counter.
	var gs = make_gs(1)
	gs.get_player(1).treasury = 10000
	gs.get_player(1).technologies = gs.db.technologies.keys().duplicate()
	var w = make_unit(gs, "worker", 1, 5, 5)
	gs.map.get_tile(5, 5).terrain_id = "grassland"
	var facade = bare_facade(gs)
	gs.current_player_id = 1
	facade.apply_command(Commands.build_improvement(1, w.id, "farm"))
	var before: int = w.build_turns_left
	facade.apply_command(Commands.end_turn(1))  # issuing turn — no progress yet
	assert_eq(w.build_turns_left, before,
		"No build progress should be made on the turn the order was issued")
	facade.apply_command(Commands.end_turn(1))  # held the tile — now progresses
	assert_eq(w.build_turns_left, before - 1,
		"Build should advance by one on a turn the worker holds its tile")

func test_moving_a_building_worker_cancels_the_build() -> void:
	# A worker that walks away mid-build must abandon the build, so it cannot
	# complete the improvement on whatever tile it ends up on.
	var gs = make_gs(1)
	gs.get_player(1).treasury = 10000
	gs.get_player(1).technologies = gs.db.technologies.keys().duplicate()
	for tile in gs.map.all_tiles():
		tile.terrain_id = "grassland"
	var w = make_unit(gs, "worker", 1, 5, 5)
	var facade = bare_facade(gs)
	gs.current_player_id = 1
	facade.apply_command(Commands.build_improvement(1, w.id, "farm"))
	assert_eq(w.building_improvement, "farm", "Build should be in progress")
	# Refresh movement (the build consumed it) and move the worker one tile.
	w.movement_left = w.movement_total
	w.has_moved = false
	facade.apply_command(Commands.mission_move_to(1, w.id, 6, 5))
	assert_eq(w.building_improvement, "",
		"Moving must cancel the in-progress build")
	assert_eq(w.build_turns_left, 0,
		"build_turns_left must reset when the build is cancelled by movement")

func test_building_worker_not_flagged_idle() -> void:
	var gs = make_gs(1)
	gs.get_player(1).treasury = 10000
	gs.get_player(1).technologies = gs.db.technologies.keys().duplicate()
	var w = make_unit(gs, "worker", 1, 5, 5)
	gs.map.get_tile(5, 5).terrain_id = "grassland"
	var facade = bare_facade(gs)
	gs.current_player_id = 1
	facade.apply_command(Commands.build_improvement(1, w.id, "farm"))
	# Advance one full turn so has_moved is reset; the worker is still building.
	facade.apply_command(Commands.end_turn(1))
	assert_true(w.building_improvement != "",
		"Worker should still be building after the turn rolls over")
	assert_true(facade.get_end_turn_state() != 2,
		"A worker mid-build must not raise the idle-units end-turn prompt")

# ── Worker resource-gating (Jun 9 bug report) ────────────────────────────────

func test_resource_improvement_rejected_without_resource() -> void:
	# A pasture is resource-bound: it must not be buildable on a bare grassland
	# tile even when the player holds every technology.
	var gs = make_gs(1)
	gs.get_player(1).technologies = gs.db.technologies.keys().duplicate()
	var w = make_unit(gs, "worker", 1, 5, 5)
	gs.map.get_tile(5, 5).terrain_id = "grassland"
	gs.map.get_tile(5, 5).resource_id = ""
	var facade = bare_facade(gs)
	gs.current_player_id = 1
	assert_false(facade.apply_command(Commands.build_improvement(1, w.id, "pasture")),
		"Pasture must be rejected on a tile with no matching resource")

func test_resource_improvement_accepted_with_visible_resource() -> void:
	var gs = make_gs(1)
	gs.get_player(1).technologies = ["animal_husbandry"]  # builds pasture + reveals cow
	var w = make_unit(gs, "worker", 1, 5, 5)
	var t = gs.map.get_tile(5, 5)
	t.terrain_id = "grassland"
	t.resource_id = "cow"  # cow.improvement_required == pasture
	var facade = bare_facade(gs)
	gs.current_player_id = 1
	assert_true(facade.apply_command(Commands.build_improvement(1, w.id, "pasture")),
		"Pasture must be buildable on a visible cow resource")

func test_resource_improvement_rejected_when_resource_not_yet_visible() -> void:
	# Whale's reveal tech (sailing) differs from whaling_boats' build tech
	# (compass). With compass but not sailing the resource is hidden, so the
	# improvement is not offered; granting sailing reveals it and unblocks.
	var gs = make_gs(1)
	gs.get_player(1).technologies = ["compass"]  # can build whaling_boats; whale hidden
	var w = make_unit(gs, "work_boat", 1, 5, 5)
	var t = gs.map.get_tile(5, 5)
	t.terrain_id = "coast"  # water landform
	t.resource_id = "whale"
	var facade = bare_facade(gs)
	gs.current_player_id = 1
	assert_false(facade.apply_command(Commands.build_improvement(1, w.id, "whaling_boats")),
		"Whaling boats must be blocked while the whale resource is not yet visible")
	gs.get_player(1).technologies.append("sailing")  # whale now revealed
	assert_true(facade.apply_command(Commands.build_improvement(1, w.id, "whaling_boats")),
		"Whaling boats must be allowed once the whale resource is visible")

func test_generic_improvement_still_allowed_without_resource() -> void:
	# Regression guard: farm/mine are NOT resource-bound and must remain buildable
	# on bare tiles given the right landform and tech.
	var gs = make_gs(1)
	gs.get_player(1).technologies = gs.db.technologies.keys().duplicate()
	var w = make_unit(gs, "worker", 1, 5, 5)
	gs.map.get_tile(5, 5).terrain_id = "grassland"
	gs.map.get_tile(5, 5).resource_id = ""
	var facade = bare_facade(gs)
	gs.current_player_id = 1
	assert_true(facade.apply_command(Commands.build_improvement(1, w.id, "farm")),
		"Farm (generic) must still build on a bare grassland tile")

# ── Work boat: Fishing Boats improvement ─────────────────────────────────────
#
# The naval "work boat" (domain sea) builds the "Fishing Boats" sea-resource
# improvement in a single turn, may dock in its own coastal city, but offers no
# build action while sitting on that city tile.

func test_fishing_boats_improvement_is_named_fishing_boats() -> void:
	var gs = make_gs(1)
	var imp: Dictionary = gs.db.get_improvement("fishing_boats")
	assert_eq(str(imp.get("name", "")), "Fishing Boats",
		"The sea-resource improvement must display as 'Fishing Boats'")
	# The work-boat build action label is generated as "Build " + improvement name,
	# so a correct name yields the correct button text.
	assert_eq("Build " + str(imp.get("name", "")), "Build Fishing Boats",
		"Work boat build action must read 'Build Fishing Boats'")

func test_work_boat_builds_fishing_boats_on_sea_resource() -> void:
	var gs = make_gs(1)
	gs.get_player(1).technologies = ["fishing"]  # reveals fish; unlocks fishing_boats
	var w = make_unit(gs, "work_boat", 1, 5, 5)
	var t = gs.map.get_tile(5, 5)
	t.terrain_id = "coast"   # water landform
	t.resource_id = "fish"
	var facade = bare_facade(gs)
	gs.current_player_id = 1
	var wid: int = w.id
	assert_true(facade.apply_command(Commands.build_improvement(1, w.id, "fishing_boats")),
		"Work boat must build Fishing Boats on a coastal fish tile")
	# Issue 2: a work boat finishes its improvement INSTANTLY — the boat is consumed
	# the same turn, so building_improvement is never left mid-build on it.
	assert_eq(t.improvement_id, "fishing_boats",
		"Fishing Boats is placed on the tile the same turn the command is issued")
	assert_null(gs.get_unit(wid),
		"The work boat is consumed instantly (no lingering mid-build unit)")

func test_fishing_boats_completes_instantly() -> void:
	var gs = make_gs(1)
	gs.get_player(1).technologies = ["fishing"]
	var w = make_unit(gs, "work_boat", 1, 5, 5)
	var t = gs.map.get_tile(5, 5)
	t.terrain_id = "coast"
	t.resource_id = "fish"
	var facade = bare_facade(gs)
	gs.current_player_id = 1
	# Issue 2: no end-turn needed — the improvement appears and the boat is gone
	# the moment the build command is processed.
	assert_true(facade.apply_command(Commands.build_improvement(1, w.id, "fishing_boats")),
		"Work boat builds Fishing Boats")
	assert_eq(t.improvement_id, "fishing_boats",
		"Fishing Boats must be on the tile immediately (no end-turn)")
	assert_eq(gs.units.size(), 0,
		"The single-use work boat is removed the same turn it builds")

# ── Fix 1: a work boat is consumed when its improvement completes ────────────
#
# The work boat is a single-use builder (data flag `consumed_on_use` on the unit
# in units.json): unlike a land worker it is removed from state when the
# improvement it is building completes. Drives the completion helper directly.

func test_work_boat_consumed_when_improvement_completes() -> void:
	var gs = make_gs(1)
	var w = make_unit(gs, "work_boat", 1, 5, 5)
	var t = gs.map.get_tile(5, 5)
	t.terrain_id = "coast"
	var wid: int = w.id
	_complete_build(gs, w, "fishing_boats")
	assert_eq(t.improvement_id, "fishing_boats",
		"The fishing boats improvement is placed when the build completes")
	assert_null(gs.get_unit(wid),
		"A work boat (consumed_on_use) is removed from state when its build completes")
	assert_eq(gs.units.size(), 0,
		"No units remain after the single-use work boat is consumed")

func test_land_worker_persists_when_improvement_completes() -> void:
	# Regression guard: a normal worker has no consumed_on_use flag and must NOT be
	# removed when its improvement finishes — it survives to improve more tiles.
	var gs = make_gs(1)
	var w = make_unit(gs, "worker", 1, 5, 5)
	gs.map.get_tile(5, 5).terrain_id = "grassland"
	var wid: int = w.id
	_complete_build(gs, w, "farm")
	assert_eq(gs.map.get_tile(5, 5).improvement_id, "farm",
		"The farm is placed when the worker finishes")
	assert_not_null(gs.get_unit(wid),
		"A normal worker persists after completing an improvement (not consumed)")

func test_work_boat_data_has_consumed_on_use_flag() -> void:
	var gs = make_gs(1)
	var tags: Array = gs.db.get_unit("work_boat").get("tags", [])
	assert_true("consumed_on_use" in tags,
		"The work boat unit must carry the consumed_on_use tag (single-use builder)")
	var wtags: Array = gs.db.get_unit("worker").get("tags", [])
	assert_false("consumed_on_use" in wtags,
		"A normal worker must NOT carry consumed_on_use (it persists)")

# ── Fix 2: a cottage may not be built on a zero-food tile (desert) ───────────
#
# A cottage models a working settlement and needs a tile that can feed it: the
# improvement carries `requires_food: true` in improvements.json and is rejected
# on any tile whose terrain base food yield is 0 (desert, snow). Other
# improvements (no requires_food flag) are unaffected.

func test_cottage_rejected_on_desert() -> void:
	var gs = make_gs(1)
	gs.get_player(1).technologies = gs.db.technologies.keys().duplicate()
	var w = make_unit(gs, "worker", 1, 5, 5)
	gs.map.get_tile(5, 5).terrain_id = "desert"  # flat landform, 0 base food
	var facade = bare_facade(gs)
	gs.current_player_id = 1
	assert_false(facade.can_build_improvement(1, w.id, "cottage"),
		"can_build_improvement must reject a cottage on a zero-food desert tile")
	assert_false(facade.apply_command(Commands.build_improvement(1, w.id, "cottage")),
		"The build command must also reject a cottage on desert")
	assert_eq(w.building_improvement, "",
		"No cottage build should be queued on a desert tile")

func test_cottage_accepted_on_grassland() -> void:
	var gs = make_gs(1)
	gs.get_player(1).technologies = gs.db.technologies.keys().duplicate()
	var w = make_unit(gs, "worker", 1, 5, 5)
	gs.map.get_tile(5, 5).terrain_id = "grassland"  # flat, 2 base food
	var facade = bare_facade(gs)
	gs.current_player_id = 1
	assert_true(facade.can_build_improvement(1, w.id, "cottage"),
		"can_build_improvement must accept a cottage on a food-bearing grassland tile")
	assert_true(facade.apply_command(Commands.build_improvement(1, w.id, "cottage")),
		"The build command must accept a cottage on grassland")

func test_non_cottage_improvement_unaffected_on_desert() -> void:
	# A mine has no requires_food flag, so the food gate must not touch it. Mines are
	# hills-only though, so use a farm on a flat zero-food tile would be wrong (farm
	# would still place); instead confirm a road (flat, no food req) builds on desert.
	var gs = make_gs(1)
	gs.get_player(1).technologies = gs.db.technologies.keys().duplicate()
	var w = make_unit(gs, "worker", 1, 5, 5)
	gs.map.get_tile(5, 5).terrain_id = "desert"  # flat, 0 base food
	var facade = bare_facade(gs)
	gs.current_player_id = 1
	assert_true(facade.can_build_improvement(1, w.id, "road"),
		"A road (no requires_food) must still be buildable on desert")

func test_cottage_data_has_requires_food_flag() -> void:
	var gs = make_gs(1)
	assert_true(bool(gs.db.get_improvement("cottage").get("requires_food", false)),
		"The cottage improvement must carry requires_food: true")
	assert_false(bool(gs.db.get_improvement("farm").get("requires_food", false)),
		"A farm must NOT carry requires_food (defaults off)")

func test_work_boat_cannot_build_on_own_city_tile() -> void:
	# A work boat docked in its own coastal city offers no improvement: the city
	# centre cannot be improved. Sim rejects the command (the HUD also hides it).
	var gs = make_gs(1)
	gs.get_player(1).technologies = ["fishing"]
	var t = gs.map.get_tile(5, 5)
	t.terrain_id = "coast"
	t.resource_id = "fish"
	make_settlement(gs, 1, 5, 5, 3)         # own city on the work boat's tile
	var w = make_unit(gs, "work_boat", 1, 5, 5)
	var facade = bare_facade(gs)
	gs.current_player_id = 1
	assert_false(facade.apply_command(Commands.build_improvement(1, w.id, "fishing_boats")),
		"Work boat cannot improve its own city tile")
	assert_eq(w.building_improvement, "",
		"No improvement should be queued on a city tile")

func test_work_boat_can_enter_own_coastal_city_tile() -> void:
	# A coastal city sits on a LAND tile; a sea unit may still dock there (harbour).
	var gs = make_gs(1)
	gs.map.get_tile(5, 5).terrain_id = "coast"          # work boat's start (sea)
	var city_tile = gs.map.get_tile(6, 5)
	city_tile.terrain_id = "grassland"                  # land city centre
	city_tile.owner_player_id = 1
	make_settlement(gs, 1, 6, 5, 3)
	var w = make_unit(gs, "work_boat", 1, 5, 5)
	var facade = bare_facade(gs)
	gs.current_player_id = 1
	facade._selection = load("res://src/api/selection_state.gd").new()
	assert_true(facade.can_stack_move(5, 5, 6, 5, [w.id]),
		"Work boat must be able to move into its own coastal city's land tile")

func test_work_boat_cannot_enter_foreign_land_tile() -> void:
	# Regression guard: the harbour waiver is for friendly cities only — a plain
	# land tile (and a foreign city) stays impassable to a sea unit.
	var gs = make_gs(2)
	gs.map.get_tile(5, 5).terrain_id = "coast"
	gs.map.get_tile(6, 5).terrain_id = "grassland"      # bare land, no city
	var foe_tile = gs.map.get_tile(5, 6)
	foe_tile.terrain_id = "grassland"
	foe_tile.owner_player_id = 2
	make_settlement(gs, 2, 5, 6, 3)                     # a rival's city
	var w = make_unit(gs, "work_boat", 1, 5, 5)
	var facade = bare_facade(gs)
	gs.current_player_id = 1
	facade._selection = load("res://src/api/selection_state.gd").new()
	assert_false(facade.can_stack_move(5, 5, 6, 5, [w.id]),
		"Work boat must not walk onto bare land")
	assert_false(facade.can_stack_move(5, 5, 5, 6, [w.id]),
		"Work boat must not dock in a foreign city")

# ── Issue 13: Scout Explore mission ──────────────────────────────────────────

func test_explore_command_accepted_for_scout() -> void:
	var gs = make_gs(1)
	var scout = make_unit(gs, "scout", 1, 5, 5)
	var facade = bare_facade(gs)
	gs.current_player_id = 1
	var ok: bool = facade.apply_command(Commands.mission_explore(1, scout.id))
	assert_true(ok, "MISSION_EXPLORE should be accepted for a scout")
	assert_true(scout.is_exploring, "Scout should have is_exploring set after explore command")

# Issue 6: every combat unit (non-civilian with base_strength > 0) may explore,
# not just recon/scout. A plain warrior is now accepted.
func test_explore_command_accepted_for_warrior() -> void:
	var gs = make_gs(1)
	var warrior = make_warrior(gs, 1, 5, 5)
	var facade = bare_facade(gs)
	gs.current_player_id = 1
	var ok: bool = facade.apply_command(Commands.mission_explore(1, warrior.id))
	assert_true(ok, "MISSION_EXPLORE is accepted for a plain combat unit (warrior)")
	assert_true(warrior.is_exploring, "Warrior should have is_exploring set after explore command")

# Civilians (base_strength 0) remain rejected — they are not combat units.
func test_explore_command_rejected_for_civilian() -> void:
	var gs = make_gs(1)
	var worker = make_unit(gs, "worker", 1, 5, 5)
	var facade = bare_facade(gs)
	gs.current_player_id = 1
	var ok: bool = facade.apply_command(Commands.mission_explore(1, worker.id))
	assert_false(ok, "MISSION_EXPLORE must be rejected for a civilian unit")
	assert_false(worker.is_exploring, "Worker should not have is_exploring set")

func test_exploring_scout_skipped_by_idle_cycle() -> void:
	var gs = make_gs(1)
	var scout = make_unit(gs, "scout", 1, 5, 5)
	scout.is_exploring = true
	var facade = bare_facade(gs)
	facade._selection = load("res://src/api/selection_state.gd").new()
	gs.current_player_id = 1
	facade.cycle_idle_units(false)
	assert_true(facade.get_selection().head_unit() < 0,
		"An exploring scout must not be surfaced by idle-unit cycling")

func test_exploring_scout_does_not_block_end_turn() -> void:
	var gs = make_gs(1)
	var scout = make_unit(gs, "scout", 1, 5, 5)
	scout.is_exploring = true
	var facade = bare_facade(gs)
	gs.current_player_id = 1
	var state: int = facade.get_end_turn_state()
	assert_true(state != 2,
		"An exploring scout should not trigger the idle-units warning for end turn")

func test_unit_wake_cancels_explore() -> void:
	var gs = make_gs(1)
	gs.get_player(1).treasury = 10000
	var scout = make_unit(gs, "scout", 1, 5, 5)
	scout.is_exploring = true
	var facade = bare_facade(gs)
	gs.current_player_id = 1
	facade.apply_command(Commands.unit_wake(1, scout.id))
	assert_false(scout.is_exploring, "UNIT_WAKE should cancel the explore mission")

func test_explore_mission_moves_scout() -> void:
	# Place a scout on an open grassland map and set it exploring; end the turn;
	# the scout should have moved from its starting position.
	var gs = make_gs(1)
	gs.get_player(1).treasury = 10000
	for tile in gs.map.all_tiles():
		tile.terrain_id = "grassland"
	var scout = make_unit(gs, "scout", 1, 5, 5)
	scout.is_exploring = true
	var start_x: int = scout.x
	var start_y: int = scout.y
	var facade = bare_facade(gs)
	gs.current_player_id = 1
	facade.apply_command(Commands.end_turn(1))
	# The scout should have moved at least one step.
	var moved: bool = (scout.x != start_x or scout.y != start_y)
	assert_true(moved, "An exploring scout should move when the turn ends")

func test_explore_wakes_on_enemy_nearby() -> void:
	# Place a scout exploring; put an enemy warrior adjacent to it.
	# When the turn ends the scout should wake (is_exploring cleared) and a
	# notification should have been added.
	var gs = make_gs(2)
	gs.get_player(1).treasury = 10000
	gs.get_player(2).treasury = 10000
	for tile in gs.map.all_tiles():
		tile.terrain_id = "grassland"
	# Declare war so the enemy is treated as hostile.
	gs.alliances[0].at_war_with.append(2)
	gs.alliances[1].at_war_with.append(1)
	var scout = make_unit(gs, "scout", 1, 5, 5)
	scout.is_exploring = true
	# Enemy unit within sight range (unit_sight default = 2).
	make_warrior(gs, 2, 6, 5)
	var facade = bare_facade(gs)
	gs.current_player_id = 1
	facade.apply_command(Commands.end_turn(1))
	assert_false(scout.is_exploring,
		"Scout should stop exploring when an enemy is spotted within sight range")

func test_explore_steps_toward_unexplored_map() -> void:
	# A scout in the middle of a large all-grassland map starts with most of the
	# map in fog. Each explore step should carry it steadily AWAY from its start
	# (into the fog), not wander back into the small revealed pocket it already
	# sees. End several turns and assert its distance from the start keeps growing.
	var gs = make_gs(1, 42, 30, 30)
	gs.get_player(1).treasury = 100000
	for tile in gs.map.all_tiles():
		tile.terrain_id = "grassland"
	var scout = make_unit(gs, "scout", 1, 15, 15)
	scout.is_exploring = true
	var facade = bare_facade(gs)
	gs.current_player_id = 1
	# Several explore turns; the distance from the start should climb monotonically
	# while the scout is heading outward (a committed heading does not backtrack).
	var prev_dist: int = 0
	for _i in range(4):
		facade.apply_command(Commands.end_turn(1))
		if not scout.is_exploring:
			break
		var d: int = gs.map.distance(scout.x, scout.y, 15, 15)
		assert_true(d > prev_dist,
			"Each explore turn should move the scout farther from its start (into fog)")
		prev_dist = d
	assert_true(prev_dist >= 3,
		"An exploring scout should head well clear of its start into the fog")

func test_explore_stops_when_all_reachable_revealed() -> void:
	# A scout alone on a small island whose every land tile is already inside its
	# sight has no reachable unseen LAND tile (the surrounding ocean is illegal for
	# a land scout), so explore should stop (idle) rather than thrash. Carve a 3x3
	# grassland island at the map centre, ocean everywhere else.
	var gs = make_gs(1, 42, 12, 12)
	for tile in gs.map.all_tiles():
		tile.terrain_id = "ocean"
	for dy in range(-1, 2):
		for dx in range(-1, 2):
			gs.map.get_tile(6 + dx, 6 + dy).terrain_id = "grassland"
	var scout = make_unit(gs, "scout", 1, 6, 6)
	scout.is_exploring = true
	var facade = bare_facade(gs)
	gs.current_player_id = 1
	facade._explore_step(scout)
	assert_false(scout.is_exploring,
		"With every reachable land tile revealed, the scout should stop exploring")

func test_explore_does_not_oscillate_along_coastline() -> void:
	# Regression (pt-b-11.sav: the easternmost scout oscillated near a coastline).
	# A land scout walking a shore where the only nearby unseen tiles lie across the
	# water (unreachable) used to ping-pong between two coastal tiles forever because
	# the per-neighbour reveal+heading tiebreak had no sense of which way the
	# REACHABLE frontier lay. The coast-trap guard now steers it toward the BFS
	# frontier tile, so it makes steady progress and never revisits a tile.
	#
	# Map: a single land row (y = 5) across an otherwise-ocean map. The scout starts
	# at the west end; the only reachable unexplored LAND is further east along the
	# strip. Every step must advance east and never return to a visited tile.
	var gs = make_gs(1, 42, 30, 12)
	gs.get_player(1).treasury = 100000
	for tile in gs.map.all_tiles():
		tile.terrain_id = "ocean"
	for x in range(0, 30):
		gs.map.get_tile(x, 5).terrain_id = "grassland"
	var scout = make_unit(gs, "scout", 1, 2, 5)
	scout.is_exploring = true
	var facade = bare_facade(gs)
	gs.current_player_id = 1
	var visited: Dictionary = {str(scout.x) + "," + str(scout.y): true}
	var max_x: int = scout.x
	for _i in range(12):
		scout.movement_left = scout.movement_total
		scout.has_moved = false
		if not scout.is_exploring:
			break
		facade._explore_step(scout)
		var key: String = str(scout.x) + "," + str(scout.y)
		# Never step back onto a tile already visited this run (no oscillation).
		assert_false(visited.has(key),
			"Exploring scout must not revisit a tile (no coastline oscillation)")
		visited[key] = true
		if scout.x > max_x:
			max_x = scout.x
	assert_true(max_x >= 6,
		"Exploring scout should make steady progress east along the coast")

func test_explore_uses_no_private_rng_state() -> void:
	# The targeting is deterministic and draws no RNG: an explore step must not
	# advance the shared RNG state (unlike the old random-neighbour pick).
	var gs = make_gs(1, 42, 30, 30)
	gs.get_player(1).treasury = 100000
	for tile in gs.map.all_tiles():
		tile.terrain_id = "grassland"
	var scout = make_unit(gs, "scout", 1, 15, 15)
	scout.is_exploring = true
	var facade = bare_facade(gs)
	gs.current_player_id = 1
	var rng_before: Dictionary = gs.rng.get_state()
	facade._explore_step(scout)
	var rng_after: Dictionary = gs.rng.get_state()
	assert_eq(str(rng_before["state"]), str(rng_after["state"]),
		"Explore targeting must be deterministic and draw nothing from the shared RNG")

func test_explore_heading_serializes_and_deserializes() -> void:
	# The committed explore heading is serialized so an explore turn survives a
	# save/load (the determinism gate).
	var gs = make_gs(1)
	var scout = make_unit(gs, "scout", 1, 5, 5)
	scout.is_exploring = true
	scout.explore_dx = -1
	scout.explore_dy = 1
	var d: Dictionary = scout.serialize()
	var u2 = load("res://src/sim/unit.gd").deserialize(d)
	assert_eq(u2.explore_dx, -1, "deserialize() must restore explore_dx")
	assert_eq(u2.explore_dy, 1, "deserialize() must restore explore_dy")

func test_explore_serializes_and_deserializes() -> void:
	var gs = make_gs(1)
	var scout = make_unit(gs, "scout", 1, 5, 5)
	scout.is_exploring = true
	var d: Dictionary = scout.serialize()
	assert_true(bool(d.get("is_exploring", false)),
		"serialize() must include is_exploring = true")
	var u2 = load("res://src/sim/unit.gd").deserialize(d)
	assert_true(u2.is_exploring,
		"deserialize() must restore is_exploring from the save dict")

# ── Issue 2: Instantaneous work-boat improvements ────────────────────────────
#
# A work boat (domain sea, tag consumed_on_use) places its sea improvement the
# moment the build command is issued — in the SAME turn, no end-turn — and the
# boat is removed from state immediately, never lingering. Land workers keep
# their multi-turn build (guarded below).

func _sea_resource_tile(gs, x, y) -> void:
	# A coastal tile carrying a fish resource: fishing_boats is buildable (water
	# landform, fishing tech, the resource the improvement requires).
	var t = gs.map.get_tile(x, y)
	t.terrain_id = "coast"
	t.resource_id = "fish"

func test_work_boat_build_is_instant_and_consumes_boat() -> void:
	var gs = make_gs(1)
	gs.get_player(1).treasury = 10000
	gs.get_player(1).technologies = gs.db.technologies.keys().duplicate()
	var wb = make_unit(gs, "work_boat", 1, 5, 5)
	var wb_id: int = wb.id
	_sea_resource_tile(gs, 5, 5)
	var facade = bare_facade(gs)
	gs.current_player_id = 1
	var ok: bool = facade.apply_command(Commands.build_improvement(1, wb_id, "fishing_boats"))
	assert_true(ok, "Work boat should be able to build fishing boats on a fish tile")
	# (1) Improvement is on the tile IMMEDIATELY — no end-turn was issued.
	assert_eq(gs.map.get_tile(5, 5).improvement_id, "fishing_boats",
		"Fishing boats must be placed instantly in the same turn the command is issued")
	# (2) The work boat is gone from gs.units immediately (consumed_on_use).
	assert_null(gs.get_unit(wb_id),
		"The work boat must be removed from gs.units the same turn it builds")

func test_work_boat_clears_selection_on_consume() -> void:
	# The consumed boat must not linger as a ghost selection in the UI.
	var gs = make_gs(1)
	gs.get_player(1).treasury = 10000
	gs.get_player(1).technologies = gs.db.technologies.keys().duplicate()
	var wb = make_unit(gs, "work_boat", 1, 5, 5)
	_sea_resource_tile(gs, 5, 5)
	var facade = bare_facade(gs)
	# bare_facade omits the selection state; install one so the consume path can
	# clear the boat from the active selection.
	facade._selection = load("res://src/api/selection_state.gd").new()
	gs.current_player_id = 1
	# Select the work boat first, then build.
	facade.select_unit(wb.id)
	assert_eq(facade.get_selection().selected_unit_ids.size(), 1, "Work boat should be selected before build")
	assert_true(facade.apply_command(Commands.build_improvement(1, wb.id, "fishing_boats")),
		"Work boat build should succeed")
	assert_eq(facade.get_selection().selected_unit_ids.size(), 0,
		"The consumed work boat must be dropped from the selection")

func test_land_worker_build_still_takes_multiple_turns() -> void:
	# Guard against over-generalizing: a land worker (no consumed_on_use) keeps its
	# multi-turn build — the improvement is NOT placed instantly and the worker
	# survives the command.
	var gs = make_gs(1)
	gs.get_player(1).treasury = 10000
	gs.get_player(1).technologies = gs.db.technologies.keys().duplicate()
	var w = make_unit(gs, "worker", 1, 5, 5)
	gs.map.get_tile(5, 5).terrain_id = "grassland"  # flat
	var facade = bare_facade(gs)
	gs.current_player_id = 1
	assert_true(facade.apply_command(Commands.build_improvement(1, w.id, "farm")),
		"Worker should start building a farm")
	assert_true(w.build_turns_left > 0,
		"Land worker keeps a positive multi-turn build (not instant)")
	assert_eq(gs.map.get_tile(5, 5).improvement_id, "",
		"Farm must NOT be on the tile yet — the land worker build is multi-turn")
	assert_eq(w.building_improvement, "farm",
		"Land worker is still mid-build, not consumed")
	assert_not_null(gs.get_unit(w.id), "Land worker must survive the build command")
