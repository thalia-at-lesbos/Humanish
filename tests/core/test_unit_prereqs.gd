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

# UnitPrereqs (§15.12) — the canonical compound tech/resource prerequisite
# reader shared by the sim gates, the AI, and the UI. These tests pin the
# parsing of all three accepted forms of each field and the AND/any-of
# semantics of the checks.

func _player_with(techs: Array):
	var gs = make_gs(1)
	var p = gs.get_player(1)
	p.technologies = techs
	return p

# ── tech_list: normalization of the three forms ────────────────────────────────

func test_tech_list_null_and_empty_are_no_requirement() -> void:
	assert_eq(UnitPrereqs.tech_list(null), [], "null → no techs")
	assert_eq(UnitPrereqs.tech_list(""), [], "empty string → no techs")

func test_tech_list_single_string_form() -> void:
	assert_eq(UnitPrereqs.tech_list("guilds"), ["guilds"], "single id → one-element list")

func test_tech_list_array_form() -> void:
	assert_eq(UnitPrereqs.tech_list(["guilds", "horseback_riding"]),
		["guilds", "horseback_riding"], "array passes through")

# ── tech_ok: list form is AND ──────────────────────────────────────────────────

func test_tech_ok_no_requirement_always_passes() -> void:
	var p = _player_with([])
	assert_true(UnitPrereqs.tech_ok(null, p), "no requirement → ok")
	assert_true(UnitPrereqs.tech_ok(null, null), "tech-free passes even with no player")

func test_tech_ok_single_form() -> void:
	assert_false(UnitPrereqs.tech_ok("guilds", _player_with([])), "missing tech blocks")
	assert_true(UnitPrereqs.tech_ok("guilds", _player_with(["guilds"])), "held tech passes")

func test_tech_ok_list_requires_all() -> void:
	var req = ["guilds", "horseback_riding"]
	assert_false(UnitPrereqs.tech_ok(req, _player_with([])), "neither tech → blocked")
	assert_false(UnitPrereqs.tech_ok(req, _player_with(["guilds"])), "one of two → blocked")
	assert_false(UnitPrereqs.tech_ok(req, _player_with(["horseback_riding"])),
		"the other alone → blocked")
	assert_true(UnitPrereqs.tech_ok(req, _player_with(["guilds", "horseback_riding"])),
		"both techs → ok")

func test_tech_ok_null_player_blocks_tech_gated_units() -> void:
	assert_false(UnitPrereqs.tech_ok("archery", null),
		"a null player (wild/headless) only passes tech-free units")

# ── resource_spec / resource_ids: normalization ────────────────────────────────

func test_resource_spec_null_and_single() -> void:
	# Godot 3 compares Dictionaries by reference, so assert on the lists.
	var none = UnitPrereqs.resource_spec(null)
	assert_eq(none["all"], [], "null → no required resources")
	assert_eq(none["any"], [], "null → no alternatives")
	var single = UnitPrereqs.resource_spec("iron")
	assert_eq(single["all"], ["iron"], "single id → required (all)")
	assert_eq(single["any"], [], "single id → no alternatives")

func test_resource_spec_dictionary_form() -> void:
	var spec = UnitPrereqs.resource_spec({"all": ["horse"], "any": ["iron", "copper"]})
	assert_eq(spec["all"], ["horse"], "all list kept")
	assert_eq(spec["any"], ["iron", "copper"], "any list kept")

func test_resource_ids_unions_both_lists() -> void:
	assert_eq(UnitPrereqs.resource_ids({"all": ["horse"], "any": ["iron", "horse"]}),
		["horse", "iron"], "ids deduplicated across all/any")

# ── resource_ok: all = every, any = at least one ───────────────────────────────

func test_resource_ok_no_requirement() -> void:
	assert_true(UnitPrereqs.resource_ok(null, {}), "no requirement → ok with nothing")

func test_resource_ok_single_form_is_required() -> void:
	assert_false(UnitPrereqs.resource_ok("iron", {}), "missing single resource blocks")
	assert_true(UnitPrereqs.resource_ok("iron", {"iron": true}), "held resource passes")

func test_resource_ok_all_needs_every_entry() -> void:
	var req = {"all": ["horse", "iron"]}
	assert_false(UnitPrereqs.resource_ok(req, {"horse": true}), "one of an all-pair blocks")
	assert_false(UnitPrereqs.resource_ok(req, {"iron": true}), "the other alone blocks")
	assert_true(UnitPrereqs.resource_ok(req, {"horse": true, "iron": true}),
		"both all entries → ok")

func test_resource_ok_any_satisfied_by_either() -> void:
	var req = {"any": ["copper", "iron"]}
	assert_false(UnitPrereqs.resource_ok(req, {}), "no alternative held blocks")
	assert_true(UnitPrereqs.resource_ok(req, {"copper": true}), "copper alone passes")
	assert_true(UnitPrereqs.resource_ok(req, {"iron": true}), "iron alone passes")

func test_resource_ok_all_plus_any_combined() -> void:
	var req = {"all": ["horse"], "any": ["copper", "iron"]}
	assert_false(UnitPrereqs.resource_ok(req, {"horse": true}),
		"the fixed resource alone is not enough when an any-list exists")
	assert_false(UnitPrereqs.resource_ok(req, {"iron": true}),
		"an alternative alone is not enough without the fixed resource")
	assert_true(UnitPrereqs.resource_ok(req, {"horse": true, "iron": true}),
		"fixed + one alternative → ok")
