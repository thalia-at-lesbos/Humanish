# Humanish — a turn-based 4X strategy game.
# Copyright (C) 2026 thalia-at-lesbos
# SPDX-License-Identifier: GPL-3.0-or-later
#
# This program is free software: you can redistribute it and/or modify it
# under the terms of the GNU General Public License as published by the Free
# Software Foundation, either version 3 of the License, or (at your option)
# any later version. See the LICENSE file for the full text and warranty
# disclaimer.

extends "res://scenes/screens/info_screen.gd"

# Options (§3.1 OPEN_OPTIONS, §11): a minimal options panel. Currently exposes
# the score-display toggle as an action button routed through the command
# pipeline (DO_CONTROL → TOGGLE_SCORE).

func init(facade) -> void:
	_title = "Options"
	.init(facade)

func _populate(vbox) -> void:
	_add_line(vbox, "Display:")
	var score_btn = Button.new()
	score_btn.text = "Toggle Score Display"
	score_btn.connect("pressed", self, "_on_toggle_score")
	vbox.add_child(score_btn)
	var minimap_btn = Button.new()
	minimap_btn.text = "Toggle Minimap"
	minimap_btn.connect("pressed", self, "_on_toggle_minimap")
	vbox.add_child(minimap_btn)
	# Debug-only: fog of war toggle.  Uses the same interactive-debug-build guard
	# as main.gd._debug_active() — only visible in a windowed debug build, never
	# in release exports or under the headless GUT runner.
	if _debug_active():
		_add_line(vbox, "Debug:")
		var fog_btn = Button.new()
		fog_btn.text = "Toggle Fog of War"
		fog_btn.connect("pressed", self, "_on_toggle_fog")
		vbox.add_child(fog_btn)

# Returns true only in an interactive windowed debug build (mirrors main.gd).
func _debug_active() -> bool:
	if not OS.is_debug_build():
		return false
	for arg in OS.get_cmdline_args():
		if arg == "--no-window" or arg.find("gut_cmdln") != -1:
			return false
	return true

func _on_toggle_score() -> void:
	var gs = _facade.get_state()
	_facade.apply_command(Commands.do_control(
		gs.current_player_id, IDs.ControlType.TOGGLE_SCORE))

func _on_toggle_minimap() -> void:
	var gs = _facade.get_state()
	_facade.apply_command(Commands.do_control(
		gs.current_player_id, IDs.ControlType.TOGGLE_MINIMAP))

func _on_toggle_fog() -> void:
	var gs = _facade.get_state()
	_facade.apply_command(Commands.do_control(
		gs.current_player_id, IDs.ControlType.TOGGLE_FOG))
