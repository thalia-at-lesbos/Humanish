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

# The HUD selection panel renders a selected unit's own actions but must not show
# an Open City button when only a unit (not a city) is selected — even on a city
# tile, where the right-click flyout still offers Open City.

func _count_buttons_named(node, text):
	var n = 0
	for c in node.get_children():
		if c is Button and c.text == text:
			n += 1
	return n

func test_unit_panel_omits_open_city_button() -> void:
	var facade = setup_facade(81, "small",
		[{"name": "A", "leader_id": "", "traits": [], "starting_gold": 50}], ["time"])
	var gs = facade.get_state()
	var pid = gs.players[0].id
	gs.current_player_id = pid

	# A city and a (garrisoned) warrior on the same tile.
	make_settlement(gs, pid, 5, 5).name = "Cap"
	var w = make_unit(gs, "warrior", pid, 5, 5)

	# Sanity: the (right-click) flyout still offers Open City on that tile.
	var has_open = false
	for it in facade.get_flyout_menu(5, 5):
		if int(it.get("action_id", -1)) == IDs.ControlType.OPEN_CITY_SCREEN:
			has_open = true
	assert_true(has_open, "Flyout should still offer Open City on a city tile")

	# But the unit selection panel must not render an Open City button.
	var panel = load("res://scenes/hud/selection_panel.gd").new()
	add_child_autofree(panel)
	panel.init(facade, null)
	facade.select_unit(w.id)
	panel.rebuild()
	assert_eq(_count_buttons_named(panel, "Open City"), 0,
		"A selected unit must not show an Open City button (no city is selected)")
	assert_true(panel.get_child_count() > 0, "The unit panel should still show unit info")
