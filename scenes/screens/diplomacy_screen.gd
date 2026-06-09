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

# Diplomacy screen: shows all other civilizations with their war/peace status,
# any permanent-alliance relationship, and action buttons (Declare War / Make
# Peace / Propose Permanent Alliance when the rule is enabled).

var _facade

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

	var vbox: VBoxContainer = VBoxContainer.new()
	vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(vbox)

	var gs = _facade.get_state()
	var my_p = gs.get_player(gs.current_player_id)
	if my_p == null:
		_add_close(vbox)
		return

	var my_alliance = gs.get_player_alliance(my_p.id)
	var perm_alliances_enabled: bool = bool(gs.permanent_alliances)

	var title: Label = Label.new()
	title.text = "Diplomacy — " + my_p.name
	vbox.add_child(title)

	# Show every other player regardless of contact; alliances start with no
	# contacts so filtering on contacts would hide every row at game start.
	var any_shown: bool = false
	for p in gs.players:
		if p.id == my_p.id:
			continue
		var other_alliance = gs.get_player_alliance(p.id)
		if other_alliance == null:
			continue
		any_shown = true

		var row: HBoxContainer = HBoxContainer.new()

		var name_lbl: Label = Label.new()
		name_lbl.text = p.name
		name_lbl.rect_min_size = Vector2(120, 0)
		row.add_child(name_lbl)

		var at_war: bool = gs.are_at_war(my_p.id, p.id)

		# Permanent-alliance status (stored on the Alliance as a set of
		# allied alliance IDs, added by the PROPOSE_PERMANENT_ALLIANCE command).
		var is_perm_ally: bool = false
		if my_alliance != null:
			is_perm_ally = other_alliance.id in my_alliance.permanent_allies

		# Relationship status label
		var status: String
		if at_war:
			status = "AT WAR"
		elif is_perm_ally:
			status = "Permanent Ally"
		else:
			status = "Peace"
		var status_lbl: Label = Label.new()
		status_lbl.text = status
		status_lbl.rect_min_size = Vector2(120, 0)
		row.add_child(status_lbl)

		# Action buttons
		if not at_war and not is_perm_ally and my_alliance != null:
			var war_btn: Button = Button.new()
			war_btn.text = "Declare War"
			war_btn.connect("pressed", self, "_on_declare_war", [other_alliance.id])
			row.add_child(war_btn)

		if at_war and my_alliance != null:
			var peace_btn: Button = Button.new()
			peace_btn.text = "Make Peace"
			peace_btn.connect("pressed", self, "_on_make_peace", [other_alliance.id])
			row.add_child(peace_btn)

		# Permanent-alliance proposal: only when the rule is on, both are at
		# peace, neither is already a permanent ally.
		if perm_alliances_enabled and not at_war and not is_perm_ally and my_alliance != null:
			var perm_btn: Button = Button.new()
			perm_btn.text = "Propose Permanent Alliance"
			perm_btn.connect("pressed", self, "_on_propose_permanent_alliance",
				[other_alliance.id])
			row.add_child(perm_btn)

		vbox.add_child(row)

	if not any_shown:
		var lbl: Label = Label.new()
		lbl.text = "(No other civilizations)"
		vbox.add_child(lbl)

	_add_close(vbox)

func _add_close(vbox: VBoxContainer) -> void:
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

func _on_propose_permanent_alliance(target_aid: int) -> void:
	var gs = _facade.get_state()
	_facade.apply_command(Commands.propose_permanent_alliance(gs.current_player_id, target_aid))
	rebuild()

func close_screen() -> void:
	_on_close()

func _on_close() -> void:
	visible = false
