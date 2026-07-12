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

# Policies & civics (§6.2): selecting a policy, the transition tick-down, and the
# slider constraints a governing policy imposes (increment, min/max research).

# ── Selecting policies ───────────────────────────────────────────────────────

func test_policy_set_and_switch() -> void:
	var p = load("res://src/sim/player.gd").new()
	p.id = 1
	p.policies["government"] = "despotism"
	assert_eq(p.policies["government"], "despotism", "Policy is set correctly")
	p.policies["government"] = "hereditary_rule"
	assert_eq(p.policies["government"], "hereditary_rule", "Policy switches correctly")

func test_transition_ticks_down() -> void:
	var gs = make_gs(1)
	var p = gs.get_player(1)
	p.transition_turns = 3
	TurnEngine._tick_states(gs, p)
	assert_eq(p.transition_turns, 2, "Transition turns tick down by 1 per turn")

func test_set_policy_applies() -> void:
	var facade = setup_facade(7, "tiny",
		[{"name": "A", "leader_id": "", "traits": [], "starting_gold": 100}], ["time"])
	var gs = facade.get_state()
	var pid = gs.players[0].id
	gs.current_player_id = pid
	assert_true(facade.apply_command(Commands.set_policy(pid, "labor", "serfdom")),
		"Selecting the serfdom labor civic should be accepted")
	assert_eq(gs.players[0].policies.get("labor", ""), "serfdom",
		"The labor category should now hold serfdom")

# ── Anarchy on civic switches (§8) ─────────────────────────────────────────────

func test_first_civic_in_category_is_free() -> void:
	var gs = make_gs(1)
	var f = bare_facade(gs)
	gs.current_player_id = 1
	# serfdom carries transition_turns 3, but it is the first labor civic chosen.
	assert_true(f.apply_command(Commands.set_policy(1, "labor", "serfdom")))
	assert_eq(gs.get_player(1).transition_turns, 0,
		"The first civic chosen in a category (from none) causes no anarchy")

func test_switching_established_civic_causes_anarchy() -> void:
	var gs = make_gs(1)
	var f = bare_facade(gs)
	gs.current_player_id = 1
	f.apply_command(Commands.set_policy(1, "labor", "serfdom"))
	assert_true(f.apply_command(Commands.set_policy(1, "labor", "slavery")))
	assert_gt(gs.get_player(1).transition_turns, 0,
		"Replacing an established civic plunges the player into anarchy")

func test_civic_anarchy_scales_with_game_pace() -> void:
	# §15.3 (C3): the policy's transition_turns is stretched by the per-pace
	# anarchy_scale — slavery's base 3 becomes 2/3/4/6 on quick/normal/epic/marathon
	# (Fixed.scale truncation, floored at anarchy_min_turns 1).
	var expected := {"quick": 2, "normal": 3, "epic": 4, "marathon": 6}
	for pace_id in expected:
		var gs = make_gs(1)
		var f = bare_facade(gs)
		gs.current_player_id = 1
		gs.pace_id = pace_id
		f.apply_command(Commands.set_policy(1, "labor", "serfdom"))
		assert_true(f.apply_command(Commands.set_policy(1, "labor", "slavery")))
		assert_eq(gs.get_player(1).transition_turns, expected[pace_id],
			"slavery switch costs %s anarchy turns on %s" % [expected[pace_id], pace_id])

func test_spiritual_leader_switches_civic_without_anarchy() -> void:
	var gs = make_gs(1)
	var f = bare_facade(gs)
	gs.current_player_id = 1
	gs.get_player(1).traits = ["spiritual"]
	f.apply_command(Commands.set_policy(1, "labor", "serfdom"))
	f.apply_command(Commands.set_policy(1, "labor", "slavery"))
	assert_eq(gs.get_player(1).transition_turns, 0,
		"A Spiritual leader switches civics without anarchy")

func test_reselecting_current_civic_is_noop() -> void:
	var gs = make_gs(1)
	var f = bare_facade(gs)
	gs.current_player_id = 1
	f.apply_command(Commands.set_policy(1, "labor", "serfdom"))
	assert_false(f.apply_command(Commands.set_policy(1, "labor", "serfdom")),
		"Re-selecting the current civic is a no-op")

# ── Slider constraints ───────────────────────────────────────────────────────

func test_sliders_unconstrained_without_policy() -> void:
	var gs = make_gs(1)
	var f = bare_facade(gs)
	gs.current_player_id = 1
	assert_true(f.apply_command(Commands.set_sliders(1, 33, 20, 10)),
		"Without a governing policy any three-rate split summing <= 100 is allowed")
	assert_eq(gs.get_player(1).slider_finance, 37,
		"Finance is the derived remainder: 100 - (33 + 20 + 10)")

func test_policy_increment_enforced() -> void:
	var gs = make_gs(1)
	var f = bare_facade(gs)
	gs.current_player_id = 1
	gs.get_player(1).policies = {"government": "republic"}  # increment 10
	assert_false(f.apply_command(Commands.set_sliders(1, 35, 20, 10)),
		"Off-increment rates are rejected")
	assert_true(f.apply_command(Commands.set_sliders(1, 30, 20, 10)),
		"On-increment rates are accepted")

func test_policy_min_research_enforced() -> void:
	var gs = make_gs(1)
	var f = bare_facade(gs)
	gs.current_player_id = 1
	gs.get_player(1).policies = {"government": "republic"}  # min_research 10
	assert_false(f.apply_command(Commands.set_sliders(1, 0, 0, 0)),
		"Research below the policy minimum is rejected")

func test_sliders_over_100_rejected() -> void:
	var gs = make_gs(1)
	var f = bare_facade(gs)
	gs.current_player_id = 1
	assert_false(f.apply_command(Commands.set_sliders(1, 50, 40, 20)),
		"Three rates summing over 100 are rejected")

func test_negative_slider_rejected() -> void:
	var gs = make_gs(1)
	var f = bare_facade(gs)
	gs.current_player_id = 1
	assert_false(f.apply_command(Commands.set_sliders(1, 60, -10, 0)),
		"A negative rate is rejected")

func test_finance_derived_remainder() -> void:
	var gs = make_gs(1)
	var f = bare_facade(gs)
	gs.current_player_id = 1
	assert_true(f.apply_command(Commands.set_sliders(1, 100, 0, 0)),
		"All-research (finance 0) is a legal split")
	var p = gs.get_player(1)
	assert_eq(p.slider_finance, 0, "Finance derives to 0 at full research")
	assert_true(f.apply_command(Commands.set_sliders(1, 40, 30, 20)))
	assert_eq(p.slider_finance, 10, "Finance derives to the remainder (10)")
	assert_eq(p.slider_research + p.slider_culture + p.slider_intel \
		+ p.slider_finance, 100, "The four Player fields still sum to 100")
