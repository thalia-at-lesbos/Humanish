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

# Espionage mission popup (§7, §15.5). Shown when the player clicks
# "Select Mission…" on the Espionage screen for a target alliance.
# Lists the mission catalogue (data/espionage_missions.json) with each mission's
# EP cost and interception risk; a button is disabled when the current player
# lacks enough points or the mission's target gate does not hold. Choosing a
# mission fires it immediately and closes the popup; Abort closes it without
# acting.
#
# Usage:
#   var menu = load("res://scenes/screens/espionage_menu.gd").new()
#   add_child(menu)
#   menu.init(facade, target_alliance_id, on_done_callback)
#
# on_done_callback() is called after any action (mission fired or abort) so
# the parent screen can rebuild.

var _facade
var _alliance_id: int = -1
var _on_done  # FuncRef — called after close

func init(facade, alliance_id: int, on_done) -> void:
	_facade = facade
	_alliance_id = alliance_id
	_on_done = on_done
	anchor_right = 1.0
	anchor_bottom = 1.0
	mouse_filter = Control.MOUSE_FILTER_STOP
	_build()

func _build() -> void:
	for child in get_children():
		remove_child(child)
		child.free()

	# Semi-transparent backdrop dims the screen behind the popup.
	var shade := ColorRect.new()
	shade.anchor_right = 1.0
	shade.anchor_bottom = 1.0
	shade.color = Color(0.0, 0.0, 0.0, 0.6)
	add_child(shade)

	# Centred panel.
	var panel := PanelContainer.new()
	panel.anchor_left = 0.25
	panel.anchor_top = 0.2
	panel.anchor_right = 0.75
	panel.anchor_bottom = 0.8
	add_child(panel)

	var vbox := VBoxContainer.new()
	vbox.add_constant_override("separation", 10)
	panel.add_child(vbox)

	# Header.
	var title_lbl := Label.new()
	title_lbl.text = "Espionage Mission"
	title_lbl.align = Label.ALIGN_CENTER
	vbox.add_child(title_lbl)

	if _facade == null:
		_add_abort(vbox)
		return

	var gs = _facade.get_state()
	var p = gs.get_player(gs.current_player_id) if gs != null else null
	var target: Alliance = gs.get_alliance(_alliance_id) if gs != null else null

	# Target alliance description (first member's name, or numeric id fallback).
	var target_label: String = "Alliance " + str(_alliance_id)
	if target != null and not target.member_player_ids.empty():
		var first = gs.get_player(int(target.member_player_ids[0]))
		if first != null:
			target_label = first.name

	var target_lbl := Label.new()
	target_lbl.text = "Target: " + target_label
	target_lbl.align = Label.ALIGN_CENTER
	vbox.add_child(target_lbl)

	# Current EP banked against this target.
	var have: int = int(p.intel_points.get(_alliance_id, 0)) if p != null else 0

	var ep_lbl := Label.new()
	ep_lbl.text = "Your EP vs. target: %d" % have
	ep_lbl.align = Label.ALIGN_CENTER
	vbox.add_child(ep_lbl)

	# Separator.
	vbox.add_child(HSeparator.new())

	# One button per catalogue mission, with its own cost and interception risk.
	# Disabled when the player cannot afford it or its target gate does not hold.
	for opt in _facade.espionage_mission_options(_alliance_id):
		var btn := Button.new()
		btn.text = "%s  (cost %d EP · Interception %d%%)" % [
			opt["name"], int(opt["cost"]), int(opt["interception"])]
		btn.disabled = not (bool(opt["affordable"]) and bool(opt["available"]))
		btn.connect("pressed", self, "_on_mission", [str(opt["id"])])
		vbox.add_child(btn)

	vbox.add_child(HSeparator.new())
	_add_abort(vbox)

func _add_abort(vbox: VBoxContainer) -> void:
	var abort_btn := Button.new()
	abort_btn.text = "Abort"
	abort_btn.connect("pressed", self, "_on_abort")
	vbox.add_child(abort_btn)

func _on_mission(mission: String) -> void:
	if _facade != null:
		var gs = _facade.get_state()
		_facade.apply_command(Commands.espionage_mission(
			gs.current_player_id, _alliance_id, mission))
	_close()

func _on_abort() -> void:
	_close()

func _close() -> void:
	if _on_done != null and _on_done.is_valid():
		_on_done.call_func()
	queue_free()
