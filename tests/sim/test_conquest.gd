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

# City conquest (§4.8): an undefended enemy city falls to a single attack by a
# player — the attacker keeps it (in revolt) or razes it, with barbarian / size-1
# auto-raze rules. Defending units must be cleared by normal combat first. Players
# may also disband their own cities at any time. (Siege HP / city_max_health is now
# dormant — neither the player nor the wild path grinds it down — but the function
# is still exercised below since the field remains serialized state.)

func _at_war(gs):
	gs.alliances[0].at_war_with = [2]
	gs.alliances[1].at_war_with = [1]

func test_city_max_health_grows_with_size_and_walls() -> void:
	var gs = make_gs(1)
	var s = make_settlement(gs, 1, 5, 5, 1)
	var base = TurnEngine.city_max_health(s, gs.db)
	s.population = 5
	assert_true(TurnEngine.city_max_health(s, gs.db) > base, "Bigger cities are tougher")
	var with_pop = TurnEngine.city_max_health(s, gs.db)
	s.structures.append("walls")
	assert_true(TurnEngine.city_max_health(s, gs.db) > with_pop, "Walls raise siege HP")

# ── Assault through the move command ──────────────────────────────────────────

func test_undefended_city_is_captured_by_a_single_attack() -> void:
	# §4.8: with no defender left, even a weak attacker takes the city outright.
	var gs = make_gs(2)
	_at_war(gs)
	var city = make_settlement(gs, 2, 5, 5, 4)   # defenderless enemy city, size 4
	city.peak_population = 4
	var atk = make_warrior(gs, 1, 5, 6)          # base_strength 10 — still enough
	var f = bare_facade(gs)
	gs.current_player_id = 1

	f.apply_command(Commands.move_stack(1, 5, 6, 5, 5))
	assert_eq(city.owner_player_id, 1, "An undefended city is captured at once")
	assert_eq(city.revolt_turns, gs.db.get_constant("revolt_base_turns", 3) + 4 / 2,
		"Kept cities revolt for the base turns plus half their size")
	assert_eq([atk.x, atk.y], [5, 5], "The attacker advances into the captured city")

func test_defended_city_must_clear_its_defender_first() -> void:
	# A defender blocks capture: attacking the tile fights the defender (normal
	# combat) and does NOT seize the city in the same step, even if the defender dies.
	var gs = make_gs(2)
	_at_war(gs)
	var city = make_settlement(gs, 2, 5, 5, 4)
	city.peak_population = 4
	var guard = make_warrior(gs, 2, 5, 5)        # defender stationed in the city
	var atk = make_warrior(gs, 1, 5, 6)
	atk.base_strength = 100                      # will win the fight handily
	var f = bare_facade(gs)
	gs.current_player_id = 1

	f.apply_command(Commands.move_stack(1, 5, 6, 5, 5))
	assert_eq(city.owner_player_id, 2, "The city is not seized in the same step as the fight")
	assert_eq([atk.x, atk.y], [5, 6], "Beating the defender does not walk the attacker in")

# ── Fall outcomes (raze vs keep) ──────────────────────────────────────────────

func test_capture_clears_palace_and_sets_revolt() -> void:
	var gs = make_gs(2)
	var city = make_settlement(gs, 2, 5, 5, 4)
	city.peak_population = 4
	city.structures.append("palace")
	var f = bare_facade(gs)
	f._capture_city(city, 1)
	assert_eq(city.owner_player_id, 1, "Ownership transfers to the captor")
	assert_false(city.has_structure("palace"), "The loser's Palace is stripped on capture")
	assert_true(city.revolt_turns > 0, "The kept city is in revolt")
	assert_eq(city.health, TurnEngine.city_max_health(city, gs.db), "HP is restored on capture")

func test_barbarians_always_raze() -> void:
	var gs = make_gs(2)
	var city = make_settlement(gs, 2, 5, 5, 5)   # large, would normally be kept
	city.peak_population = 5
	var f = bare_facade(gs)
	assert_eq(f._city_falls(city, -2), "razed", "A barbarian captor razes any city")
	assert_eq(gs.get_settlement_at(5, 5), null, "…and the city is gone")

func test_size_one_never_larger_is_auto_razed() -> void:
	var gs = make_gs(2)
	var city = make_settlement(gs, 2, 5, 5, 1)
	city.peak_population = 1
	var f = bare_facade(gs)
	assert_eq(f._city_falls(city, 1), "razed",
		"A size-1 city that was never larger is razed automatically")

func test_size_one_previously_larger_can_be_kept() -> void:
	var gs = make_gs(2)
	var city = make_settlement(gs, 2, 5, 5, 1)
	city.peak_population = 3                       # it used to be bigger
	var f = bare_facade(gs)
	assert_eq(f._city_falls(city, 1), "captured",
		"A shrunken city (peak > 1) is kept, not auto-razed")

# ── Voluntary disband (raze any time) ─────────────────────────────────────────

func test_disband_razes_own_city() -> void:
	var gs = make_gs(1)
	gs.current_player_id = 1
	var city = make_settlement(gs, 1, 5, 5, 3)
	var f = bare_facade(gs)
	assert_true(f.apply_command(Commands.disband_city(1, city.id)), "Disband accepted")
	assert_eq(gs.get_settlement_at(5, 5), null, "Disbanding razes the city")

func test_cannot_disband_someone_elses_city() -> void:
	var gs = make_gs(2)
	gs.current_player_id = 1
	var city = make_settlement(gs, 2, 5, 5, 3)
	var f = bare_facade(gs)
	assert_false(f.apply_command(Commands.disband_city(1, city.id)),
		"A player cannot disband a city they do not own")
	assert_eq(gs.get_settlement_at(5, 5).id, city.id, "…and the city survives")

func test_cannot_disband_capital() -> void:
	var gs = make_gs(1)
	gs.current_player_id = 1
	var capital = make_settlement(gs, 1, 5, 5, 3)
	capital.structures.append("palace")
	var f = bare_facade(gs)
	assert_false(f.apply_command(Commands.disband_city(1, capital.id)),
		"The capital (palace holder) cannot be disbanded")
	assert_eq(gs.get_settlement_at(5, 5).id, capital.id, "…the capital survives")

func test_can_disband_non_capital_when_capital_exists() -> void:
	var gs = make_gs(1)
	gs.current_player_id = 1
	var capital = make_settlement(gs, 1, 5, 5, 3)
	capital.structures.append("palace")
	var colony = make_settlement(gs, 1, 8, 8, 2)
	var f = bare_facade(gs)
	assert_true(f.apply_command(Commands.disband_city(1, colony.id)),
		"A non-capital city can be disbanded even when the capital exists")
	assert_eq(gs.get_settlement_at(8, 8), null, "Colony is razed")
	assert_eq(gs.get_settlement_at(5, 5).id, capital.id, "Capital is unaffected")

# ── Revolt & HP regen through the turn pipeline ───────────────────────────────

func test_revolt_city_produces_nothing_and_counts_down() -> void:
	var gs = make_gs(1)
	var city = make_settlement(gs, 1, 5, 5, 3)
	city.revolt_turns = 2
	city.output_commerce = 99
	TurnEngine.settlement_step(gs, city, gs.get_player(1), hooks())
	assert_eq(city.revolt_turns, 1, "Revolt counts down each owner turn")
	assert_eq(city.output_commerce, 0, "A revolting city generates no output")
	assert_true(city.in_disorder, "…and shows as in unrest")

func test_city_health_regenerates_toward_max() -> void:
	var gs = make_gs(1)
	var city = make_settlement(gs, 1, 5, 5, 3)
	var maxh = TurnEngine.city_max_health(city, gs.db)
	city.health = 1
	TurnEngine._city_health_regen(gs, city)
	assert_true(city.health > 1, "Siege HP recovers between assaults")
	assert_true(city.health <= maxh, "…but never past the maximum")

# ── Missiles cannot defend (§15.7 / D3) ───────────────────────────────────────

func test_garrisoned_missile_is_never_the_defender() -> void:
	# A1 regression: a garrisoned guided missile (strength 40) must never be
	# picked over a real defender — and alone it is no defender at all.
	var gs = make_gs(2)
	_at_war(gs)
	make_settlement(gs, 2, 5, 5, 4)
	var missile = make_unit(gs, "guided_missile", 2, 5, 5)
	var guard = make_warrior(gs, 2, 5, 5)   # strength 10 < the missile's 40
	assert_eq(Stack.get_defender(gs.units, 5, 5, 1, gs).id, guard.id,
		"the weaker warrior defends; the stronger missile is skipped")
	Stack.remove_unit(gs.units, guard.id)
	assert_null(Stack.get_defender(gs.units, 5, 5, 1, gs),
		"a missile-only garrison leaves the city undefended")
	assert_not_null(gs.get_unit(missile.id), "merely asking picks no fight")

func test_missile_only_city_falls_and_missile_dies() -> void:
	var gs = make_gs(2)
	_at_war(gs)
	var city = make_settlement(gs, 2, 5, 5, 4)
	city.peak_population = 4
	var missile = make_unit(gs, "guided_missile", 2, 5, 5)
	var atk = make_warrior(gs, 1, 5, 6)
	var f = bare_facade(gs)
	gs.current_player_id = 1
	f.apply_command(Commands.move_stack(1, 5, 6, 5, 5))
	assert_eq(city.owner_player_id, 1,
		"a city garrisoned only by a missile is undefended and falls at once")
	assert_null(gs.get_unit(missile.id),
		"the stranded missile is destroyed with the captured city, not inherited")
	assert_eq([atk.x, atk.y], [5, 5], "the attacker advances into the city")

func test_stack_wipe_destroys_stranded_missile() -> void:
	var gs = make_gs(2)
	_at_war(gs)
	var guard = make_warrior(gs, 2, 5, 5)
	var missile = make_unit(gs, "guided_missile", 2, 5, 5)
	var atk = make_warrior(gs, 1, 5, 6)
	atk.base_strength = 1000   # wins the fight outright
	var f = bare_facade(gs)
	gs.current_player_id = 1
	f.apply_command(Commands.move_stack(1, 5, 6, 5, 5))
	assert_null(gs.get_unit(guard.id), "the defender died")
	assert_eq([atk.x, atk.y], [5, 5], "the attacker advanced onto the tile")
	assert_null(gs.get_unit(missile.id),
		"the missile left with no surviving defender dies on the captured tile")

func test_missile_survives_while_a_defender_still_stands() -> void:
	var gs = make_gs(2)
	_at_war(gs)
	var missile = make_unit(gs, "guided_missile", 2, 5, 5)
	make_warrior(gs, 2, 5, 5)
	CombatApply.destroy_stranded_missiles(gs, 5, 5, 1)
	assert_not_null(gs.get_unit(missile.id),
		"a missile behind a live defender is not stranded")

func test_walking_onto_lone_missile_tile_destroys_it() -> void:
	var gs = make_gs(2)
	_at_war(gs)
	var missile = make_unit(gs, "guided_missile", 2, 5, 5)
	var atk = make_warrior(gs, 1, 5, 6)
	var f = bare_facade(gs)
	gs.current_player_id = 1
	f.apply_command(Commands.move_stack(1, 5, 6, 5, 5))
	assert_eq([atk.x, atk.y], [5, 5],
		"a lone hostile missile cannot contest the tile (missiles cannot defend)")
	assert_null(gs.get_unit(missile.id), "entering its tile destroys the missile")
	assert_eq(atk.health, 100, "no combat was fought over the missile")
