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

# Shared scaffold for the simple, read-only advisor/info screens (§3.1, §11):
# an opaque backdrop, a scrolled list of text Labels, and a Close button. No art,
# just text and a plain colored rect. Concrete screens set `_title` and override
# `_populate(vbox)` to add their lines.

var _facade
var _title = "Info"

func init(facade) -> void:
	_facade = facade
	anchor_right = 1.0
	anchor_bottom = 1.0
	mouse_filter = Control.MOUSE_FILTER_STOP
	visible = false

func show_screen() -> void:
	visible = true
	rebuild()

func rebuild() -> void:
	for child in get_children():
		remove_child(child)
		child.free()

	var bg = ColorRect.new()
	bg.anchor_right = 1.0
	bg.anchor_bottom = 1.0
	bg.color = Color(0.10, 0.10, 0.13, 1.0)
	add_child(bg)

	var scroll = ScrollContainer.new()
	scroll.anchor_right = 1.0
	scroll.anchor_bottom = 1.0
	add_child(scroll)

	var vbox = VBoxContainer.new()
	vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(vbox)

	var title = Label.new()
	title.text = _title
	vbox.add_child(title)

	_populate(vbox)

	var close_btn = Button.new()
	close_btn.text = "Close"
	close_btn.connect("pressed", self, "_on_close")
	vbox.add_child(close_btn)

# Override in concrete screens to add the screen's content lines.
func _populate(vbox) -> void:
	pass

func _add_line(vbox, text) -> void:
	var lbl = Label.new()
	lbl.text = text
	vbox.add_child(lbl)

func close_screen() -> void:
	_on_close()

func _on_close() -> void:
	visible = false
