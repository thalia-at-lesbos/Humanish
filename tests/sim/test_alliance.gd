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

# §7 persistent deals (Phase 7): a recurring trade promotes to a Deal on
# GameState.deals, delivers per-turn each world step, lapses on war, and is
# cancellable only past its minimum duration.

# A deal manually seeded between alliance 1 (proposer player 1) and alliance 2
# (accepter player 2), delivering `gpt_give` gold/turn proposer→accepter.
func _seed_deal(gs, gpt_give = 5, gpt_recv = 0, start = 0, min_dur = 10):
	gs.deals.append({
		"id": gs.next_trade_id(),
		"a_alliance": 1,
		"b_alliance": 2,
		"proposer_player_id": 1,
		"accepter_player_id": 2,
		"recurring": {
			"give": {"gold_per_turn": gpt_give} if gpt_give > 0 else {},
			"receive": {"gold_per_turn": gpt_recv} if gpt_recv > 0 else {}
		},
		"start_turn": start,
		"min_duration": min_dur
	})
	return gs.deals[gs.deals.size() - 1]

# ── Deal creation from an accepted trade ───────────────────────────────────────

func test_recurring_trade_creates_a_deal() -> void:
	var gs = make_gs(2)
	var f = bare_facade(gs)
	gs.current_player_id = 1
	f.apply_command(Commands.propose_trade(1, 2, {"gold_per_turn": 7}, {}))
	# Find the offer id on alliance 1.
	var offer_id: int = int(gs.get_alliance(1).pending_trades[0]["id"])
	gs.current_player_id = 2
	f.apply_command(Commands.accept_trade(2, offer_id))
	assert_eq(gs.deals.size(), 1, "an accepted recurring trade creates one deal")
	var d: Dictionary = gs.deals[0]
	assert_eq(int(d["proposer_player_id"]), 1)
	assert_eq(int(d["accepter_player_id"]), 2)
	assert_eq(int(d["recurring"]["give"]["gold_per_turn"]), 7)

func test_one_off_only_trade_creates_no_deal() -> void:
	var gs = make_gs(2)
	gs.get_player(1).treasury = 100
	var f = bare_facade(gs)
	gs.current_player_id = 1
	f.apply_command(Commands.propose_trade(1, 2, {"gold": 30}, {}))
	var offer_id: int = int(gs.get_alliance(1).pending_trades[0]["id"])
	gs.current_player_id = 2
	f.apply_command(Commands.accept_trade(2, offer_id))
	assert_eq(gs.deals.size(), 0, "a pure one-off trade leaves no standing deal")
	assert_eq(gs.get_player(2).treasury, 30, "one-off gold delivered once")

# ── Per-turn delivery ──────────────────────────────────────────────────────────

func test_deal_delivers_gold_each_world_step() -> void:
	var gs = make_gs(2)
	gs.get_player(1).treasury = 100
	_seed_deal(gs, 5, 0)
	TurnEngine._execute_deals(gs)
	assert_eq(gs.get_player(1).treasury, 95, "proposer pays 5 once")
	assert_eq(gs.get_player(2).treasury, 5, "accepter receives 5 once")
	TurnEngine._execute_deals(gs)
	assert_eq(gs.get_player(1).treasury, 90, "delivered again the next step")
	assert_eq(gs.get_player(2).treasury, 10)

func test_deal_delivers_both_directions() -> void:
	var gs = make_gs(2)
	gs.get_player(1).treasury = 100
	gs.get_player(2).treasury = 100
	_seed_deal(gs, 8, 3)  # 1→2 of 8, 2→1 of 3
	TurnEngine._execute_deals(gs)
	assert_eq(gs.get_player(1).treasury, 95, "100 - 8 + 3")
	assert_eq(gs.get_player(2).treasury, 105, "100 + 8 - 3")

# ── Lapse on war / missing party ───────────────────────────────────────────────

func test_deal_lapses_when_parties_go_to_war() -> void:
	var gs = make_gs(2)
	_seed_deal(gs, 5, 0)
	gs.get_alliance(1).at_war_with.append(2)
	TurnEngine._execute_deals(gs)
	assert_eq(gs.deals.size(), 0, "a deal between warring alliances is torn up")
	assert_eq(gs.pending_deal_events.size(), 1, "lapse surfaces a notice")
	assert_eq(str(gs.pending_deal_events[0]["kind"]), "deal_expired")

# ── Cancellation honours the minimum duration ──────────────────────────────────

func test_cancel_blocked_before_min_duration() -> void:
	var gs = make_gs(2)
	gs.turn_number = 5
	_seed_deal(gs, 5, 0, 0, 10)  # min runs to turn 10
	var f = bare_facade(gs)
	gs.current_player_id = 1
	var ok: bool = f.apply_command(Commands.cancel_deal(1, int(gs.deals[0]["id"])))
	assert_false(ok, "cannot cancel before the minimum duration elapses")
	assert_eq(gs.deals.size(), 1, "deal remains")

func test_cancel_allowed_after_min_duration() -> void:
	var gs = make_gs(2)
	gs.turn_number = 12
	_seed_deal(gs, 5, 0, 0, 10)
	var f = bare_facade(gs)
	gs.current_player_id = 2
	var ok: bool = f.apply_command(Commands.cancel_deal(2, int(gs.deals[0]["id"])))
	assert_true(ok, "either party may cancel once the minimum elapses")
	assert_eq(gs.deals.size(), 0, "deal removed")
	assert_eq(str(gs.pending_deal_events[0]["kind"]), "deal_cancelled")

func test_cancel_rejected_for_non_party() -> void:
	var gs = make_gs(3)
	gs.turn_number = 50
	_seed_deal(gs, 5, 0, 0, 10)
	var f = bare_facade(gs)
	gs.current_player_id = 3
	var ok: bool = f.apply_command(Commands.cancel_deal(3, int(gs.deals[0]["id"])))
	assert_false(ok, "a third party cannot cancel someone else's deal")
	assert_eq(gs.deals.size(), 1)

# ── Save/load determinism ──────────────────────────────────────────────────────

func test_deal_survives_save_load_as_ints() -> void:
	var gs = make_gs(2)
	gs.turn_number = 7
	_seed_deal(gs, 5, 2, 3, 10)
	var d = gs.serialize()
	var gs2 = load("res://src/sim/game_state.gd").deserialize(d, gs.db)
	assert_eq(gs2.deals.size(), 1, "deal roundtrips")
	var dl: Dictionary = gs2.deals[0]
	# Int discipline: the envelope fields must come back as ints, not floats.
	assert_true(dl["a_alliance"] is int, "a_alliance coerced to int")
	assert_true(dl["proposer_player_id"] is int, "proposer coerced to int")
	assert_eq(int(dl["start_turn"]), 3)
	assert_eq(int(dl["recurring"]["receive"]["gold_per_turn"]), 2)
