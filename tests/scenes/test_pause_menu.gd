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

# Pause menu (§11 session/meta): the Escape-toggled in-game system menu offering
# Resume / Save / Load / New Game / Quit.

# Canary: a parse error in this UI script would otherwise report green (see the
# CLAUDE.md gotcha). can_instance() reports the compile state without throwing.
func test_pause_menu_script_compiles() -> void:
	var script = load("res://scenes/screens/pause_menu.gd")
	assert_true(script.can_instance(), "pause_menu.gd should compile and instance")

func test_pause_menu_builds_and_toggles() -> void:
	var facade = setup_facade(11)
	var pause = load("res://scenes/screens/pause_menu.gd").new()
	add_child_autofree(pause)
	pause.init(facade)
	assert_false(pause.visible, "Pause menu starts hidden")
	pause.toggle()
	assert_true(pause.visible, "toggle() opens the menu")
	pause.toggle()
	assert_false(pause.visible, "toggle() closes the menu again")

# Regression (issue 7): New Game from the pause menu must clear the SceneTree's
# pause flag before swapping scenes. paused is a SceneTree property that survives
# change_scene, so a game paused by the hotseat pass-device overlay would hand a
# paused tree to the freshly loaded title screen, whose buttons would never
# process — the menu looked hung. We can't drive change_scene in headless GUT, so
# assert the unpause directly: pause the tree, then run _on_new_game and confirm
# it cleared the flag. (change_scene is a no-op without a real main loop here.)
func test_pause_menu_new_game_unpauses_tree() -> void:
	var facade = setup_facade(11)
	var pause = load("res://scenes/screens/pause_menu.gd").new()
	add_child_autofree(pause)
	pause.init(facade)
	get_tree().paused = true
	pause._on_new_game()
	assert_false(get_tree().paused,
		"_on_new_game() should clear the tree pause before change_scene")
	# Leave the shared tree as we found it for the rest of the suite.
	get_tree().paused = false
