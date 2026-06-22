# Humanish — a turn-based 4X strategy game.
# Copyright (C) 2026 thalia-at-lesbos
# SPDX-License-Identifier: GPL-3.0-or-later
#
# This program is free software: you can redistribute it and/or modify it
# under the terms of the GNU General Public License as published by the Free
# Software Foundation, either version 3 of the License, or (at your option)
# any later version. See the LICENSE file for the full text and warranty
# disclaimer.

extends "res://tests/support/sim_fixture.gd"

# Save/Load screen (§11 session/meta). Regression guard: the screen must render
# as a proper modal overlay — an opaque, full-rect backdrop that hides the live
# map — not a few stray widgets drawn straight over the map.

func _screen(facade):
	var sl = load("res://scenes/screens/save_load_screen.gd").new()
	add_child_autofree(sl)
	sl.init(facade)
	return sl

func _find_backdrop(node):
	for child in node.get_children():
		if child is ColorRect:
			return child
	return null

func test_show_screen_is_visible_with_content() -> void:
	var sl = _screen(setup_facade(91))
	sl.show_screen()
	assert_true(sl.visible, "Save/Load screen should be visible after show_screen()")
	assert_true(sl.get_child_count() > 0, "…and should build its content")

func test_screen_has_opaque_full_rect_backdrop() -> void:
	var sl = _screen(setup_facade(92))
	sl.show_screen()
	var bg = _find_backdrop(sl)
	assert_not_null(bg, "Screen must draw a backdrop so the map does not show through")
	assert_eq(bg.color.a, 1.0, "Backdrop must be fully opaque")
	assert_eq(bg.anchor_right, 1.0, "Backdrop spans the full width")
	assert_eq(bg.anchor_bottom, 1.0, "Backdrop spans the full height")

func test_screen_is_modal_full_rect() -> void:
	var sl = _screen(setup_facade(93))
	assert_eq(sl.mouse_filter, Control.MOUSE_FILTER_STOP,
		"Screen swallows input so clicks do not fall through to the map")
	assert_eq(sl.anchor_right, 1.0, "Screen fills the viewport width")
	assert_eq(sl.anchor_bottom, 1.0, "Screen fills the viewport height")

func test_close_hides_screen() -> void:
	var sl = _screen(setup_facade(94))
	sl.show_screen()
	assert_true(sl.visible, "shown")
	sl._on_close()
	assert_false(sl.visible, "Close hides the screen")

func test_named_save_writes_chosen_filename() -> void:
	var sl = _screen(setup_facade(96))
	sl.show_screen()
	sl._name_edit.text = "my campaign"
	sl._on_save_named()
	assert_true("my campaign.sav" in sl._list_saves(),
		"Saving with a custom name writes <name>.sav")
	# Cleanup so the temp user:// saves dir does not accrue across runs.
	Directory.new().remove(sl.SAVE_DIR + "my campaign.sav")

func test_named_save_sanitizes_and_defaults() -> void:
	var sl = _screen(setup_facade(97))
	# Strips a directory prefix and a trailing .sav, keeps friendly chars.
	assert_eq(sl._sanitize_name("../danger/Game_1.sav"), "Game_1",
		"Sanitizer drops path parts and the extension")
	# Blank field falls back to the turn-stamped default.
	sl.show_screen()
	sl._name_edit.text = "   "
	sl._on_save_named()
	var def = sl._default_save_name() + ".sav"
	assert_true(def in sl._list_saves(), "A blank name falls back to the default")
	Directory.new().remove(sl.SAVE_DIR + def)

func _find_button(node, text):
	for c in node.get_children():
		if c is Button and c.text == text:
			return c
		var found = _find_button(c, text)
		if found != null:
			return found
	return null

func test_pressing_save_does_not_free_widget_mid_signal() -> void:
	# Regression: _on_save* rebuilt synchronously, freeing the very button that was
	# emitting `pressed` — Godot 3 then aborts ("Object was freed while a signal is
	# being emitted from it"). The rebuild must be deferred so the press is safe.
	var sl = _screen(setup_facade(98))
	sl.show_screen()
	var btn = _find_button(sl, "Save")
	assert_not_null(btn, "the named-save button exists")
	btn.emit_signal("pressed")
	assert_true(is_instance_valid(btn),
		"the Save button is not freed during its own press (rebuild is deferred)")
	yield(get_tree(), "idle_frame")   # flush the deferred rebuild
	Directory.new().remove(sl.SAVE_DIR + sl._default_save_name() + ".sav")

func test_delete_removes_file_and_does_not_crash() -> void:
	var sl = _screen(setup_facade(99))
	sl.show_screen()
	sl._name_edit.text = "to_delete"
	sl._on_save_named()
	yield(get_tree(), "idle_frame")   # flush deferred rebuild after save
	assert_true("to_delete.sav" in sl._list_saves(), "File exists before delete")
	sl._on_delete("to_delete.sav")
	yield(get_tree(), "idle_frame")   # flush deferred rebuild after delete
	assert_false("to_delete.sav" in sl._list_saves(), "File gone after delete")

func test_file_list_shows_load_and_delete() -> void:
	var sl = _screen(setup_facade(100))
	sl.show_screen()
	sl._name_edit.text = "del_check"
	sl._on_save_named()
	yield(get_tree(), "idle_frame")
	sl.show_screen()
	assert_not_null(_find_button(sl, "Delete"), "Each save row should have a Delete button")
	assert_not_null(_find_button(sl, "Load"), "Each save row should have a Load button")
	Directory.new().remove(sl.SAVE_DIR + "del_check.sav")

func test_script_compiles() -> void:
	# Canary: GUT reports a suite green even when a scene script fails to parse, so
	# guard the compile state explicitly (the sort helpers added a static method).
	assert_true(load("res://scenes/screens/save_load_screen.gd").can_instance(),
		"save_load_screen.gd must compile cleanly")

func test_sort_entries_newest_first_orders_by_mtime_desc() -> void:
	# Pure helper: newest mtime first, ties broken by name ascending for stability.
	var SL = load("res://scenes/screens/save_load_screen.gd")
	var entries = [
		{"name": "old.sav", "mtime": 100},
		{"name": "newest.sav", "mtime": 300},
		{"name": "mid.sav", "mtime": 200},
	]
	assert_eq(SL.sort_entries_newest_first(entries),
		["newest.sav", "mid.sav", "old.sav"],
		"Newest-modified file is listed first")

func test_sort_entries_breaks_ties_by_name() -> void:
	var SL = load("res://scenes/screens/save_load_screen.gd")
	var entries = [
		{"name": "b.sav", "mtime": 500},
		{"name": "a.sav", "mtime": 500},
	]
	assert_eq(SL.sort_entries_newest_first(entries), ["a.sav", "b.sav"],
		"Equal mtimes fall back to name order for a stable, deterministic list")

func test_rebuild_is_synchronous_and_replaces_content() -> void:
	# rebuild() must not leave stale children behind (it once deferred frees and
	# yielded a frame, which flashed the old widgets / a missing backdrop).
	var sl = _screen(setup_facade(95))
	sl.show_screen()
	var first_count = sl.get_child_count()
	sl.rebuild()
	assert_eq(sl.get_child_count(), first_count,
		"A rebuild replaces the content in place, leaving no duplicate widgets")
	assert_not_null(_find_backdrop(sl), "…and the backdrop is rebuilt")
