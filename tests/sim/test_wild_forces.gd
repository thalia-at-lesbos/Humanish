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

# Wild forces: per-turn spawning is bounded by a land-based cap so raiders never
# flood the map over a long game.

func test_wild_units_are_capped_over_many_turns() -> void:
	var facade = setup_facade(4242, "small",
		[{"name": "A", "leader_id": "", "traits": [], "starting_gold": 50},
		 {"name": "B", "leader_id": "", "traits": [], "starting_gold": 50}],
		["time"])
	var gs = facade.get_state()
	for _t in range(20):
		for p in gs.players:
			gs.current_player_id = p.id
			facade.apply_command(Commands.end_turn(p.id))

	var land = 0
	for tile in gs.map.all_tiles():
		if gs.db.get_terrain(tile.terrain_id).get("domain", "land") == "land":
			land += 1
	var wild = 0
	for u in gs.units:
		if u.is_wild:
			wild += 1
	var cap = land / int(gs.db.constants.get("wild_land_per_unit", 80))
	assert_true(wild <= cap + 1,
		"Wild units (%d) must stay near the land-based cap (%d), not flood" % [wild, cap])
