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

# Canary for the fog-of-war overlay. It now drives the shared Visibility helper
# (terrain-aware sight) instead of an inline Manhattan loop; this guards against a
# parse/compile error in the refactored script that GUT would otherwise swallow.

func test_fog_layer_script_compiles() -> void:
	assert_true(load("res://scenes/world/fog_layer.gd").can_instance(),
		"fog_layer.gd must compile (terrain-aware sight refactor)")

func test_visibility_helper_compiles() -> void:
	assert_true(load("res://src/world/visibility.gd").can_instance(),
		"Visibility helper must compile")
