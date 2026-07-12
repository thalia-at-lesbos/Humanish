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

# State religion (§8, provisional): a player-level adopted religion selected via
# the SET_STATE_RELIGION command. First adoption is free; later switches cause
# anarchy (no commerce) unless the leader is Spiritual. Wired to Theocracy XP,
# Cathedral happiness, and Theocracy's non-state-spread block.

# Build a facade over a hand-made state where player 1 has a city following
# `belief` and that belief is registered as founded.
func _facade_with_religion(belief = "buddhism", spiritual = false):
	var gs = make_gs(1)
	gs.current_player_id = 1
	var p = gs.get_player(1)
	if spiritual:
		p.traits = ["spiritual"]
	gs.founded_beliefs[belief] = 1
	var s = make_settlement(gs, 1, 5, 5, 3)
	s.belief_id = belief
	return bare_facade(gs)

# ── Adoption & anarchy ─────────────────────────────────────────────────────────

func test_all_players_start_without_state_religion() -> void:
	var gs = make_gs(2)
	assert_eq(gs.get_player(1).state_religion, "", "Player 1 starts with no state religion")
	assert_eq(gs.get_player(2).state_religion, "", "Player 2 starts with no state religion")

func test_first_adoption_sets_religion_without_anarchy() -> void:
	var f = _facade_with_religion()
	var ok = f.apply_command(Commands.set_state_religion(1, "buddhism"))
	var p = f.get_state().get_player(1)
	assert_true(ok, "Adopting a present religion succeeds")
	assert_eq(p.state_religion, "buddhism", "State religion is adopted")
	assert_eq(p.transition_turns, 0, "First adoption (from none) causes no anarchy")

func test_switching_religion_triggers_anarchy() -> void:
	var f = _facade_with_religion()
	var gs = f.get_state()
	# A second religion also present in the empire.
	gs.founded_beliefs["christianity"] = 1
	make_settlement(gs, 1, 6, 6, 2).belief_id = "christianity"
	f.apply_command(Commands.set_state_religion(1, "buddhism"))
	var ok = f.apply_command(Commands.set_state_religion(1, "christianity"))
	var p = gs.get_player(1)
	assert_true(ok, "Switching to another present religion succeeds")
	assert_eq(p.state_religion, "christianity", "State religion switched")
	assert_gt(p.transition_turns, 0, "Switching away from a religion causes anarchy")

func test_switching_to_none_triggers_anarchy() -> void:
	var f = _facade_with_religion()
	f.apply_command(Commands.set_state_religion(1, "buddhism"))
	var ok = f.apply_command(Commands.set_state_religion(1, ""))
	var p = f.get_state().get_player(1)
	assert_true(ok, "Reverting to no state religion succeeds")
	assert_eq(p.state_religion, "", "State religion cleared")
	assert_gt(p.transition_turns, 0, "Abandoning a state religion also causes anarchy")

func test_religion_anarchy_scales_with_pace_and_keeps_the_minimum() -> void:
	# §15.3 (C3): religion-switch anarchy (base state_religion_anarchy_turns 1) is
	# stretched by the per-pace anarchy_scale — marathon (200) doubles it to 2, and
	# on quick (67) truncation to 0 is caught by the anarchy_min_turns 1 floor.
	var expected := {"quick": 1, "normal": 1, "epic": 1, "marathon": 2}
	for pace_id in expected:
		var f = _facade_with_religion()
		f.get_state().pace_id = pace_id
		f.apply_command(Commands.set_state_religion(1, "buddhism"))
		f.apply_command(Commands.set_state_religion(1, ""))
		assert_eq(f.get_state().get_player(1).transition_turns, expected[pace_id],
			"religion switch costs %s anarchy turns on %s" % [expected[pace_id], pace_id])

func test_spiritual_leader_switches_without_anarchy() -> void:
	var f = _facade_with_religion("buddhism", true)
	var gs = f.get_state()
	gs.founded_beliefs["christianity"] = 1
	make_settlement(gs, 1, 6, 6, 2).belief_id = "christianity"
	f.apply_command(Commands.set_state_religion(1, "buddhism"))
	f.apply_command(Commands.set_state_religion(1, "christianity"))
	assert_eq(gs.get_player(1).transition_turns, 0,
		"A Spiritual leader switches state religion without anarchy")

func test_cannot_adopt_religion_absent_from_empire() -> void:
	var f = _facade_with_religion()
	var gs = f.get_state()
	gs.founded_beliefs["islam"] = 2  # founded by someone else, not present in our cities
	var ok = f.apply_command(Commands.set_state_religion(1, "islam"))
	assert_false(ok, "Cannot adopt a religion not present in any of the player's cities")
	assert_eq(gs.get_player(1).state_religion, "", "State religion unchanged")

func test_cannot_adopt_unfounded_religion() -> void:
	var f = _facade_with_religion()
	var ok = f.apply_command(Commands.set_state_religion(1, "no_such_belief"))
	assert_false(ok, "Cannot adopt an unfounded religion")

func test_readopting_same_religion_is_noop() -> void:
	var f = _facade_with_religion()
	f.apply_command(Commands.set_state_religion(1, "buddhism"))
	var ok = f.apply_command(Commands.set_state_religion(1, "buddhism"))
	assert_false(ok, "Re-selecting the current state religion is a no-op")
	assert_eq(f.get_state().get_player(1).transition_turns, 0, "No anarchy from a no-op")

# ── Anarchy suppresses commerce ────────────────────────────────────────────────

func test_anarchy_zeroes_commerce_output() -> void:
	var gs = make_gs(1)
	var p = gs.get_player(1)
	var s = make_settlement(gs, 1, 5, 5, 3)
	s.specialists = {"merchant": 1}  # merchant yields commerce per the specialists table
	TurnEngine._settlement_growth(gs, s, p)
	assert_gt(s.output_commerce, 0, "A merchant specialist yields commerce in peacetime")
	p.transition_turns = 1
	TurnEngine._settlement_growth(gs, s, p)
	assert_eq(s.output_commerce, 0, "Anarchy zeroes all commerce output")

func test_anarchy_ticks_down() -> void:
	var gs = make_gs(1)
	var p = gs.get_player(1)
	p.transition_turns = 2
	TurnEngine._tick_states(gs, p)
	assert_eq(p.transition_turns, 1, "Anarchy counts down one turn per tick")

# ── Cathedral happiness requires the state religion ────────────────────────────

func test_cathedral_happiness_requires_state_religion() -> void:
	var gs = make_gs(1)
	var p = gs.get_player(1)
	gs.founded_beliefs["buddhism"] = 1
	var s = make_settlement(gs, 1, 5, 5, 5)
	s.belief_id = "buddhism"
	# Reference parity (A2) set the shipped cathedral happiness_bonus to 0; inject
	# a bonus here so the requires_state_religion gate itself stays under test.
	gs.db.structures["buddhist_cathedral"]["happiness_bonus"] = 2
	s.structures = ["buddhist_cathedral"]  # requires_state_religion
	TurnEngine._update_contentment(gs, s, p, gs.db)
	var without: int = s.positive_sentiment
	p.state_religion = "buddhism"
	TurnEngine._update_contentment(gs, s, p, gs.db)
	assert_eq(s.positive_sentiment - without, 2,
		"The Cathedral comforts the city only once its religion is the state religion")

# ── Theocracy blocks non-state religion spread ─────────────────────────────────

func test_theocracy_blocks_nonstate_spread() -> void:
	var gs = make_gs(1)
	var p = gs.get_player(1)
	p.policies = {"religion": "theocracy"}  # blocks_nonstate_spread
	p.state_religion = "buddhism"
	gs.founded_beliefs["christianity"] = 1
	# A source city (neutral owner irrelevant) right next to our empty city.
	var src = make_settlement(gs, 1, 5, 5, 2)
	src.belief_id = "christianity"
	var ours = make_settlement(gs, 1, 6, 5, 2)  # adjacent, currently religionless
	for _i in range(30):
		Beliefs.spread_all(gs, gs.rng)
	assert_eq(ours.belief_id, "",
		"Theocracy keeps a non-state religion from spreading into our cities")

# ── Persistence ────────────────────────────────────────────────────────────────

func test_state_religion_survives_serialization() -> void:
	var gs = make_gs(1)
	var p = gs.get_player(1)
	p.state_religion = "buddhism"
	p.transition_turns = 3
	var restored = load("res://src/sim/player.gd").deserialize(p.serialize())
	assert_eq(restored.state_religion, "buddhism", "state_religion round-trips")
	assert_eq(restored.transition_turns, 3, "transition_turns round-trips")
