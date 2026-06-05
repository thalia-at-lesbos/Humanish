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

# Diplomacy screen: shows known players with war/peace status.
# Declare War and Make Peace buttons for Phase 6 scope.

var _facade

func init(facade) -> void:
	_facade = facade
	visible = false

func show_screen() -> void:
	visible = true
	rebuild()

func rebuild() -> void:
	for child in get_children():
		child.queue_free()
	yield(get_tree(), "idle_frame")

	var gs = _facade.get_state()
	var my_p = gs.get_player(gs.current_player_id)
	if my_p == null:
		return
	var my_alliance = gs.get_player_alliance(my_p.id)

	var vbox: VBoxContainer = VBoxContainer.new()
	vbox.anchor_right = 1.0
	vbox.anchor_bottom = 1.0
	vbox.margin_left = 10
	vbox.margin_top = 10
	vbox.margin_right = -10
	vbox.margin_bottom = -10
	add_child(vbox)

	var title: Label = Label.new()
	title.text = "Diplomacy — " + my_p.name
	vbox.add_child(title)

	for p in gs.players:
		if p.id == my_p.id:
			continue
		var other_alliance = gs.get_player_alliance(p.id)
		if other_alliance == null:
			continue
		# Only show known players (contacted alliances)
		if my_alliance != null and not my_alliance.has_contact_with(other_alliance.id) and \
				(my_alliance == null or not my_alliance.id == other_alliance.id):
			continue

		var row: HBoxContainer = HBoxContainer.new()
		var name_lbl: Label = Label.new()
		name_lbl.text = p.name
		name_lbl.rect_min_size = Vector2(100, 0)
		row.add_child(name_lbl)

		var at_war: bool = my_alliance != null and my_alliance.id in other_alliance.at_war_with or \
			other_alliance != null and other_alliance.id in (my_alliance.at_war_with if my_alliance else [])

		var status_lbl: Label = Label.new()
		status_lbl.text = "AT WAR" if at_war else "Peace"
		row.add_child(status_lbl)

		if not at_war and other_alliance != null:
			var war_btn: Button = Button.new()
			war_btn.text = "Declare War"
			war_btn.connect("pressed", self, "_on_declare_war", [other_alliance.id])
			row.add_child(war_btn)
		elif at_war and other_alliance != null:
			var peace_btn: Button = Button.new()
			peace_btn.text = "Make Peace"
			peace_btn.connect("pressed", self, "_on_make_peace", [other_alliance.id])
			row.add_child(peace_btn)

		vbox.add_child(row)

	var close_btn: Button = Button.new()
	close_btn.text = "Close"
	close_btn.connect("pressed", self, "_on_close")
	vbox.add_child(close_btn)

func _on_declare_war(target_aid: int) -> void:
	var gs = _facade.get_state()
	_facade.apply_command(Commands.declare_war(gs.current_player_id, target_aid))
	rebuild()

func _on_make_peace(target_aid: int) -> void:
	var gs = _facade.get_state()
	_facade.apply_command(Commands.make_peace(gs.current_player_id, target_aid))
	rebuild()

func _on_close() -> void:
	visible = false
