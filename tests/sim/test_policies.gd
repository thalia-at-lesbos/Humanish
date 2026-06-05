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
	p.policies["government"] = "monarchy"
	assert_eq(p.policies["government"], "monarchy", "Policy switches correctly")

func test_transition_ticks_down() -> void:
	var gs = make_gs(1)
	var p = gs.get_player(1)
	p.transition_turns = 3
	TurnEngine._tick_states(gs, p)
	assert_eq(p.transition_turns, 2, "Transition turns tick down by 1 per turn")

func test_set_civic_policy_applies() -> void:
	var facade = setup_facade(7, "tiny",
		[{"name": "A", "leader_id": "", "traits": [], "starting_gold": 100}], ["time"])
	var gs = facade.get_state()
	var pid = gs.players[0].id
	gs.current_player_id = pid
	assert_true(facade.apply_command(Commands.set_policy(pid, "civic", "fascism")),
		"Selecting the fascism civic should be accepted")
	assert_eq(gs.players[0].policies.get("civic", ""), "fascism",
		"The civic category should now hold fascism")

# ── Slider constraints ───────────────────────────────────────────────────────

func test_sliders_unconstrained_without_policy() -> void:
	var gs = make_gs(1)
	var f = bare_facade(gs)
	gs.current_player_id = 1
	assert_true(f.apply_command(Commands.set_sliders(1, 37, 33, 20, 10)),
		"Without a governing policy any 100-sum split is allowed")

func test_policy_increment_enforced() -> void:
	var gs = make_gs(1)
	var f = bare_facade(gs)
	gs.current_player_id = 1
	gs.get_player(1).policies = {"government": "republic"}  # increment 10
	assert_false(f.apply_command(Commands.set_sliders(1, 35, 35, 20, 10)),
		"Off-increment sliders are rejected")
	assert_true(f.apply_command(Commands.set_sliders(1, 40, 30, 20, 10)),
		"On-increment sliders are accepted")

func test_policy_min_research_enforced() -> void:
	var gs = make_gs(1)
	var f = bare_facade(gs)
	gs.current_player_id = 1
	gs.get_player(1).policies = {"government": "republic"}  # min_research 10
	assert_false(f.apply_command(Commands.set_sliders(1, 100, 0, 0, 0)),
		"Research below the policy minimum is rejected")

func test_policy_max_research_cap_enforced() -> void:
	var gs = make_gs(1)
	var f = bare_facade(gs)
	gs.current_player_id = 1
	gs.get_player(1).policies = {"civic": "communism"}  # max_research 50
	assert_false(f.apply_command(Commands.set_sliders(1, 10, 90, 0, 0)),
		"Research above the policy cap is rejected")
	assert_true(f.apply_command(Commands.set_sliders(1, 50, 50, 0, 0)),
		"Research at the cap is accepted")
