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

# Diplomacy (§7): war/peace declaration, trades (gold/tech/peace clause), and
# subordination/tributary relationships.

# ── War & peace declaration ──────────────────────────────────────────────────

func test_declare_war_command_sets_war_state() -> void:
	var gs = make_gs(2)
	var f = bare_facade(gs)
	gs.current_player_id = 1
	assert_true(f.apply_command(Commands.declare_war(1, 2)), "Declare war command accepted")
	assert_true(gs.alliances[0].is_at_war_with(2), "Declaring war records the war state")
	assert_true(gs.alliances[0].has_contact_with(2), "Declaring war establishes contact")

func test_make_peace_command_clears_war_state() -> void:
	var gs = make_gs(2)
	var f = bare_facade(gs)
	gs.current_player_id = 1
	gs.alliances[0].at_war_with = [2]
	assert_true(f.apply_command(Commands.make_peace(1, 2)), "Make peace command accepted")
	assert_false(gs.alliances[0].is_at_war_with(2), "Making peace clears the war state")

func test_cannot_declare_war_on_own_alliance() -> void:
	var gs = make_gs(2)
	var f = bare_facade(gs)
	gs.current_player_id = 1
	assert_false(f.apply_command(Commands.declare_war(1, 1)),
		"A player cannot declare war on their own alliance")

# ── Trades ───────────────────────────────────────────────────────────────────

func test_trade_transfers_gold() -> void:
	var gs = make_gs(2)
	var f = bare_facade(gs)
	gs.get_player(1).treasury = 100
	gs.get_player(2).treasury = 0
	f._cmd_propose_trade({"player_id": 1, "target_alliance_id": 2,
		"give": {"gold": 50}, "receive": {}, "peace": false})
	var tid: int = int(gs.alliances[0].pending_trades[0]["id"])
	assert_true(f._cmd_accept_trade({"player_id": 2, "trade_id": tid}), "Accept succeeds")
	assert_eq(gs.get_player(1).treasury, 50, "Proposer paid the gold")
	assert_eq(gs.get_player(2).treasury, 50, "Accepter received the gold")
	assert_true(gs.alliances[0].pending_trades.empty(), "Trade removed after acceptance")

func test_trade_transfers_tech() -> void:
	var gs = make_gs(2)
	var f = bare_facade(gs)
	gs.get_player(1).technologies = ["mining"]
	f._cmd_propose_trade({"player_id": 1, "target_alliance_id": 2,
		"give": {"techs": ["mining"]}, "receive": {}, "peace": false})
	var tid: int = int(gs.alliances[0].pending_trades[0]["id"])
	f._cmd_accept_trade({"player_id": 2, "trade_id": tid})
	assert_true(gs.get_player(2).has_tech("mining"), "Accepter gained the traded tech")

func test_trade_peace_clause_ends_war() -> void:
	var gs = make_gs(2)
	var f = bare_facade(gs)
	gs.alliances[0].at_war_with = [2]
	gs.alliances[1].at_war_with = [1]
	f._cmd_propose_trade({"player_id": 1, "target_alliance_id": 2,
		"give": {}, "receive": {}, "peace": true})
	var tid: int = int(gs.alliances[0].pending_trades[0]["id"])
	f._cmd_accept_trade({"player_id": 2, "trade_id": tid})
	assert_false(gs.alliances[0].is_at_war_with(2), "Peace clause ended the war (proposer)")
	assert_false(gs.alliances[1].is_at_war_with(1), "Peace clause ended the war (accepter)")

func test_trade_reject_removes_without_effect() -> void:
	var gs = make_gs(2)
	var f = bare_facade(gs)
	gs.get_player(1).treasury = 100
	f._cmd_propose_trade({"player_id": 1, "target_alliance_id": 2,
		"give": {"gold": 50}, "receive": {}, "peace": false})
	var tid: int = int(gs.alliances[0].pending_trades[0]["id"])
	assert_true(f._cmd_reject_trade({"player_id": 2, "trade_id": tid}), "Reject succeeds")
	assert_eq(gs.get_player(1).treasury, 100, "Rejected trade transfers nothing")
	assert_true(gs.alliances[0].pending_trades.empty(), "Rejected trade removed")

# ── Permanent alliances ───────────────────────────────────────────────────────

func test_permanent_alliance_requires_rule_enabled() -> void:
	var gs = make_gs(2)
	var f = bare_facade(gs)
	gs.current_player_id = 1
	# Rule is off by default: command must be rejected.
	assert_false(f.apply_command(Commands.propose_permanent_alliance(1, 2)),
		"Permanent alliance command rejected when rule is off")

func test_permanent_alliance_forms_when_rule_enabled() -> void:
	var gs = make_gs(2)
	gs.permanent_alliances = true
	var f = bare_facade(gs)
	gs.current_player_id = 1
	assert_true(f.apply_command(Commands.propose_permanent_alliance(1, 2)),
		"Permanent alliance command accepted when rule is on")
	assert_true(2 in gs.alliances[0].permanent_allies, "Alliance 1 records alliance 2 as perm ally")
	assert_true(1 in gs.alliances[1].permanent_allies, "Alliance 2 records alliance 1 as perm ally (mutual)")

func test_permanent_alliance_blocked_while_at_war() -> void:
	var gs = make_gs(2)
	gs.permanent_alliances = true
	var f = bare_facade(gs)
	gs.current_player_id = 1
	gs.alliances[0].at_war_with = [2]
	assert_false(f.apply_command(Commands.propose_permanent_alliance(1, 2)),
		"Cannot form permanent alliance while at war")

func test_permanent_alliance_no_duplicate() -> void:
	var gs = make_gs(2)
	gs.permanent_alliances = true
	var f = bare_facade(gs)
	gs.current_player_id = 1
	f.apply_command(Commands.propose_permanent_alliance(1, 2))
	assert_false(f.apply_command(Commands.propose_permanent_alliance(1, 2)),
		"Duplicate permanent alliance rejected")

func test_permanent_alliance_establishes_contact() -> void:
	var gs = make_gs(2)
	gs.permanent_alliances = true
	var f = bare_facade(gs)
	gs.current_player_id = 1
	f.apply_command(Commands.propose_permanent_alliance(1, 2))
	assert_true(gs.alliances[0].has_contact_with(2), "Permanent alliance establishes contact (p1 side)")
	assert_true(gs.alliances[1].has_contact_with(1), "Permanent alliance establishes contact (p2 side)")

# ── Subordination / tributaries ────────────────────────────────────────────────

func test_become_tributary_records_relationship() -> void:
	var gs = make_gs(2)
	var f = bare_facade(gs)
	gs.alliances[0].at_war_with = [2]; gs.alliances[1].at_war_with = [1]
	assert_true(f._cmd_set_subordination({"player_id": 2, "overlord_alliance_id": 1}),
		"Subordination command succeeds")
	assert_eq(gs.alliances[1].is_subordinate_to, 1, "Subordinate records its overlord")
	assert_true(2 in gs.alliances[0].tributaries, "Overlord records the tributary")
	assert_false(gs.alliances[0].is_at_war_with(2), "War between them ends on submission")

func test_tributary_joins_overlord_wars() -> void:
	var gs = make_gs(2)
	var f = bare_facade(gs)
	gs.alliances[0].at_war_with = [9]  # overlord at war with alliance 9
	f._cmd_set_subordination({"player_id": 2, "overlord_alliance_id": 1})
	assert_true(gs.alliances[1].is_at_war_with(9), "Tributary inherits the overlord's wars")

func test_tribute_transfers_treasury() -> void:
	var gs = make_gs(2)
	var f = bare_facade(gs)
	gs.get_player(2).treasury = 100
	gs.get_player(1).treasury = 0
	f._cmd_set_subordination({"player_id": 2, "overlord_alliance_id": 1})
	TurnEngine._collect_tribute(gs)
	assert_eq(gs.get_player(2).treasury, 100 - 10, "Tributary pays tribute")
	assert_eq(gs.get_player(1).treasury, 10, "Overlord receives the tribute")
