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

# Technology tree selector: prereq-tier depth, ordering, and node enablement.

func _chooser(facade):
	var tc = load("res://scenes/screens/tech_chooser.gd").new()
	add_child_autofree(tc)
	tc.init(facade)
	return tc

func test_tech_depth_follows_prereq_chain() -> void:
	var facade = setup_facade(70)
	var tc = _chooser(facade)
	# agriculture has no prereqs (tier 0); pottery requires agriculture (tier 1).
	assert_eq(tc._tech_depth("agriculture"), 0, "A root tech sits at tier 0")
	assert_eq(tc._tech_depth("pottery"), 1, "A tech one prereq deep sits at tier 1")
	assert_true(tc._tech_depth("pottery") > tc._tech_depth("agriculture"),
		"A derived tech is deeper than its prerequisite")

func test_compare_orders_shallower_tech_first() -> void:
	var facade = setup_facade(71)
	var tc = _chooser(facade)
	assert_true(tc._compare_tech("agriculture", "pottery"),
		"A tier-0 tech sorts before its tier-1 dependant")
	assert_false(tc._compare_tech("pottery", "agriculture"),
		"…and not the other way round")

func test_researchable_node_is_enabled_known_is_not() -> void:
	var facade = setup_facade(72)
	var gs = facade.get_state()
	var p = gs.players[0]
	gs.current_player_id = p.id
	# Know agriculture; pottery (its dependant) becomes researchable.
	p.technologies = ["agriculture"]

	var tc = _chooser(facade)
	var known_node = tc._build_tech_node("agriculture", p)
	assert_true(known_node.disabled, "An already-known tech node is not selectable")
	assert_true(known_node.text.find("✓") >= 0, "A known tech is marked known")

	var researchable = tc._build_tech_node("pottery", p)
	assert_false(researchable.disabled, "A researchable tech node is clickable")

func _find_cancel_button(tc):
	for child in tc.get_children():
		if child is Button and child.text == "Cancel":
			return child
	return null

func test_cancel_button_is_anchored_to_the_bottom() -> void:
	# Regression: the tech tree's Cancel button must sit at the bottom of the
	# screen (like every other advisor's Close button), not anchored to the right.
	var facade = setup_facade(74)
	var gs = facade.get_state()
	gs.current_player_id = gs.players[0].id
	var tc = _chooser(facade)
	tc.show_screen()                       # rebuild() yields one idle frame
	yield(yield_for(0.05), YIELD)
	var cancel = _find_cancel_button(tc)
	assert_not_null(cancel, "The chooser has a Cancel button")
	assert_eq(cancel.text, "Cancel", "It is labelled Cancel")
	assert_eq(cancel.anchor_top, 1.0, "Cancel is anchored to the bottom edge")
	assert_eq(cancel.anchor_bottom, 1.0, "…top and bottom both pinned to the bottom")
	assert_true(cancel.anchor_left < 1.0,
		"Cancel is no longer anchored to the right edge")

func test_locked_node_is_disabled() -> void:
	var facade = setup_facade(73)
	var gs = facade.get_state()
	var p = gs.players[0]
	gs.current_player_id = p.id
	p.technologies = []          # nothing known → pottery is locked (needs agriculture)
	p.current_research_id = ""   # …and not the active research either
	var tc = _chooser(facade)
	var locked = tc._build_tech_node("pottery", p)
	assert_true(locked.disabled, "A tech whose prereqs are unmet is locked")
	assert_true(locked.text.find("locked") >= 0, "…and labelled locked")
