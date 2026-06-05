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

# Economic organizations (§8): seeded by a special person and spreading to nearby
# same-owner settlements over time.

func test_special_person_founds_econ_org() -> void:
	var gs = make_gs()
	var p = gs.get_player(1)
	p.current_research_id = ""  # no research -> try econ org before gold
	var s = make_settlement(gs, 1, 5, 5, 5)
	TurnEngine._apply_special_person(gs, s)
	assert_ne(s.econ_org_id, "", "A special person seeds an economic organization")
	assert_true(gs.founded_econ_orgs.has(s.econ_org_id), "Org recorded as founded")

func test_econ_org_spreads_to_adjacent_settlement() -> void:
	var gs = make_gs()
	gs.get_player(1).treasury = 1000
	var s1 = make_settlement(gs, 1, 5, 5, 5)
	var s2 = make_settlement(gs, 1, 6, 5, 5)
	EconOrgs.found("merchant_guild", s1, gs)
	var spread := false
	for _i in range(50):
		EconOrgs.spread_all(gs, gs.rng)
		if s2.econ_org_id == "merchant_guild":
			spread = true
			break
	assert_true(spread, "An economic organization spreads to an adjacent settlement")
