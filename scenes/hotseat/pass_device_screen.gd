# Humanish — a turn-based 4X strategy game.
# Copyright (C) 2026 thalia-at-lesbos
# SPDX-License-Identifier: GPL-3.0-or-later
#
# This program is free software: you can redistribute it and/or modify it
# under the terms of the GNU General Public License as published by the Free
# Software Foundation, either version 3 of the License, or (at your option)
# any later version. See the LICENSE file for the full text and warranty
# disclaimer.

extends CanvasLayer

# Full-screen overlay shown between hotseat turns so the outgoing player cannot
# see the incoming player's state.
#
# It lives on a high CanvasLayer (layer 128) so it draws ABOVE the HUD's own
# CanvasLayer — previously it was a plain Control on the base canvas, so the HUD
# rendered over it and the HUD's full-screen container swallowed the clicks,
# which is why the OK button "did nothing" and the turn appeared not to advance.
#
# While visible it pauses the scene tree (this node is PAUSE_MODE_PROCESS via the
# scene) so no stray world clicks or End-Turn hotkeys leak through to the game
# underneath; pressing OK unpauses and hides it.

var _facade

onready var _root: Control = $Root
onready var _label: Label = $Root/VBox/Label
onready var _button: Button = $Root/VBox/OKButton

func _ready() -> void:
	if _button != null and not _button.is_connected("pressed", self, "_on_ok_pressed"):
		_button.connect("pressed", self, "_on_ok_pressed")
	_set_shown(false)

func init(facade) -> void:
	_facade = facade
	_set_shown(false)

func show_for_player(player_name: String, _player_id: int) -> void:
	if _label != null:
		_label.text = "Pass the device to\n" + player_name
	# Restore the normal OK handler in case a previous game-over rewired it.
	if _button != null:
		_button.text = "OK"
		_disconnect_quit()
		if not _button.is_connected("pressed", self, "_on_ok_pressed"):
			_button.connect("pressed", self, "_on_ok_pressed")
	_set_shown(true)

func show_game_over(alliance_id: int, gs) -> void:
	if _label != null:
		var winner_name: String = "Unknown"
		for p in gs.players:
			if p.alliance_id == alliance_id:
				winner_name = p.name
				break
		_label.text = "Game Over!\n" + winner_name + " wins!"
	if _button != null:
		_button.text = "Quit"
		if _button.is_connected("pressed", self, "_on_ok_pressed"):
			_button.disconnect("pressed", self, "_on_ok_pressed")
		if not _button.is_connected("pressed", get_tree(), "quit"):
			_button.connect("pressed", get_tree(), "quit")
	_set_shown(true)

func _on_ok_pressed() -> void:
	_set_shown(false)

# Toggle visibility and pause state together so the rest of the game is frozen
# (and its input blocked) exactly while the overlay is up.
func _set_shown(shown: bool) -> void:
	if _root != null:
		_root.visible = shown
	if is_inside_tree():
		get_tree().paused = shown

func _disconnect_quit() -> void:
	if _button != null and _button.is_connected("pressed", get_tree(), "quit"):
		_button.disconnect("pressed", get_tree(), "quit")
