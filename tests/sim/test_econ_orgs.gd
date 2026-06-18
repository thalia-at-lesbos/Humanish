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

# ── §14.6 corporation model: HQ, executive, resource-count output, maintenance ──

# Place a connected resource tile owned by `player_id` (resource + the improvement
# its connection requires, with the player granted the resource's tech).
func _give_resource(gs, player_id, x, y, res_id) -> void:
	var res = gs.db.get_resource(res_id)
	var tile = gs.map.get_tile(x, y)
	tile.owner_player_id = player_id
	tile.resource_id = res_id
	var imp = res.get("improvement_required", null)
	if imp != null and imp != "":
		tile.improvement_id = imp
	var tech = res.get("tech_required", null)
	if tech != null and tech != "":
		gs.get_player(player_id).technologies.append(tech)

func test_found_corporation_erects_hq_structure() -> void:
	var gs = make_gs()
	var s = make_settlement(gs, 1, 5, 5, 5)
	EconOrgs.found("cereal_mills", s, gs)
	assert_true(s.has_structure("cereal_mills_hq"),
		"Founding a corporation erects its HQ structure in the founding city")

func test_output_scales_with_accessible_input_count() -> void:
	var gs = make_gs()
	var s = make_settlement(gs, 1, 5, 5, 5)
	EconOrgs.found("cereal_mills", s, gs)  # +1 food per accessible input type
	assert_eq(EconOrgs.get_output_delta(gs, s), [0, 0, 0],
		"No accessible inputs yields no corporation output")
	_give_resource(gs, 1, 1, 1, "wheat")
	_give_resource(gs, 1, 2, 1, "rice")
	assert_eq(EconOrgs.get_output_delta(gs, s), [2, 0, 0],
		"Output scales +1 food per distinct accessible input resource")
	_give_resource(gs, 1, 3, 1, "corn")
	assert_eq(EconOrgs.get_output_delta(gs, s), [3, 0, 0],
		"A third accessible input raises the per-city output again")

func test_flat_output_ignores_input_count() -> void:
	var gs = make_gs()
	var s = make_settlement(gs, 1, 5, 5, 5)
	EconOrgs.found("aluminum_co", s, gs)  # flat +3 production, no per-input scaling
	assert_eq(EconOrgs.get_output_delta(gs, s), [0, 3, 0],
		"A flat-output corporation pays its bonus without any inputs")

func test_maintenance_charged_per_member_city() -> void:
	var gs = make_gs()
	var p = gs.get_player(1)
	var s = make_settlement(gs, 1, 5, 5, 5)
	EconOrgs.found("merchant_guild", s, gs)
	assert_eq(EconOrgs.maintenance_for(gs, gs.db, p), 3,
		"A member city charges its corporation maintenance")
	p.policies["economic"] = "free_market"  # -50% corporation maintenance
	assert_true(EconOrgs.maintenance_for(gs, gs.db, p) < 3,
		"Free Market reduces corporation maintenance")

func test_hq_pays_founder_per_input_consumed() -> void:
	var gs = make_gs()
	var p = gs.get_player(1)
	var s = make_settlement(gs, 1, 5, 5, 5)
	EconOrgs.found("cereal_mills", s, gs)
	_give_resource(gs, 1, 1, 1, "wheat")
	_give_resource(gs, 1, 2, 1, "rice")
	# 2 accessible inputs in the one member city × hq_gold_per_input (2) = 4.
	assert_eq(EconOrgs.hq_gold_for(gs, gs.db, p), 4,
		"The HQ pays the founder per unit of input consumed worldwide")

func test_banning_civic_disables_corporations() -> void:
	var gs = make_gs()
	var p = gs.get_player(1)
	var s = make_settlement(gs, 1, 5, 5, 5)
	EconOrgs.found("aluminum_co", s, gs)
	p.policies["economic"] = "state_property"  # corporations_disabled
	assert_eq(EconOrgs.get_output_delta(gs, s), [0, 0, 0],
		"A state-property economy yields no corporation output")
	assert_eq(EconOrgs.maintenance_for(gs, gs.db, p), 0,
		"A banning civic charges no corporation maintenance")

func test_executive_spread_costs_treasury_and_is_deterministic() -> void:
	var gs = make_gs()
	var p = gs.get_player(1)
	p.treasury = 200
	gs.current_player_id = 1
	var s1 = make_settlement(gs, 1, 5, 5, 5)
	var s2 = make_settlement(gs, 1, 10, 10, 5)
	EconOrgs.found("merchant_guild", s1, gs)  # player now owns the corporation
	var exe = make_unit(gs, "executive", 1, 10, 10)
	var f = bare_facade(gs)
	var ok = f.apply_command(Commands.spread_corporation(1, exe.id, s2.id))
	assert_true(ok, "Executive spreads the player's corporation to the city on its tile")
	assert_eq(s2.econ_org_id, "merchant_guild", "The target city now hosts the corporation")
	assert_eq(p.treasury, 100, "Spreading charges the executive spread cost")
	assert_null(gs.get_unit(exe.id), "The executive is consumed on a successful spread")

func test_executive_spread_blocked_under_ban() -> void:
	var gs = make_gs()
	var p = gs.get_player(1)
	p.treasury = 200
	gs.current_player_id = 1
	var s1 = make_settlement(gs, 1, 5, 5, 5)
	var s2 = make_settlement(gs, 1, 10, 10, 5)
	p.policies["economic"] = "state_property"
	EconOrgs.found("merchant_guild", s1, gs)
	var exe = make_unit(gs, "executive", 1, 10, 10)
	var f = bare_facade(gs)
	var ok = f.apply_command(Commands.spread_corporation(1, exe.id, s2.id))
	assert_false(ok, "An executive cannot spread a corporation under a banning civic")
	assert_eq(s2.econ_org_id, "", "The city stays free of the corporation")
