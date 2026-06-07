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

# Save/Load screen. Saves to user://saves/ and loads from there.

const SAVE_DIR: String = "user://saves/"
const QUICK_SAVE_NAME: String = "quicksave.sav"

var _facade
var _name_edit: LineEdit = null   # custom save filename field (rebuilt each show)

func init(facade) -> void:
	_facade = facade
	# Fill the screen and swallow input so this reads as a proper modal overlay
	# (the opaque backdrop is drawn in rebuild()) rather than a handful of stray
	# widgets floating over — and clicking through to — the live map.
	anchor_right = 1.0
	anchor_bottom = 1.0
	mouse_filter = Control.MOUSE_FILTER_STOP
	visible = false
	_ensure_dir()

func _ensure_dir() -> void:
	var dir: Directory = Directory.new()
	if not dir.dir_exists(SAVE_DIR):
		dir.make_dir(SAVE_DIR)

func show_screen() -> void:
	visible = true
	rebuild()

func rebuild() -> void:
	# Remove immediately (queue_free is deferred, which would leave the old
	# widgets — and a missing backdrop — rendered for a frame).
	for child in get_children():
		remove_child(child)
		child.free()

	# Opaque backdrop first so it sits behind the content and hides the map.
	var bg: ColorRect = ColorRect.new()
	bg.anchor_right = 1.0
	bg.anchor_bottom = 1.0
	bg.color = Color(0.10, 0.10, 0.13, 1.0)
	add_child(bg)

	var vbox: VBoxContainer = VBoxContainer.new()
	vbox.anchor_right = 1.0
	vbox.anchor_bottom = 1.0
	vbox.margin_left = 10
	vbox.margin_top = 10
	vbox.margin_right = -10
	vbox.margin_bottom = -10
	add_child(vbox)

	var title: Label = Label.new()
	title.text = "Save / Load"
	vbox.add_child(title)

	# Named-save row: type a filename and save under it (the ".sav" extension is
	# added automatically). This is the explicit "save as" the screen previously
	# lacked — before, the only options were the turn-stamped Quick Save and the F5
	# quicksave slot, so there was no way to choose a save's name.
	var save_row: HBoxContainer = HBoxContainer.new()
	var save_lbl: Label = Label.new()
	save_lbl.text = "File name:"
	save_row.add_child(save_lbl)
	_name_edit = LineEdit.new()
	_name_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_name_edit.placeholder_text = _default_save_name()
	_name_edit.connect("text_entered", self, "_on_save_named_text")
	save_row.add_child(_name_edit)
	var save_as_btn: Button = Button.new()
	save_as_btn.text = "Save"
	save_as_btn.connect("pressed", self, "_on_save_named")
	save_row.add_child(save_as_btn)
	vbox.add_child(save_row)

	# Quick save (turn-stamped) button — kept as a one-click convenience.
	var save_btn: Button = Button.new()
	save_btn.text = "Quick Save"
	save_btn.connect("pressed", self, "_on_save")
	vbox.add_child(save_btn)

	# File list with per-entry Load and Delete buttons.
	var files_lbl: Label = Label.new()
	files_lbl.text = "Saved games:"
	vbox.add_child(files_lbl)

	var dir_lbl: Label = Label.new()
	dir_lbl.text = "Save directory: " + OS.get_user_data_dir() + "/saves"
	dir_lbl.modulate = Color(0.7, 0.7, 0.7)
	vbox.add_child(dir_lbl)

	var files: Array = _list_saves()
	if files.empty():
		var none_lbl: Label = Label.new()
		none_lbl.text = "  (no saves found)"
		vbox.add_child(none_lbl)
	else:
		for filename in files:
			var row: HBoxContainer = HBoxContainer.new()
			var name_lbl: Label = Label.new()
			name_lbl.text = filename
			name_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			row.add_child(name_lbl)
			var load_btn: Button = Button.new()
			load_btn.text = "Load"
			load_btn.connect("pressed", self, "_on_load", [filename])
			row.add_child(load_btn)
			var delete_btn: Button = Button.new()
			delete_btn.text = "Delete"
			delete_btn.connect("pressed", self, "_on_delete", [filename])
			row.add_child(delete_btn)
			vbox.add_child(row)

	var close_btn: Button = Button.new()
	close_btn.text = "Close"
	close_btn.connect("pressed", self, "_on_close")
	vbox.add_child(close_btn)

# Immediate save to the quicksave slot, without opening the screen (F5).
func quick_save() -> void:
	_write_save(QUICK_SAVE_NAME)

# Immediate load of the quicksave slot, without opening the screen (F9).
func quick_load() -> void:
	_load_file(QUICK_SAVE_NAME)

func _on_save() -> void:
	if _facade == null:
		return
	_write_save(_default_save_name() + ".sav")
	# Defer the rebuild: it frees every child (incl. the button that emitted this
	# `pressed` signal), and freeing a node mid-emit crashes Godot 3 ("Object was
	# freed while a signal is being emitted from it"). Deferring lets the signal
	# finish first, then rebuilds on the next idle frame.
	call_deferred("rebuild")

# A sensible default file name (current turn) shown as the field's placeholder and
# used by Quick Save.
func _default_save_name() -> String:
	if _facade == null:
		return "save"
	var gs = _facade.get_state()
	return "turn" + str(gs.turn_number) if gs != null else "save"

# Save under the name typed in the field. Falls back to the default when blank.
func _on_save_named() -> void:
	if _facade == null or _name_edit == null:
		return
	var base: String = _sanitize_name(_name_edit.text)
	if base == "":
		base = _default_save_name()
	_write_save(base + ".sav")
	call_deferred("rebuild")   # deferred — see _on_save() for why

# Pressing Enter in the field saves too.
func _on_save_named_text(_text: String) -> void:
	_on_save_named()

# Reduce arbitrary user text to a safe bare file name: trim, drop any path parts
# and a trailing ".sav", and keep only filename-friendly characters.
func _sanitize_name(raw: String) -> String:
	var s: String = raw.strip_edges().get_file()   # strip any directory components
	if s.to_lower().ends_with(".sav"):
		s = s.substr(0, s.length() - 4)
	var out: String = ""
	for i in range(s.length()):
		var ch: String = s[i]
		var lower: String = ch.to_lower()
		var is_alpha: bool = lower >= "a" and lower <= "z"
		var is_digit: bool = ch >= "0" and ch <= "9"
		if is_alpha or is_digit or ch in "-_. ":
			out += ch
	return out.strip_edges()

func _on_load(filename: String) -> void:
	_load_file(filename)
	_on_close()

func _on_delete(filename: String) -> void:
	Directory.new().remove(SAVE_DIR + filename)
	call_deferred("rebuild")

# Write the current game state to SAVE_DIR + filename. Returns true on success.
func _write_save(filename: String) -> bool:
	if _facade == null:
		return false
	_ensure_dir()
	var json_str: String = _facade.save()
	var file: File = File.new()
	if file.open(SAVE_DIR + filename, File.WRITE) == OK:
		file.store_string(json_str)
		file.close()
		return true
	return false

# Load game state from SAVE_DIR + filename. Returns true on success.
func _load_file(filename: String) -> bool:
	if _facade == null:
		return false
	var file: File = File.new()
	if file.open(SAVE_DIR + filename, File.READ) == OK:
		var json_str: String = file.get_as_text()
		file.close()
		if _facade.load_save(json_str):
			_facade.get_dirty().mark_all()
			return true
	return false

func close_screen() -> void:
	_on_close()

func _on_close() -> void:
	visible = false

func _list_saves() -> Array:
	var files: Array = []
	var dir: Directory = Directory.new()
	if dir.open(SAVE_DIR) == OK:
		dir.list_dir_begin(true, true)
		var fname: String = dir.get_next()
		while fname != "":
			if fname.ends_with(".sav"):
				files.append(fname)
			fname = dir.get_next()
		dir.list_dir_end()
	return files
