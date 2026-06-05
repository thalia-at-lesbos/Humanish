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

# System / pause menu. Opened with Escape (ControlType.OPEN_MENU). Offers Save,
# Load, New Game and Quit; Save/Load defer to the shared SaveLoadScreen so file
# handling lives in one place, and New Game returns to the title screen. Pressing
# Escape while it is open closes it again (toggle).

var _facade
var _save_load_screen

func init(facade) -> void:
	_facade = facade
	visible = false
	_build_ui()

# Hand the menu the shared save/load screen so its Save/Load buttons can open it.
func set_save_load_screen(screen) -> void:
	_save_load_screen = screen

# Escape toggles the menu: open when hidden, close when already showing.
func toggle() -> void:
	visible = not visible

func show_screen() -> void:
	visible = true

func _build_ui() -> void:
	var dim := ColorRect.new()
	dim.anchor_right = 1.0
	dim.anchor_bottom = 1.0
	dim.color = Color(0, 0, 0, 0.6)
	add_child(dim)

	var box := VBoxContainer.new()
	box.anchor_left = 0.4
	box.anchor_top = 0.32
	box.anchor_right = 0.6
	box.anchor_bottom = 0.68
	box.add_constant_override("separation", 14)
	add_child(box)

	var title := Label.new()
	title.text = "Paused"
	title.align = Label.ALIGN_CENTER
	box.add_child(title)

	var resume_btn := Button.new()
	resume_btn.text = "Resume"
	resume_btn.connect("pressed", self, "_on_resume")
	box.add_child(resume_btn)

	var save_btn := Button.new()
	save_btn.text = "Save Game"
	save_btn.connect("pressed", self, "_on_save")
	box.add_child(save_btn)

	var load_btn := Button.new()
	load_btn.text = "Load Game"
	load_btn.connect("pressed", self, "_on_load")
	box.add_child(load_btn)

	var new_game_btn := Button.new()
	new_game_btn.text = "New Game"
	new_game_btn.connect("pressed", self, "_on_new_game")
	box.add_child(new_game_btn)

	var quit_btn := Button.new()
	quit_btn.text = "Quit to Desktop"
	quit_btn.connect("pressed", self, "_on_quit")
	box.add_child(quit_btn)

func _on_resume() -> void:
	visible = false

func _on_save() -> void:
	visible = false
	if _save_load_screen != null:
		_save_load_screen.show_screen()

func _on_load() -> void:
	visible = false
	if _save_load_screen != null:
		_save_load_screen.show_screen()

# Tear down the current game and return to the title screen, where a new game is
# configured (New Game / Load Game). change_scene frees this scene tree for us.
func _on_new_game() -> void:
	visible = false
	get_tree().change_scene("res://scenes/menus/start_menu.tscn")

func _on_quit() -> void:
	get_tree().quit()
