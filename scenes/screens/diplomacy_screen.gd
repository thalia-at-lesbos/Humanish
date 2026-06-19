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
# how they regard you (§7 attitude), any permanent-alliance relationship, and
# action buttons (Declare War / Make Peace / Propose Permanent Alliance / simple
# trade offers). A standing-deals panel lists active per-turn deals and lets you
# cancel one once its minimum duration has elapsed.

# A modest gift / per-turn offer the player can extend with one click (the rest of
# the deal space — techs, resources, cities — is reachable once a full trade table
# is built; these cover the common "warm a relationship" gestures).
const GIFT_GOLD: int = 50
const OFFER_GOLD_PER_TURN: int = 5

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

	# Only show players we have met (§7 first contact): a rival appears once either
	# side's unit/city has sighted the other's unit, city, or border. Contact is
	# permanent, so a met player stays listed thereafter. TurnEngine maintains the
	# per-alliance contacts; here we just read them.
	var any_shown: bool = false
	for p in gs.players:
		if p.id == my_p.id:
			continue
		var other_alliance = gs.get_player_alliance(p.id)
		if other_alliance == null:
			continue
		if my_alliance == null or not my_alliance.has_contact_with(other_alliance.id):
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

		# Subordination (§7 vassalage): are we their overlord, or they ours?
		var they_are_our_vassal: bool = other_alliance.is_subordinate_to == my_alliance.id \
			if my_alliance != null else false
		var we_are_their_vassal: bool = my_alliance != null \
			and my_alliance.is_subordinate_to == other_alliance.id

		# Relationship status label
		var status: String
		if they_are_our_vassal:
			status = "Our Vassal"
		elif we_are_their_vassal:
			status = "Our Overlord"
		elif at_war:
			status = "AT WAR"
		elif is_perm_ally:
			status = "Permanent Ally"
		else:
			status = "Peace"
		var status_lbl: Label = Label.new()
		status_lbl.text = status
		status_lbl.rect_min_size = Vector2(120, 0)
		row.add_child(status_lbl)

		# How this rival regards you (§7 attitude): the AI's own attitude toward the
		# viewing player, surfaced so the human can read the diplomatic mood.
		var attitude_lbl: Label = Label.new()
		var level: int = Diplomacy.attitude_level(gs, gs.db, p.id, my_p.id)
		attitude_lbl.text = "(" + Diplomacy.level_name(gs.db, level) + ")"
		attitude_lbl.rect_min_size = Vector2(90, 0)
		row.add_child(attitude_lbl)

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

			# Capitulate (§7 vassalage): only offered when this rival is crushing us
			# — at war and so much stronger that submission beats annihilation.
			if Vassalage.is_crushed_by(gs, gs.db, my_alliance, other_alliance):
				var cap_btn: Button = Button.new()
				cap_btn.text = "Capitulate"
				cap_btn.connect("pressed", self, "_on_capitulate", [other_alliance.id])
				row.add_child(cap_btn)

		# Release a vassal we hold back to independence (§7 vassalage).
		if they_are_our_vassal:
			var free_btn: Button = Button.new()
			free_btn.text = "Free Vassal"
			free_btn.connect("pressed", self, "_on_free_vassal", [other_alliance.id])
			row.add_child(free_btn)

		# Permanent-alliance proposal: only when the rule is on, both are at
		# peace, neither is already a permanent ally.
		if perm_alliances_enabled and not at_war and not is_perm_ally and my_alliance != null:
			var perm_btn: Button = Button.new()
			perm_btn.text = "Propose Permanent Alliance"
			perm_btn.connect("pressed", self, "_on_propose_permanent_alliance",
				[other_alliance.id])
			row.add_child(perm_btn)

		# Simple trade offers (§7): a one-off gift and a per-turn deal. They become a
		# standing deal (or instant transfer) when the other side accepts on its turn.
		if not at_war and my_alliance != null:
			var gift_btn: Button = Button.new()
			gift_btn.text = "Gift %dg" % GIFT_GOLD
			gift_btn.connect("pressed", self, "_on_gift", [other_alliance.id])
			row.add_child(gift_btn)

			var sub_btn: Button = Button.new()
			sub_btn.text = "Offer %dg/turn" % OFFER_GOLD_PER_TURN
			sub_btn.connect("pressed", self, "_on_offer_per_turn", [other_alliance.id])
			row.add_child(sub_btn)

		vbox.add_child(row)

	if not any_shown:
		var lbl: Label = Label.new()
		lbl.text = "(You have not met any other civilizations yet)"
		vbox.add_child(lbl)

	_build_deals(vbox, gs, my_alliance)
	_add_close(vbox)

# List every standing deal this player's alliance is party to, with a Cancel
# button enabled only once the deal's minimum duration has elapsed (§7).
func _build_deals(vbox: VBoxContainer, gs, my_alliance) -> void:
	if my_alliance == null:
		return
	var mine: Array = []
	for d in gs.deals:
		if int(d.get("a_alliance", -1)) == my_alliance.id or int(d.get("b_alliance", -1)) == my_alliance.id:
			mine.append(d)
	if mine.empty():
		return
	var header: Label = Label.new()
	header.text = "Standing deals"
	vbox.add_child(header)
	for d in mine:
		var row: HBoxContainer = HBoxContainer.new()
		var lbl: Label = Label.new()
		lbl.text = _deal_summary(d)
		lbl.rect_min_size = Vector2(260, 0)
		row.add_child(lbl)
		var btn: Button = Button.new()
		var ready_turn: int = int(d.get("start_turn", 0)) + int(d.get("min_duration", 0))
		if gs.turn_number >= ready_turn:
			btn.text = "Cancel"
			btn.connect("pressed", self, "_on_cancel_deal", [int(d.get("id", -1))])
		else:
			btn.text = "Locked (until turn %d)" % ready_turn
			btn.disabled = true
		row.add_child(btn)
		vbox.add_child(row)

# A short human-readable summary of a deal's recurring items.
func _deal_summary(d: Dictionary) -> String:
	var rec: Dictionary = d.get("recurring", {})
	var parts: Array = []
	var g_give: int = int(rec.get("give", {}).get("gold_per_turn", 0))
	var g_recv: int = int(rec.get("receive", {}).get("gold_per_turn", 0))
	if g_give > 0:
		parts.append("we send %dg/turn" % g_give)
	if g_recv > 0:
		parts.append("we receive %dg/turn" % g_recv)
	for r in rec.get("give", {}).get("resources", []):
		parts.append("we send " + str(r))
	for r in rec.get("receive", {}).get("resources", []):
		parts.append("we receive " + str(r))
	if parts.empty():
		return "Deal #%d" % int(d.get("id", -1))
	return "Deal #%d: %s" % [int(d.get("id", -1)), ", ".join(parts)]

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

func _on_gift(target_aid: int) -> void:
	var gs = _facade.get_state()
	_facade.apply_command(Commands.propose_trade(
		gs.current_player_id, target_aid, {"gold": GIFT_GOLD}, {}))
	rebuild()

func _on_offer_per_turn(target_aid: int) -> void:
	var gs = _facade.get_state()
	_facade.apply_command(Commands.propose_trade(
		gs.current_player_id, target_aid, {"gold_per_turn": OFFER_GOLD_PER_TURN}, {}))
	rebuild()

func _on_capitulate(overlord_aid: int) -> void:
	var gs = _facade.get_state()
	_facade.apply_command(Commands.set_subordination(gs.current_player_id, overlord_aid))
	rebuild()

func _on_free_vassal(vassal_aid: int) -> void:
	var gs = _facade.get_state()
	_facade.apply_command(Commands.free_vassal(gs.current_player_id, vassal_aid))
	rebuild()

func _on_cancel_deal(deal_id: int) -> void:
	var gs = _facade.get_state()
	_facade.apply_command(Commands.cancel_deal(gs.current_player_id, deal_id))
	rebuild()

func close_screen() -> void:
	_on_close()

func _on_close() -> void:
	visible = false
