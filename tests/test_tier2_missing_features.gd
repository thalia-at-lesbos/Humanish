# Humanish — a turn-based 4X strategy game.
# Copyright (C) 2026 thalia-at-lesbos
# SPDX-License-Identifier: GPL-3.0-or-later
#
# This program is free software: you can redistribute it and/or modify it
# under the terms of the GNU General Public License as published by the Free
# Software Foundation, either version 3 of the License, or (at your option)
# any later version. See the LICENSE file for the full text and warranty
# disclaimer.

extends "res://addons/gut/test.gd"

# Tier 2 subsystems from docs/missing-engine-features.md:
#   1. trades (propose/accept/reject + execution)   (§7)
#   2. war success -> war-fatigue -> discontent      (§3.8, §4.5, §7)
#   3. specialists (assign command + output)         (§6.5)
#   4. economic organizations (found + spread)       (§8)
#   5. intelligence missions                         (§7)
#   6. transport / embarkation                       (§5.2)

func _make_db():
	var db = load("res://src/core/data_db.gd").new()
	db.load_all()
	return db

func _make_gs():
	var db = _make_db()
	var gs = load("res://src/sim/game_state.gd").new()
	gs.db = db
	gs.rng = load("res://src/core/rng.gd").new()
	gs.rng.init(42)
	gs.map = load("res://src/world/world_map.gd").new()
	gs.map.init(20, 20, false, false)
	for tile in gs.map.all_tiles():
		tile.terrain_id = "grassland"
	var p1 = load("res://src/sim/player.gd").new()
	p1.id = 1; p1.alliance_id = 1
	var p2 = load("res://src/sim/player.gd").new()
	p2.id = 2; p2.alliance_id = 2
	gs.players.append(p1); gs.players.append(p2)
	var a1 = load("res://src/sim/alliance.gd").new(); a1.id = 1; a1.add_member(1)
	var a2 = load("res://src/sim/alliance.gd").new(); a2.id = 2; a2.add_member(2)
	gs.alliances.append(a1); gs.alliances.append(a2)
	return gs

# A facade wired to an existing game state without running setup().
func _facade(gs):
	var f = load("res://src/api/sim_facade.gd").new()
	f._gs = gs
	f._db = gs.db
	f._dirty = load("res://src/api/dirty_flags.gd").new()
	return f

func _unit(gs, type_id, player_id, x, y):
	var u = load("res://src/sim/unit.gd").new()
	u.id = gs.next_unit_id()
	u.unit_type_id = type_id
	u.owner_player_id = player_id
	u.x = x; u.y = y
	var ud = gs.db.get_unit(type_id)
	u.base_strength = int(ud.get("base_strength", 5))
	u.health = 100
	u.movement_total = int(ud.get("movement", 200)); u.movement_left = u.movement_total
	gs.units.append(u)
	return u

func _settlement(gs, player_id, x, y):
	var s = load("res://src/sim/settlement.gd").new()
	s.id = gs.next_settlement_id(); s.owner_player_id = player_id
	s.x = x; s.y = y; s.population = 5
	gs.settlements.append(s)
	return s

# ── 1. Trades ──────────────────────────────────────────────────────────────────

func test_trade_transfers_gold() -> void:
	var gs = _make_gs()
	var f = _facade(gs)
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
	var gs = _make_gs()
	var f = _facade(gs)
	gs.get_player(1).technologies = ["mining"]
	f._cmd_propose_trade({"player_id": 1, "target_alliance_id": 2,
		"give": {"techs": ["mining"]}, "receive": {}, "peace": false})
	var tid: int = int(gs.alliances[0].pending_trades[0]["id"])
	f._cmd_accept_trade({"player_id": 2, "trade_id": tid})
	assert_true(gs.get_player(2).has_tech("mining"), "Accepter gained the traded tech")

func test_trade_peace_clause_ends_war() -> void:
	var gs = _make_gs()
	var f = _facade(gs)
	gs.alliances[0].at_war_with = [2]
	gs.alliances[1].at_war_with = [1]
	f._cmd_propose_trade({"player_id": 1, "target_alliance_id": 2,
		"give": {}, "receive": {}, "peace": true})
	var tid: int = int(gs.alliances[0].pending_trades[0]["id"])
	f._cmd_accept_trade({"player_id": 2, "trade_id": tid})
	assert_false(gs.alliances[0].is_at_war_with(2), "Peace clause ended the war (proposer)")
	assert_false(gs.alliances[1].is_at_war_with(1), "Peace clause ended the war (accepter)")

func test_trade_reject_removes_without_effect() -> void:
	var gs = _make_gs()
	var f = _facade(gs)
	gs.get_player(1).treasury = 100
	f._cmd_propose_trade({"player_id": 1, "target_alliance_id": 2,
		"give": {"gold": 50}, "receive": {}, "peace": false})
	var tid: int = int(gs.alliances[0].pending_trades[0]["id"])
	assert_true(f._cmd_reject_trade({"player_id": 2, "trade_id": tid}), "Reject succeeds")
	assert_eq(gs.get_player(1).treasury, 100, "Rejected trade transfers nothing")
	assert_true(gs.alliances[0].pending_trades.empty(), "Rejected trade removed")

# ── 2. War-fatigue ─────────────────────────────────────────────────────────────

func test_combat_loss_accrues_war_fatigue() -> void:
	var gs = _make_gs()
	var f = _facade(gs)
	var atk = _unit(gs, "warrior", 1, 5, 6)
	var def = _unit(gs, "warrior", 2, 5, 5)
	var result = {
		"attacker_survived": true, "defender_survived": false,
		"attacker_health_after": 100, "defender_health_after": 0,
		"attacker_withdrew": false, "rounds": 1,
		"attacker_xp_gain": 0, "defender_xp_gain": 0,
		"spillover_damage": 0, "flanking_damage": 0
	}
	f._apply_combat_result(atk, def, result)
	var amt: int = gs.db.get_constant("war_fatigue_per_loss", 5)
	assert_eq(int(gs.alliances[1].war_fatigue.get(1, 0)), amt,
		"Loser's alliance accrues war-fatigue against the victor")

func test_war_fatigue_raises_discontent() -> void:
	var gs = _make_gs()
	var s = _settlement(gs, 1, 5, 5)
	s.population = 10
	var p = gs.get_player(1)
	TurnEngine._update_contentment(gs, s, p, gs.db)
	var base_neg: int = s.negative_sentiment
	# 200 fatigue / divisor 4 = 50 anger points -> 50% of 10 pop = 5 discontented.
	gs.alliances[0].war_fatigue = {2: 200}
	TurnEngine._update_contentment(gs, s, p, gs.db)
	assert_gt(s.negative_sentiment, base_neg, "War-fatigue increases negative sentiment")

# ── 3. Specialists ─────────────────────────────────────────────────────────────

func test_assign_specialist_sets_count() -> void:
	var gs = _make_gs()
	var f = _facade(gs)
	var s = _settlement(gs, 1, 5, 5)  # population 5
	assert_true(f._cmd_assign_specialist({"player_id": 1, "settlement_id": s.id,
		"specialist_type": "scientist", "count": 2}), "Assign within population succeeds")
	assert_eq(int(s.specialists.get("scientist", 0)), 2, "Specialist count recorded")

func test_assign_specialist_rejects_over_population() -> void:
	var gs = _make_gs()
	var f = _facade(gs)
	var s = _settlement(gs, 1, 5, 5)
	assert_false(f._cmd_assign_specialist({"player_id": 1, "settlement_id": s.id,
		"specialist_type": "scientist", "count": 6}), "Cannot exceed population")

func test_specialists_add_commerce() -> void:
	var gs = _make_gs()
	var s = _settlement(gs, 1, 5, 5)
	var p = gs.get_player(1)
	s.worked_tiles = []
	TurnEngine._settlement_growth(gs, s, p)
	var base_commerce: int = s.output_commerce
	s.specialists = {"merchant": 2}
	TurnEngine._settlement_growth(gs, s, p)
	var per: int = gs.db.get_constant("specialist_commerce", 3)
	assert_eq(s.output_commerce, base_commerce + 2 * per, "Each specialist adds commerce")

# ── 4. Economic organizations ──────────────────────────────────────────────────

func test_special_person_founds_econ_org() -> void:
	var gs = _make_gs()
	var p = gs.get_player(1)
	p.current_research_id = ""  # no research -> try econ org before gold
	var s = _settlement(gs, 1, 5, 5)
	TurnEngine._apply_special_person(gs, s)
	assert_ne(s.econ_org_id, "", "A special person seeds an economic organization")
	assert_true(gs.founded_econ_orgs.has(s.econ_org_id), "Org recorded as founded")

func test_econ_org_spreads_to_adjacent_settlement() -> void:
	var gs = _make_gs()
	var p = gs.get_player(1)
	p.treasury = 1000
	var s1 = _settlement(gs, 1, 5, 5)
	var s2 = _settlement(gs, 1, 6, 5)
	EconOrgs.found("merchant_guild", s1, gs)
	# Force a guaranteed spread by giving the rng a seed that rolls under the chance.
	var spread := false
	for i in range(50):
		EconOrgs.spread_all(gs, gs.rng)
		if s2.econ_org_id == "merchant_guild":
			spread = true
			break
	assert_true(spread, "An economic organization spreads to an adjacent settlement")

# ── 5. Intelligence missions ───────────────────────────────────────────────────

func test_espionage_spends_intel_points() -> void:
	var gs = _make_gs()
	var f = _facade(gs)
	gs.get_player(2).technologies = ["mining"]
	var cost: int = gs.db.get_constant("intel_mission_cost", 100)
	gs.get_player(1).intel_points = {2: cost + 50}
	assert_true(f._cmd_espionage_mission({"player_id": 1, "target_alliance_id": 2,
		"mission": "steal_tech"}), "Mission runs when points suffice")
	assert_eq(int(gs.get_player(1).intel_points.get(2, 0)), 50,
		"Mission spends its intel cost regardless of interception")

func test_espionage_rejected_without_points() -> void:
	var gs = _make_gs()
	var f = _facade(gs)
	gs.get_player(1).intel_points = {2: 10}
	assert_false(f._cmd_espionage_mission({"player_id": 1, "target_alliance_id": 2,
		"mission": "steal_tech"}), "Mission fails without enough points")

func test_steal_tech_transfers_unknown_tech() -> void:
	var gs = _make_gs()
	var f = _facade(gs)
	gs.get_player(2).technologies = ["mining"]
	f._espionage_steal_tech(gs.get_player(1), gs.alliances[1])
	assert_true(gs.get_player(1).has_tech("mining"), "Steal grants a tech the thief lacked")

# ── 6. Transport / embarkation ─────────────────────────────────────────────────

func _make_coast(gs, xs):
	for x in xs:
		gs.map.get_tile(x, 5).terrain_id = "coast"

func test_land_unit_loads_onto_transport() -> void:
	var gs = _make_gs()
	var f = _facade(gs)
	_make_coast(gs, [5])
	var galley = _unit(gs, "galley", 1, 5, 5)
	var warrior = _unit(gs, "warrior", 1, 4, 5)  # adjacent land
	assert_true(f._cmd_load_unit({"player_id": 1, "unit_id": warrior.id,
		"transport_id": galley.id}), "Adjacent land unit loads")
	assert_eq(warrior.transported_by, galley.id, "Warrior is marked transported")
	assert_true(warrior.id in galley.cargo, "Warrior is in the galley cargo")
	assert_eq(warrior.x, 5, "Warrior moved onto the transport tile")

func test_transport_respects_capacity() -> void:
	var gs = _make_gs()
	var f = _facade(gs)
	_make_coast(gs, [5])
	var galley = _unit(gs, "galley", 1, 5, 5)  # capacity 2
	var w1 = _unit(gs, "warrior", 1, 4, 5)
	var w2 = _unit(gs, "warrior", 1, 6, 5)
	var w3 = _unit(gs, "warrior", 1, 5, 6)
	f._cmd_load_unit({"player_id": 1, "unit_id": w1.id, "transport_id": galley.id})
	f._cmd_load_unit({"player_id": 1, "unit_id": w2.id, "transport_id": galley.id})
	assert_false(f._cmd_load_unit({"player_id": 1, "unit_id": w3.id, "transport_id": galley.id}),
		"A full transport rejects further cargo")

func test_cargo_follows_transport() -> void:
	var gs = _make_gs()
	var f = _facade(gs)
	_make_coast(gs, [5, 6, 7])
	var galley = _unit(gs, "galley", 1, 5, 5)
	var warrior = _unit(gs, "warrior", 1, 4, 5)
	f._cmd_load_unit({"player_id": 1, "unit_id": warrior.id, "transport_id": galley.id})
	f._cmd_move_stack({"player_id": 1, "from_x": 5, "from_y": 5, "to_x": 6, "to_y": 5})
	assert_eq(galley.x, 6, "Transport moved")
	assert_eq(warrior.x, 6, "Carried unit moved with the transport")

func test_unload_to_land() -> void:
	var gs = _make_gs()
	var f = _facade(gs)
	_make_coast(gs, [5])
	var galley = _unit(gs, "galley", 1, 5, 5)
	var warrior = _unit(gs, "warrior", 1, 4, 5)
	f._cmd_load_unit({"player_id": 1, "unit_id": warrior.id, "transport_id": galley.id})
	assert_true(f._cmd_unload_unit({"player_id": 1, "unit_id": warrior.id,
		"target_x": 4, "target_y": 5}), "Unload onto adjacent land")
	assert_eq(warrior.transported_by, -1, "Warrior is no longer transported")
	assert_false(warrior.id in galley.cargo, "Warrior removed from cargo")
	assert_eq(warrior.x, 4, "Warrior disembarked onto land")
