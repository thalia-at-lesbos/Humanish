# Humanish — a turn-based 4X strategy game.
# Copyright (C) 2026 thalia-at-lesbos
# SPDX-License-Identifier: GPL-3.0-or-later
#
# This program is free software: you can redistribute it and/or modify it
# under the terms of the GNU General Public License as published by the Free
# Software Foundation, either version 3 of the License, or (at your option)
# any later version. See the LICENSE file for the full text and warranty
# disclaimer.

extends Reference

# Loads key→ControlType bindings from data/hotkeys.json.
# Keys in the JSON are scancode integers (as strings).
# Format: {"scancode": {"shift": bool, "ctrl": bool, "action": ControlType int}}

var _bindings: Dictionary = {}   # key: "scancode_shift_ctrl" → ControlType int

func load_bindings() -> void:
	var file: File = File.new()
	if file.open("res://data/hotkeys.json", File.READ) != OK:
		push_warning("hotkeys.json not found; using empty hotkey map")
		return
	var text: String = file.get_as_text()
	file.close()
	var result = JSON.parse(text)
	if result.error != OK:
		push_warning("hotkeys.json parse error")
		return
	var data: Dictionary = result.result
	for scancode_str in data:
		var entry: Dictionary = data[scancode_str]
		var shift: bool = bool(entry.get("shift", false))
		var ctrl: bool = bool(entry.get("ctrl", false))
		var action: int = int(entry.get("action", -1))
		if action >= 0:
			var key: String = scancode_str + "_" + str(shift) + "_" + str(ctrl)
			_bindings[key] = action

func lookup(scancode: int, shift: bool, ctrl: bool) -> int:
	var key: String = str(scancode) + "_" + str(shift) + "_" + str(ctrl)
	return _bindings.get(key, -1)
