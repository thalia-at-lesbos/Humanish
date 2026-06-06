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

# About screen (§11 session/meta): builds title/version/license text with no
# game state, and is reachable from the pause menu.

func test_about_screen_builds_without_facade() -> void:
	var about = load("res://scenes/screens/about_screen.gd").new()
	add_child_autofree(about)
	about.init(null)
	about.show_screen()
	assert_true(about.visible, "About screen should be visible after show_screen()")
	assert_true(about.get_child_count() > 0, "About screen should build text content")

func _collect_labels(node, out) -> void:
	for child in node.get_children():
		if child is Label:
			out.append(child.text)
		if child.get_child_count() > 0:
			_collect_labels(child, out)

func test_about_screen_shows_version_and_license() -> void:
	var about = load("res://scenes/screens/about_screen.gd").new()
	add_child_autofree(about)
	about.init(null)
	about.show_screen()
	var labels = []
	_collect_labels(about, labels)
	var joined = PoolStringArray(labels).join("\n")
	assert_true(joined.find("Version") >= 0, "About should show a version line")
	assert_true(joined.find("GNU General Public License") >= 0,
		"About should show the GPL license notice")

func test_pause_menu_opens_about() -> void:
	var facade = setup_facade(77)
	var pause = load("res://scenes/screens/pause_menu.gd").new()
	add_child_autofree(pause)
	pause.init(facade)
	pause._on_about()
	assert_not_null(pause._about_screen, "Pause menu should lazily build the About overlay")
	assert_true(pause._about_screen.visible, "About overlay should be shown from the pause menu")
