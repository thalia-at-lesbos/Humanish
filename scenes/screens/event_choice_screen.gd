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

# Modal popup that surfaces a mandatory random-event / quest-reward CHOICE (§9, §4)
# to the local human. The facade parks the pre-rolled branches in
# pending_event_choices and refuses End Turn until one is picked; this screen is
# the presentation half of that contract. It is a pure SimFacade *client* — it
# reads the pending choice (handed to it as a descriptor) and routes the answer
# back through apply_command(RESOLVE_EVENT); it never mutates sim state itself.
#
# Driven by TurnPrompts as the first item in the start-of-turn chooser chain, so a
# pending decision is always answered before research / production prompts. Wired
# only in solo/hotseat play (remote turns are server-driven).

signal closed

var _facade
var _event_id: String = ""

func init(facade) -> void:
	_facade = facade
	anchor_right = 1.0
	anchor_bottom = 1.0
	mouse_filter = Control.MOUSE_FILTER_STOP
	visible = false

# descriptor: { event_id, name, text, choices: [{id, text}] }
func show_event(descriptor: Dictionary) -> void:
	_event_id = str(descriptor.get("event_id", ""))
	visible = true
	_rebuild(descriptor)

func _rebuild(descriptor: Dictionary) -> void:
	for child in get_children():
		child.queue_free()
	# Opaque backdrop that swallows clicks to the board beneath.
	var bg: ColorRect = ColorRect.new()
	bg.anchor_right = 1.0
	bg.anchor_bottom = 1.0
	bg.color = Color(0.0, 0.0, 0.0, 0.75)
	bg.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(bg)
	# Centred card.
	var panel: PanelContainer = PanelContainer.new()
	panel.anchor_left = 0.2
	panel.anchor_right = 0.8
	panel.anchor_top = 0.2
	panel.anchor_bottom = 0.8
	add_child(panel)
	var vbox: VBoxContainer = VBoxContainer.new()
	vbox.size_flags_vertical = Control.SIZE_EXPAND_FILL
	panel.add_child(vbox)
	var title_lbl: Label = Label.new()
	title_lbl.text = str(descriptor.get("name", "Event"))
	title_lbl.align = Label.ALIGN_CENTER
	vbox.add_child(title_lbl)
	vbox.add_child(HSeparator.new())
	var body_lbl: Label = Label.new()
	body_lbl.text = str(descriptor.get("text", ""))
	body_lbl.autowrap = true
	body_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	vbox.add_child(body_lbl)
	vbox.add_child(HSeparator.new())
	for ch in descriptor.get("choices", []):
		var btn: Button = Button.new()
		btn.text = str(ch.get("text", ""))
		btn.focus_mode = Control.FOCUS_NONE
		btn.connect("pressed", self, "_on_choice", [str(ch.get("id", ""))])
		vbox.add_child(btn)

func _on_choice(choice_id: String) -> void:
	if _facade == null:
		return
	var gs = _facade.get_state()
	if gs == null:
		return
	_facade.apply_command(Commands.resolve_event(gs.current_player_id, _event_id, choice_id))
	visible = false
	emit_signal("closed")
