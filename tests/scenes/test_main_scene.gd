# Humanish — a turn-based 4X strategy game.
# Copyright (C) 2026 thalia-at-lesbos
# SPDX-License-Identifier: GPL-3.0-or-later
#
# This program is free software: you can redistribute it and/or modify it
# under the terms of the GNU General Public License as published by the Free
# Software Foundation, either version 3 of the License, or (at your option)
# any later version. See the LICENSE file for the full text and warranty
# disclaimer.

extends "res://addons/gut/test.gd"

# Whole-scene smoke tests: the main scene boots its fallback game and wires the
# overlays, and the hotseat pass-device overlay sits above the HUD and dismisses
# correctly.

func test_main_scene_boots_and_wires_overlays() -> void:
	var main = load("res://scenes/main.tscn").instance()
	add_child_autofree(main)
	# _ready ran the default 2-player fallback game.
	assert_not_null(main.get_facade(), "main should have a facade after _ready")
	assert_not_null(main.get_node_or_null("WorldView"), "world view present")
	assert_not_null(main.get_node_or_null("Screens/CityScreen"), "city screen wired")
	assert_not_null(main.get_node_or_null("Screens/TechChooser"), "tech chooser wired")
	assert_not_null(main.get_node_or_null("Screens/PolicyScreen"), "policy screen wired")
	assert_not_null(main.get_node_or_null("Screens/DiplomacyScreen"), "diplomacy screen wired")
	assert_not_null(main.get_node_or_null("HUD/VBox/MenuBar"), "advisor menu bar present")
	assert_true(main.get_node("HUD/VBox/MenuBar").get_child_count() > 0,
		"the menu bar should build its advisor buttons")
	assert_true(main.get_facade().get_state().units.size() > 0,
		"the booted game should have starting units")
	get_tree().paused = false  # safety in case an overlay toggled pause

func test_pass_device_overlay_wiring() -> void:
	var scene = load("res://scenes/hotseat/pass_device_screen.tscn").instance()
	add_child_autofree(scene)

	# It must live on its own CanvasLayer (above the HUD's layer) so input reaches
	# the OK button instead of being swallowed by the HUD.
	assert_true(scene is CanvasLayer, "overlay must be a CanvasLayer")
	assert_true(scene.layer > 1, "overlay layer must be above the HUD CanvasLayer")

	scene.init(null)
	assert_false(scene._root.visible, "overlay starts hidden")
	assert_true(scene._button.is_connected("pressed", scene, "_on_ok_pressed"),
		"OK button must be connected to its dismiss handler")

	scene.show_for_player("Bob", 2)
	assert_true(scene._root.visible, "overlay is visible after show_for_player")
	assert_true(get_tree().paused, "the game is paused while the overlay is up")

	scene._on_ok_pressed()
	assert_false(scene._root.visible, "OK dismisses the overlay")
	assert_false(get_tree().paused, "OK resumes the game so the next turn proceeds")

	get_tree().paused = false  # safety: never leave the test tree paused
