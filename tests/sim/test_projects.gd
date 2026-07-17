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

# §15.7 effects projects (C5): SDI and The Internet. Covers the data rows, the
# Projects effects reader, buildability/instance gating, production completion,
# the Internet's research-phase tech-share, and save/load round-tripping of
# Player.projects.

func _give_manhattan(gs, owner_id):
	var s = make_settlement(gs, owner_id, 0, 0, 1)
	s.structures.append("manhattan_project")
	return s

# ── Data rows (§29.2 reference values) ────────────────────────────────────────

func test_projects_carry_c5_reference_rows() -> void:
	var db = make_db()
	var sdi: Dictionary = db.projects.get("sdi", {})
	assert_eq(int(sdi.get("cost", 0)), 1000, "SDI costs 1000")
	assert_eq(str(sdi.get("tech_required", "")), "laser", "SDI needs Laser")
	assert_eq(str(sdi.get("instances", "")), "player", "SDI is one per player")
	assert_eq(str(sdi.get("requires_wonder_any", "")), "manhattan_project",
		"SDI requires the Manhattan Project completed by anyone")
	assert_eq(int(sdi.get("effects", {}).get("nuke_interception", 0)), 75,
		"SDI grants 75% nuke interception")
	var net: Dictionary = db.projects.get("the_internet", {})
	assert_eq(int(net.get("cost", 0)), 2000, "The Internet costs 2000")
	assert_eq(str(net.get("tech_required", "")), "computers", "The Internet needs Computers")
	assert_eq(str(net.get("instances", "")), "world", "The Internet is one per game")
	assert_eq(int(net.get("effects", {}).get("tech_share", 0)), 2,
		"The Internet shares techs known by 2 other players")

func test_effects_projects_are_not_endgame_stages() -> void:
	var db = make_db()
	assert_false(Projects.is_endgame(db.projects["sdi"]), "SDI is not a spaceship stage")
	assert_true(Projects.is_endgame(db.projects["ss_casing"]),
		"spaceship parts keep the endgame model")

# ── Effects reader ────────────────────────────────────────────────────────────

func test_effect_int_sums_completed_projects_only() -> void:
	var gs = make_gs(2)
	var p1 = gs.get_player(1)
	assert_eq(Projects.effect_int(p1, gs.db, "nuke_interception"), 0,
		"no projects, no effect")
	p1.projects.append("sdi")
	assert_eq(Projects.effect_int(p1, gs.db, "nuke_interception"), 75,
		"SDI's owner reads the 75% interception effect")
	assert_eq(Projects.effect_int(gs.get_player(2), gs.db, "nuke_interception"), 0,
		"a rival without the project reads zero")
	assert_true(Projects.has_project(p1, "sdi"), "has_project sees the grant")
	assert_false(Projects.has_project(p1, "the_internet"), "only completed projects count")

# ── Buildability gating ───────────────────────────────────────────────────────

func test_can_build_sdi_needs_tech_and_manhattan_by_anyone() -> void:
	var gs = make_gs(2)
	var p1 = gs.get_player(1)
	assert_false(Projects.can_build(gs, p1, "sdi"), "no Laser, no Manhattan: refused")
	p1.technologies.append("laser")
	assert_false(Projects.can_build(gs, p1, "sdi"), "still no Manhattan Project anywhere")
	_give_manhattan(gs, 2)  # a RIVAL's Manhattan Project counts
	assert_true(Projects.can_build(gs, p1, "sdi"),
		"Laser + anyone's Manhattan Project allows SDI")

func test_can_build_respects_instance_limits() -> void:
	var gs = make_gs(2)
	var p1 = gs.get_player(1)
	var p2 = gs.get_player(2)
	p1.technologies.append("laser")
	p1.technologies.append("computers")
	p2.technologies.append("computers")
	_give_manhattan(gs, 1)
	p1.projects.append("sdi")
	assert_false(Projects.can_build(gs, p1, "sdi"), "SDI is one per player")
	p2.technologies.append("laser")
	assert_true(Projects.can_build(gs, p2, "sdi"), "a rival may still build their own SDI")
	p2.projects.append("the_internet")
	assert_false(Projects.can_build(gs, p1, "the_internet"),
		"The Internet is one per game — a rival's copy exhausts it")

func test_can_build_rejects_unknown_and_endgame_ids() -> void:
	var gs = make_gs(1)
	var p1 = gs.get_player(1)
	assert_false(Projects.can_build(gs, p1, "no_such_project"), "unknown id refused")
	assert_false(Projects.can_build(gs, p1, "ss_casing"),
		"spaceship stages are not judged by the effects-project gate")

# ── Completion ────────────────────────────────────────────────────────────────

func test_completing_sdi_records_it_on_the_player() -> void:
	var gs = make_gs(2)
	var p1 = gs.get_player(1)
	var s = make_settlement(gs, 1, 5, 5, 3)
	TurnEngine._complete_item(gs, s, p1, {"type": "project", "id": "sdi"})
	assert_true("sdi" in p1.projects, "completion records the project on the player")
	assert_false(gs.endgame_project_stages.has(p1.alliance_id),
		"an effects project never counts as a spaceship stage")

func test_completing_spaceship_stage_keeps_old_model() -> void:
	var gs = make_gs(2)
	var p1 = gs.get_player(1)
	var s = make_settlement(gs, 1, 5, 5, 3)
	TurnEngine._complete_item(gs, s, p1, {"type": "project", "id": "ss_casing"})
	assert_eq(int(gs.endgame_project_stages.get(p1.alliance_id, 0)), 1,
		"spaceship stage still increments the alliance counter")
	assert_false("ss_casing" in p1.projects,
		"spaceship stages are not recorded on Player.projects")

func test_world_project_completed_second_grants_nothing() -> void:
	var gs = make_gs(2)
	var p1 = gs.get_player(1)
	var p2 = gs.get_player(2)
	p2.projects.append("the_internet")
	var s = make_settlement(gs, 1, 5, 5, 3)
	TurnEngine._complete_item(gs, s, p1, {"type": "project", "id": "the_internet"})
	assert_false("the_internet" in p1.projects,
		"a world-unique project already claimed by a rival grants nothing")

# ── Queue gating at the command layer ─────────────────────────────────────────

func test_set_production_rejects_ungated_effects_project() -> void:
	var gs = make_gs(2)
	gs.current_player_id = 1
	var f = bare_facade(gs)
	var s = make_settlement(gs, 1, 5, 5, 3)
	assert_false(f.apply_command(Commands.set_production(1, s.id,
		[{"type": "project", "id": "sdi"}])),
		"queueing SDI without Laser/Manhattan is refused")
	var p1 = gs.get_player(1)
	p1.technologies.append("laser")
	_give_manhattan(gs, 1)
	assert_true(f.apply_command(Commands.set_production(1, s.id,
		[{"type": "project", "id": "sdi"}])),
		"queueing SDI with its prerequisites met is accepted")

# ── The Internet's tech-share (research phase) ────────────────────────────────

func test_tech_share_grants_tech_known_by_two_others() -> void:
	var gs = make_gs(3)
	var p1 = gs.get_player(1)
	p1.projects.append("the_internet")
	gs.get_player(2).technologies.append("pottery")
	gs.get_player(3).technologies.append("pottery")
	TurnEngine.player_step(gs, 1, hooks())
	assert_true(p1.has_tech("pottery"),
		"the Internet's owner absorbs a tech known by 2 other players")

func test_tech_share_needs_enough_other_players() -> void:
	var gs = make_gs(3)
	var p1 = gs.get_player(1)
	p1.projects.append("the_internet")
	gs.get_player(2).technologies.append("pottery")
	TurnEngine.player_step(gs, 1, hooks())
	assert_false(p1.has_tech("pottery"),
		"a tech known by only 1 other player is not shared (K = 2)")

func test_tech_share_inert_without_the_project() -> void:
	var gs = make_gs(3)
	gs.get_player(2).technologies.append("pottery")
	gs.get_player(3).technologies.append("pottery")
	TurnEngine.player_step(gs, 1, hooks())
	assert_false(gs.get_player(1).has_tech("pottery"),
		"no Internet, no tech-share")

func test_tech_share_completes_current_research_for_free() -> void:
	var gs = make_gs(3)
	var p1 = gs.get_player(1)
	p1.projects.append("the_internet")
	p1.current_research_id = "pottery"
	gs.get_player(2).technologies.append("pottery")
	gs.get_player(3).technologies.append("pottery")
	TurnEngine.player_step(gs, 1, hooks())
	assert_true(p1.has_tech("pottery"), "the shared tech is granted")
	assert_eq(p1.current_research_id, "",
		"a shared tech that was under research clears the research slot")

# ── Serialization ─────────────────────────────────────────────────────────────

func test_player_projects_round_trip_save_load() -> void:
	var f = setup_facade(777)
	var gs = f.get_state()
	gs.get_player(1).projects.append("sdi")
	gs.get_player(2).projects.append("the_internet")
	var save_json: String = f.save()
	var h1: int = f.state_hash()
	var f2 = load("res://src/api/sim_facade.gd").new()
	f2.init_for_load(make_db())
	f2.load_save(save_json)
	assert_eq(f2.state_hash(), h1, "projects survive save/load with an identical hash")
	assert_true("sdi" in f2.get_state().get_player(1).projects,
		"the loaded player still owns SDI")
