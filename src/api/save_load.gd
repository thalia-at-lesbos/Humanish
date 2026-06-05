# Humanish — a turn-based 4X strategy game.
# Copyright (C) 2026 thalia-at-lesbos
# SPDX-License-Identifier: GPL-3.0-or-later
#
# This program is free software: you can redistribute it and/or modify it
# under the terms of the GNU General Public License as published by the Free
# Software Foundation, either version 3 of the License, or (at your option)
# any later version. See the LICENSE file for the full text and warranty
# disclaimer.

class_name SaveLoad

# Deterministic (de)serialization of GameState.
# Saves to/loads from a JSON string. The RNG state is embedded so that
# resuming from a save continues the exact same sequence.

static func save_to_string(gs: GameState) -> String:
	return JSON.print(gs.serialize())

static func load_from_string(json_str: String, db: DataDB) -> GameState:
	var result := JSON.parse(json_str)
	if result.error != OK:
		push_error("SaveLoad: JSON parse error: " + result.error_string)
		return null
	if not result.result is Dictionary:
		push_error("SaveLoad: root is not a Dictionary")
		return null
	return GameState.deserialize(result.result, db)

# Compute a simple hash of the serialized state for the determinism gate.
# Uses Godot's hash() built-in on the JSON string for a fast integer hash.
static func state_hash(gs: GameState) -> int:
	return save_to_string(gs).hash()
