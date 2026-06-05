# Humanish — a turn-based 4X strategy game.
# Copyright (C) 2026 thalia-at-lesbos
# SPDX-License-Identifier: GPL-3.0-or-later
#
# This program is free software: you can redistribute it and/or modify it
# under the terms of the GNU General Public License as published by the Free
# Software Foundation, either version 3 of the License, or (at your option)
# any later version. See the LICENSE file for the full text and warranty
# disclaimer.

class_name DebugLog
extends Reference

# A pure, capped ring buffer of debug log lines. No Node, no scene, no input —
# both the in-game overlay and the terminal console read/write through one of
# these instances (wired by scenes/main.gd). When enabled, every appended line
# is also mirrored to stdout so the launching terminal shows the same feed.
#
# This lives in src/core because it is foundational and side-effect free apart
# from the optional stdout mirror; it never touches GameState.

signal appended(entry)

const MAX_LINES: int = 500

# Gated by the host: scenes/main.gd sets this from OS.is_debug_build() (and clears
# it under headless/GUT runs) so release builds and the test harness stay silent.
var enabled: bool = true

var _lines: Array = []   # Array of {turn:int, category:String, text:String}

# Append one line. category is a short tag (e.g. "turn", "combat", "console").
# turn is the game turn it happened on, or -1 if not turn-scoped.
func append(category: String, text: String, turn: int = -1) -> void:
	if not enabled:
		return
	var entry: Dictionary = {"turn": turn, "category": category, "text": text}
	_lines.append(entry)
	if _lines.size() > MAX_LINES:
		_lines.pop_front()
	# Mirror to the launching terminal so the same feed is visible there.
	var prefix: String = ("T" + str(turn) + " ") if turn >= 0 else ""
	print("[DBG] ", prefix, "[", category, "] ", text)
	emit_signal("appended", entry)

func lines() -> Array:
	return _lines

func clear() -> void:
	_lines.clear()

# Render the last `count` lines as text (0 = all). Used by the overlay pane and
# by the console's `log` command.
func formatted(count: int = 0) -> String:
	var start: int = 0
	if count > 0 and _lines.size() > count:
		start = _lines.size() - count
	var out: String = ""
	for i in range(start, _lines.size()):
		var e: Dictionary = _lines[i]
		var t: int = int(e.get("turn", -1))
		var prefix: String = ("T" + str(t) + " ") if t >= 0 else ""
		out += prefix + "[" + str(e.get("category", "")) + "] " + str(e.get("text", "")) + "\n"
	return out
