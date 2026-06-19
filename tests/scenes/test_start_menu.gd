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

# StartMenu / main entry-point canaries. These scripts run randomize() in _ready()
# so the default seed chooser varies per launch (the new-map-variance fix); a parse
# error there would silently disable New Game, so guard their compile state — GUT
# reports a suite green even when a scene script fails to load.

func test_start_menu_script_compiles() -> void:
	assert_true(load("res://scenes/menus/start_menu.gd").can_instance(),
		"start_menu.gd must compile cleanly")

func test_main_script_compiles() -> void:
	assert_true(load("res://scenes/main.gd").can_instance(),
		"main.gd must compile cleanly")
