# Humanish — a turn-based 4X strategy game.
# Copyright (C) 2026 thalia-at-lesbos
# SPDX-License-Identifier: GPL-3.0-or-later
#
# This program is free software: you can redistribute it and/or modify it
# under the terms of the GNU General Public License as published by the Free
# Software Foundation, either version 3 of the License, or (at your option)
# any later version. See the LICENSE file for the full text and warranty
# disclaimer.

extends Control

# In-game debug menu, toggled with the '~'/'`' key (KEY_QUOTELEFT). Only active
# in a debug build. Shows a live debug-info panel plus an embedded console that
# runs the SAME DebugConsole engine as the terminal reader, with a couple of
# GUI-only map-view helpers ('reveal', 'fog') layered on top.
#
# It builds its UI programmatically (matching the other screens) and lives on the
# Screens CanvasLayer. While visible it captures input so clicks/keys feed the
# console instead of the map.

const TOGGLE_SCANCODE: int = KEY_QUOTELEFT   # the '~'/'`' key, Quake-console style

var _facade
var _console     # DebugConsole
var _log         # DebugLog
var _fog          # FogLayer (optional, for the view-only commands)

var _info: RichTextLabel
var _output: RichTextLabel
var _input_line: LineEdit

func init(facade, console, log_ref, fog = null) -> void:
	_facade = facade
	_console = console
	_log = log_ref
	_fog = fog
	visible = false
	mouse_filter = Control.MOUSE_FILTER_STOP
	anchor_right = 1.0
	anchor_bottom = 1.0
	_build_ui()
	if _log != null:
		_log.connect("appended", self, "_on_log_appended")

func _build_ui() -> void:
	var dim := ColorRect.new()
	dim.anchor_right = 1.0
	dim.anchor_bottom = 1.0
	dim.color = Color(0.04, 0.04, 0.06, 0.92)
	add_child(dim)

	var box := VBoxContainer.new()
	box.anchor_left = 0.04
	box.anchor_top = 0.04
	box.anchor_right = 0.96
	box.anchor_bottom = 0.96
	box.add_constant_override("separation", 8)
	add_child(box)

	var title := Label.new()
	title.text = "Debug Console  —  '~' to close,  type 'help' for commands"
	box.add_child(title)

	# Live game-state info panel.
	_info = RichTextLabel.new()
	_info.bbcode_enabled = false
	_info.scroll_active = false
	_info.rect_min_size = Vector2(0, 96)
	box.add_child(_info)

	var sep := HSeparator.new()
	box.add_child(sep)

	# Console + log feed.
	_output = RichTextLabel.new()
	_output.bbcode_enabled = false
	_output.scroll_following = true
	_output.size_flags_vertical = Control.SIZE_EXPAND_FILL
	box.add_child(_output)

	_input_line = LineEdit.new()
	_input_line.placeholder_text = "command…"
	_input_line.connect("text_entered", self, "_on_command_entered")
	box.add_child(_input_line)

	# Seed the output with whatever is already in the log.
	if _log != null:
		_output.text = _log.formatted(0)

# Grab '~' before anything else so it toggles the overlay (and never lands in the
# console's text field). While open, Escape also closes it (consumed here so it
# doesn't fall through to the pause menu). Inert outside a debug build.
func _input(event: InputEvent) -> void:
	if not OS.is_debug_build():
		return
	if not (event is InputEventKey) or not event.pressed or event.echo:
		return
	if event.scancode == TOGGLE_SCANCODE:
		toggle()
		get_tree().set_input_as_handled()
	elif visible and event.scancode == KEY_ESCAPE:
		visible = false
		get_tree().set_input_as_handled()

func toggle() -> void:
	visible = not visible
	if visible:
		_refresh_info()
		_input_line.grab_focus()

func _process(_delta: float) -> void:
	if visible:
		_refresh_info()

func _refresh_info() -> void:
	if _facade == null or _info == null:
		return
	var gs = _facade.get_state()
	if gs == null:
		_info.text = "(no game state)"
		return
	var p = gs.get_player(gs.current_player_id)
	var pname: String = (p.name if p != null else "world")
	var gold: int = (p.treasury if p != null else 0)
	var text: String = ""
	text += "turn: " + str(gs.turn_number) + " / " + str(gs.max_turns) + "\n"
	text += "current player: #" + str(gs.current_player_id) + " " + pname \
		+ "   gold: " + str(gold) + "\n"
	text += "players: " + str(gs.players.size()) \
		+ "   cities: " + str(gs.settlements.size()) \
		+ "   units: " + str(gs.units.size()) + "\n"
	text += "interface mode: " + str(_facade.get_interface_mode()) \
		+ "   winner: " + str(gs.winning_alliance_id) + "\n"
	text += "fps: " + str(Engine.get_frames_per_second())
	_info.text = text

func _on_command_entered(line: String) -> void:
	line = line.strip_edges()
	_input_line.clear()
	if line == "":
		return
	_append_output("> " + line)
	var out: String = _run(line)
	if out != "":
		_append_output(out)
	_input_line.grab_focus()

# Handle the GUI-only view helpers here, then delegate everything else to the
# shared console engine so the terminal and overlay stay in sync.
func _run(line: String) -> String:
	var first: String = String(line.split(" ", false)[0]).to_lower()
	match first:
		"reveal":
			if _fog != null and _fog.has_method("reveal_all"):
				_fog.reveal_all()
				return "fog of war revealed"
			return "no fog layer"
		"fog":
			if _fog != null and _facade != null:
				_fog.rebuild(_facade.get_state().current_player_id)
				return "fog restored"
			return "no fog layer"
	if _console == null:
		return "no console"
	return _console.execute(line)

func _append_output(text: String) -> void:
	if _output == null:
		return
	if _output.text != "":
		_output.text += "\n"
	_output.text += text

# Live-mirror new log lines into the output pane (skip console echoes, which we
# already print locally to avoid doubling them).
func _on_log_appended(entry: Dictionary) -> void:
	if _output == null:
		return
	if String(entry.get("category", "")) == "console":
		return
	_append_output("[" + str(entry.get("category", "")) + "] " + str(entry.get("text", "")))
