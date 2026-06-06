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

# The Palace defines the capital (§6.1): it follows the Palace, is rebuilt for
# free in the new capital if the old one is lost, and can be moved by building a
# new Palace in another city.

func test_find_capital_follows_the_palace() -> void:
	var gs = make_gs(1)
	var first = make_settlement(gs, 1, 3, 3)    # lowest id
	var second = make_settlement(gs, 1, 9, 9)
	second.structures.append("palace")          # capital is the Palace city, not the oldest
	assert_eq(TurnEngine._find_capital(gs, 1).id, second.id,
		"The capital is the city that holds the Palace")

func test_find_capital_falls_back_to_oldest_without_a_palace() -> void:
	var gs = make_gs(1)
	var first = make_settlement(gs, 1, 3, 3)
	make_settlement(gs, 1, 9, 9)
	assert_eq(TurnEngine._find_capital(gs, 1).id, first.id,
		"With no Palace anywhere, the earliest-founded city is the fallback capital")

func test_capital_palace_rebuilt_when_capital_lost() -> void:
	var gs = make_gs(1)
	var capital = make_settlement(gs, 1, 3, 3)
	var other = make_settlement(gs, 1, 9, 9)
	capital.structures.append("palace")

	# Lose the capital city.
	gs.settlements.erase(capital)
	TurnEngine._ensure_capital_palace(gs, 1)

	assert_true(other.has_structure("palace"),
		"Losing the capital rebuilds the Palace for free in the new capital")
	assert_eq(TurnEngine._find_capital(gs, 1).id, other.id,
		"…and that city is now the capital")

func test_ensure_capital_palace_is_noop_when_intact() -> void:
	var gs = make_gs(1)
	var capital = make_settlement(gs, 1, 3, 3)
	var other = make_settlement(gs, 1, 9, 9)
	capital.structures.append("palace")

	TurnEngine._ensure_capital_palace(gs, 1)
	assert_true(capital.has_structure("palace"), "The intact capital keeps its Palace")
	assert_false(other.has_structure("palace"), "No second Palace is created")

func test_ensure_capital_palace_noop_with_no_cities() -> void:
	var gs = make_gs(1)
	TurnEngine._ensure_capital_palace(gs, 1)   # must not error with zero cities
	assert_eq(TurnEngine._find_capital(gs, 1), null, "No cities → no capital")

func test_building_palace_relocates_the_capital() -> void:
	var gs = make_gs(1)
	var old_cap = make_settlement(gs, 1, 3, 3)
	var new_cap = make_settlement(gs, 1, 9, 9)
	old_cap.structures.append("palace")
	var player = gs.get_player(1)

	# Finish building a Palace in the second city.
	TurnEngine._complete_item(gs, new_cap, player, {"type": "structure", "id": "palace"})

	assert_true(new_cap.has_structure("palace"), "The newly built city gains the Palace")
	assert_false(old_cap.has_structure("palace"),
		"…and the old capital loses it — there is only ever one Palace")
	assert_eq(TurnEngine._find_capital(gs, 1).id, new_cap.id,
		"…so the built city is now the capital")

func test_player_step_reseeds_a_lost_capital() -> void:
	# End-to-end through the turn pipeline: the capital is gone at the top of the
	# player's turn, and player_step rebuilds it before maintenance reads it.
	var gs = make_gs(1)
	var capital = make_settlement(gs, 1, 3, 3)
	var other = make_settlement(gs, 1, 9, 9)
	capital.structures.append("palace")
	gs.settlements.erase(capital)

	TurnEngine.player_step(gs, 1, hooks())
	assert_true(other.has_structure("palace"),
		"player_step rebuilds the Palace in the surviving city")
