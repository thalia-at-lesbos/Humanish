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

# DiplomacyScreen (§7): the trade/attitude table builds against a real facade and
# its cancel/offer actions route back through apply_command.

func _screen(facade):
	var screen = load("res://scenes/screens/diplomacy_screen.gd").new()
	add_child_autofree(screen)
	screen.init(facade)
	return screen

# Canary: the script must compile so a parse error cannot hide behind a green run
# (GUT reports green even when a scene script fails to load).
func test_diplomacy_screen_script_compiles() -> void:
	assert_true(load("res://scenes/screens/diplomacy_screen.gd").can_instance(),
		"diplomacy_screen.gd must compile cleanly")

func _recurse_text(node) -> String:
	var out := ""
	if node is Label or node is Button:
		out += str(node.text) + "\n"
	for c in node.get_children():
		out += _recurse_text(c)
	return out

func test_screen_shows_attitude_and_offer_buttons() -> void:
	var facade = setup_facade(91, "small", [
		{"name": "A", "leader_id": "", "traits": [], "starting_gold": 50},
		{"name": "B", "leader_id": "", "traits": [], "starting_gold": 50}
	], ["time"])
	var gs = facade.get_state()
	# Force mutual contact so the rival is listed.
	gs.current_player_id = gs.players[0].id
	gs.get_alliance(gs.players[0].alliance_id).contacts.append(gs.players[1].alliance_id)
	var screen = _screen(facade)
	screen.show_screen()
	var text: String = _recurse_text(screen)
	assert_true("Gift" in text, "an offer button is shown for a met rival")
	# Attitude appears parenthesised (e.g. "(cautious)").
	assert_true("(" in text and ")" in text, "the rival's attitude is shown")

func test_open_borders_button_hidden_without_writing() -> void:
	var facade = setup_facade(93, "small", [
		{"name": "A", "leader_id": "", "traits": [], "starting_gold": 50},
		{"name": "B", "leader_id": "", "traits": [], "starting_gold": 50}
	], ["time"])
	var gs = facade.get_state()
	gs.current_player_id = gs.players[0].id
	gs.get_alliance(gs.players[0].alliance_id).contacts.append(gs.players[1].alliance_id)
	var screen = _screen(facade)
	screen.show_screen()
	assert_false("Open Borders" in _recurse_text(screen),
		"the open-borders button is hidden when the player lacks Writing")

func test_open_borders_button_routes_command_with_writing() -> void:
	var facade = setup_facade(94, "small", [
		{"name": "A", "leader_id": "", "traits": [], "starting_gold": 50},
		{"name": "B", "leader_id": "", "traits": [], "starting_gold": 50}
	], ["time"])
	var gs = facade.get_state()
	var p0 = gs.players[0]
	gs.current_player_id = p0.id
	p0.technologies.append("writing")
	gs.get_alliance(p0.alliance_id).contacts.append(gs.players[1].alliance_id)
	var screen = _screen(facade)
	screen.show_screen()
	assert_true("Open Borders" in _recurse_text(screen),
		"with Writing the open-borders button appears")
	# Driving the handler routes a proposal through apply_command.
	screen._on_open_borders(gs.players[1].alliance_id)
	assert_eq(gs.get_alliance(p0.alliance_id).pending_trades.size(), 1,
		"the proposal is queued as a pending trade")

func test_cancel_button_routes_command() -> void:
	var facade = setup_facade(92, "small", [
		{"name": "A", "leader_id": "", "traits": [], "starting_gold": 50},
		{"name": "B", "leader_id": "", "traits": [], "starting_gold": 50}
	], ["time"])
	var gs = facade.get_state()
	var p0 = gs.players[0]
	gs.current_player_id = p0.id
	gs.turn_number = 100  # well past any min duration
	gs.deals.append({
		"id": 1, "a_alliance": p0.alliance_id, "b_alliance": gs.players[1].alliance_id,
		"proposer_player_id": p0.id, "accepter_player_id": gs.players[1].id,
		"recurring": {"give": {"gold_per_turn": 5}, "receive": {}},
		"start_turn": 0, "min_duration": 10
	})
	var screen = _screen(facade)
	screen.show_screen()
	# Driving the handler directly exercises the apply_command path.
	screen._on_cancel_deal(1)
	assert_eq(gs.deals.size(), 0, "cancelling through the screen removes the deal")

func test_screen_shows_last_denial_reason() -> void:
	# §7 denial reasons: a recorded refusal against the viewing player is surfaced
	# on the rival's row with the display text from diplomacy.json.
	var facade = setup_facade(95, "small", [
		{"name": "A", "leader_id": "", "traits": [], "starting_gold": 50},
		{"name": "B", "leader_id": "", "traits": [], "starting_gold": 50}
	], ["time"])
	var gs = facade.get_state()
	var p0 = gs.players[0]
	var p1 = gs.players[1]
	gs.current_player_id = p0.id
	gs.get_alliance(p0.alliance_id).contacts.append(p1.alliance_id)
	gs.deal_denials[p0.id] = {p1.id: {"reason": "attitude_too_low", "turn": 4}}
	var screen = _screen(facade)
	screen.show_screen()
	var text: String = _recurse_text(screen)
	assert_true(Diplomacy.denial_text(gs.db, "attitude_too_low") in text,
		"the rival's last denial reason text is shown")
	assert_true("turn 4" in text, "the denial is stamped with its turn")

func test_civ_label_shows_civilization_and_leader() -> void:
	# Diplomacy rows must identify each visible civ by its civilization and leader
	# name, not the bare "Player N".
	var facade = setup_facade(91, "small",
		[{"name": "A", "leader_id": "", "traits": [], "starting_gold": 50}], ["time"])
	var gs = facade.get_state()
	var p = gs.players[0]
	var screen = _screen(facade)
	p.society_id = "american"
	var label: String = screen._civ_label(p, gs)
	assert_true("American" in label and "Washington" in label,
		"the row shows the civilization name and leader name")
	# A society-less player still shows something (its raw name).
	p.society_id = ""
	assert_eq(screen._civ_label(p, gs), p.name,
		"falls back to the player name when no society is set")
