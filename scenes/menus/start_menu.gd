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

# Reuse the save directory constant so the menu and in-game screen never drift.
const SaveLoadScreen = preload("res://scenes/screens/save_load_screen.gd")

var _db
var _menu_box: VBoxContainer
var _load_box: VBoxContainer
var _setup_screen

func _ready() -> void:
	_db = load("res://src/core/data_db.gd").new()
	if not _db.load_all():
		push_error("DataDB load failed: " + str(_db.get_errors()))
	_build_ui()

func _build_ui() -> void:
	var bg := ColorRect.new()
	bg.anchor_right = 1.0
	bg.anchor_bottom = 1.0
	bg.color = Color(0.08, 0.08, 0.10)
	add_child(bg)

	_menu_box = VBoxContainer.new()
	_menu_box.anchor_left = 0.35
	_menu_box.anchor_top = 0.3
	_menu_box.anchor_right = 0.65
	_menu_box.anchor_bottom = 0.75
	_menu_box.add_constant_override("separation", 16)
	add_child(_menu_box)

	var title := Label.new()
	title.text = "HUMANISH"
	title.align = Label.ALIGN_CENTER
	_menu_box.add_child(title)

	var spacer := Control.new()
	spacer.rect_min_size = Vector2(0, 24)
	_menu_box.add_child(spacer)

	var new_game_btn := Button.new()
	new_game_btn.text = "New Game"
	new_game_btn.connect("pressed", self, "_on_new_game_pressed")
	_menu_box.add_child(new_game_btn)

	var load_game_btn := Button.new()
	load_game_btn.text = "Load Game"
	load_game_btn.connect("pressed", self, "_on_load_game_pressed")
	_menu_box.add_child(load_game_btn)

	var about_btn := Button.new()
	about_btn.text = "About"
	about_btn.connect("pressed", self, "_on_about_pressed")
	_menu_box.add_child(about_btn)

	var exit_btn := Button.new()
	exit_btn.text = "Exit"
	exit_btn.connect("pressed", self, "_on_exit_pressed")
	_menu_box.add_child(exit_btn)

func _on_about_pressed() -> void:
	var about = load("res://scenes/screens/about_screen.gd").new()
	add_child(about)
	about.init(null)   # the About screen needs no game state
	about.show_screen()

func _on_new_game_pressed() -> void:
	_menu_box.visible = false
	_setup_screen = load("res://scenes/setup/setup_screen.gd").new()
	_setup_screen.anchor_right = 1.0
	_setup_screen.anchor_bottom = 1.0
	add_child(_setup_screen)
	_setup_screen.init(_db, funcref(self, "_on_setup_complete"))

func _on_load_game_pressed() -> void:
	_menu_box.visible = false
	_build_load_ui()

func _build_load_ui() -> void:
	if _load_box != null:
		_load_box.queue_free()

	_load_box = VBoxContainer.new()
	_load_box.anchor_left = 0.3
	_load_box.anchor_top = 0.25
	_load_box.anchor_right = 0.7
	_load_box.anchor_bottom = 0.8
	_load_box.add_constant_override("separation", 10)
	add_child(_load_box)

	var title := Label.new()
	title.text = "Load Game"
	title.align = Label.ALIGN_CENTER
	_load_box.add_child(title)

	var saves := _list_saves()
	if saves.empty():
		var none_lbl := Label.new()
		none_lbl.text = "(no saved games found)"
		none_lbl.align = Label.ALIGN_CENTER
		_load_box.add_child(none_lbl)
	else:
		for filename in saves:
			var btn := Button.new()
			btn.text = filename
			btn.connect("pressed", self, "_on_load_file", [filename])
			_load_box.add_child(btn)

	var back_btn := Button.new()
	back_btn.text = "Back"
	back_btn.connect("pressed", self, "_on_load_back_pressed")
	_load_box.add_child(back_btn)

func _on_load_back_pressed() -> void:
	if _load_box != null:
		_load_box.queue_free()
		_load_box = null
	_menu_box.visible = true

func _on_load_file(filename: String) -> void:
	var file := File.new()
	if file.open(SaveLoadScreen.SAVE_DIR + filename, File.READ) != OK:
		push_error("StartMenu: could not open save: " + filename)
		return
	var json_str := file.get_as_text()
	file.close()

	var facade = load("res://src/api/sim_facade.gd").new()
	facade.init_for_load(_db)
	if not facade.load_save(json_str):
		push_error("StartMenu: failed to load save: " + filename)
		return
	_on_setup_complete(facade, _db)

func _list_saves() -> Array:
	var files: Array = []
	var dir := Directory.new()
	if dir.open(SaveLoadScreen.SAVE_DIR) == OK:
		dir.list_dir_begin(true, true)
		var fname := dir.get_next()
		while fname != "":
			if fname.ends_with(".sav"):
				files.append(fname)
			fname = dir.get_next()
		dir.list_dir_end()
	files.sort()
	return files

func _on_setup_complete(facade, db) -> void:
	var main_scene = load("res://scenes/main.tscn").instance()
	main_scene.init_with_facade(facade, db)
	get_tree().get_root().add_child(main_scene)
	get_tree().current_scene = main_scene
	queue_free()

func _on_exit_pressed() -> void:
	get_tree().quit()
