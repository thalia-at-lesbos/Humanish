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
	# The peace notification must render the alliances' labels (Alliance has no
	# `name` field — referencing it used to raise a swallowed SCRIPT ERROR and emit
	# a corrupted "Null and Null agreed to peace" line).
	var peace_note: String = ""
	for n in f.get_notification_queue():
		if "agreed to peace" in str(n.get("text", "")):
			peace_note = str(n["text"])
	assert_eq(peace_note, "P1 and P2 agreed to peace.",
		"Peace clause emits a well-formed notification naming both powers")

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

# ── First contact (§7): sight-based meeting ──────────────────────────────────

func test_first_contact_when_unit_sees_enemy_unit() -> void:
	# Two players' units one tile apart (within unit_sight = 2). The world-step
	# contact sweep must record mutual, permanent contact between their alliances.
	var gs = make_gs(2)
	make_unit(gs, "warrior", 1, 5, 5)
	make_unit(gs, "warrior", 2, 6, 5)
	assert_false(gs.get_player_alliance(1).has_contact_with(2),
		"No contact before the units have been seen")
	TurnEngine._detect_sight_contact(gs)
	assert_true(gs.get_player_alliance(1).has_contact_with(2),
		"Player 1 has met player 2 after sighting their unit")
	assert_true(gs.get_player_alliance(2).has_contact_with(1),
		"Contact is mutual")

func test_no_first_contact_when_players_far_apart() -> void:
	var gs = make_gs(2)
	make_unit(gs, "warrior", 1, 2, 2)
	make_unit(gs, "warrior", 2, 17, 17)   # well beyond either sight radius
	TurnEngine._detect_sight_contact(gs)
	assert_false(gs.get_player_alliance(1).has_contact_with(2),
		"Distant players do not meet")
	assert_false(gs.get_player_alliance(2).has_contact_with(1),
		"…and the reverse holds too")

func test_first_contact_is_permanent_after_separation() -> void:
	var gs = make_gs(2)
	var a = make_unit(gs, "warrior", 1, 5, 5)
	var b = make_unit(gs, "warrior", 2, 6, 5)
	TurnEngine._detect_sight_contact(gs)
	assert_true(gs.get_player_alliance(1).has_contact_with(2), "Met while adjacent")
	# Move both far apart and sweep again — contact must persist (sticky).
	a.x = 1; a.y = 1
	b.x = 18; b.y = 18
	TurnEngine._detect_sight_contact(gs)
	assert_true(gs.get_player_alliance(1).has_contact_with(2),
		"A met player stays known after moving out of view")

func test_first_contact_via_border_tile() -> void:
	# Player 1's unit sees a tile owned by player 2 (a border) — no enemy unit
	# needed. That counts as meeting player 2.
	var gs = make_gs(2)
	make_unit(gs, "warrior", 1, 5, 5)
	gs.map.get_tile(6, 5).owner_player_id = 2
	TurnEngine._detect_sight_contact(gs)
	assert_true(gs.get_player_alliance(1).has_contact_with(2),
		"Sighting a rival's border tile establishes contact")
	assert_true(gs.get_player_alliance(2).has_contact_with(1), "…mutually")

func test_first_contact_ignores_wild_forces() -> void:
	# A wild unit (owner -2) near a player must not create a contact entry.
	var gs = make_gs(2)
	make_unit(gs, "warrior", 1, 5, 5)
	make_warrior(gs, 1, 6, 5, true)   # wild = true → owner -2
	TurnEngine._detect_sight_contact(gs)
	assert_false(gs.get_player_alliance(1).has_contact_with(-2),
		"Wild forces are not diplomatic contacts")

func test_world_step_establishes_first_contact() -> void:
	# Wiring: the contact sweep runs as part of world_step.
	var gs = make_gs(2)
	make_unit(gs, "warrior", 1, 5, 5)
	make_unit(gs, "warrior", 2, 6, 5)
	TurnEngine.world_step(gs, hooks())
	assert_true(gs.get_player_alliance(1).has_contact_with(2),
		"world_step detects first contact")

# ── Save/load key typing (determinism) ───────────────────────────────────────

func test_alliance_contacts_deserialize_as_ints() -> void:
	# JSON turns dict/array number entries into floats/strings; alliance ID arrays
	# must come back as ints so int lookups (has_contact_with, intel_points keys,
	# permanent_allies membership) keep matching after a load. Guards the save/load
	# determinism break first seen via sight-based first contact.
	var a = load("res://src/sim/alliance.gd").new()
	a.id = 1
	a.contacts = [2, 3]
	a.permanent_allies = [3]
	a.at_war_with = [2]
	a.war_fatigue = {2: 7}
	# Round-trip through real JSON so keys/values pick up JSON's float/string typing.
	var round_tripped = JSON.parse(JSON.print(a.serialize())).result
	var b = load("res://src/sim/alliance.gd").deserialize(round_tripped)
	assert_true(b.has_contact_with(2), "Contact lookup works with an int id after load")
	assert_true(2 in b.contacts and typeof(b.contacts[0]) == TYPE_INT,
		"Contacts are ints, not floats, after load")
	assert_true(3 in b.permanent_allies, "Permanent-ally membership matches an int id")
	assert_true(2 in b.at_war_with, "War membership matches an int id")
	assert_eq(int(b.war_fatigue[2]), 7, "war_fatigue is reachable by its int key")

func test_intel_accumulation_survives_save_load() -> void:
	# Two players in sight of each other accumulate intel identically whether the
	# game runs straight through or is saved and resumed mid-way.
	var gs = make_gs(2)
	# Player 1 needs a city for espionage output; its sight (and the adjacent rival
	# warrior) establishes contact so intel actually accumulates.
	make_settlement(gs, 1, 5, 5, 3)
	make_unit(gs, "warrior", 2, 6, 5)
	var f = bare_facade(gs)
	f._hooks = hooks()
	_end_turn_round(f, gs)             # establishes contact + first intel tick
	var save_str = f.save()
	_end_turn_round(f, gs)
	var straight = gs.get_player(1).intel_points.duplicate()

	var f2 = load("res://src/api/sim_facade.gd").new()
	f2.init_for_load(make_db())
	f2.load_save(save_str)
	var gs2 = f2.get_state()
	_end_turn_round(f2, gs2)
	# After one matching round the loaded game must hold the same single int-keyed
	# intel entry (no phantom float/string duplicate).
	assert_eq(gs2.get_player(1).intel_points.size(), straight.size(),
		"No phantom duplicate intel key after load")
	assert_eq(int(gs2.get_player(1).intel_points.get(2, -1)),
		int(straight.get(2, -2)), "Resumed intel matches the straight-through run")

func _end_turn_round(f, gs) -> void:
	gs.current_player_id = 1
	f.apply_command(Commands.end_turn(1))
	gs.current_player_id = 2
	f.apply_command(Commands.end_turn(2))

# ── §7 AI attitude & memory (Phase 7) ─────────────────────────────────────────
# The Diplomacy module computes a deterministic 0..100 attitude from a neutral base
# + live factors + decaying memory, bucketed into five levels (furious → friendly).

func test_neutral_attitude_is_cautious_middle() -> void:
	var gs = make_gs(2)
	# No memory, no factors: score == attitude_base (50) → middle level (cautious).
	assert_eq(Diplomacy.attitude_score(gs, gs.db, 1, 2),
		int(gs.db.get_diplomacy().get("attitude_base", 50)))
	assert_eq(Diplomacy.attitude_level(gs, gs.db, 1, 2), Diplomacy.CAUTIOUS)

func test_attitude_level_name_round_trips() -> void:
	var gs = make_gs(2)
	assert_eq(Diplomacy.level_name(gs.db, Diplomacy.FRIENDLY), "friendly")
	assert_eq(Diplomacy.level_name(gs.db, Diplomacy.FURIOUS), "furious")
	assert_eq(Diplomacy.level_name(gs.db, 99), "", "out-of-range level has no name")

func test_war_drops_attitude_to_furious() -> void:
	var gs = make_gs(2)
	gs.get_alliance(1).at_war_with.append(2)
	gs.get_alliance(2).at_war_with.append(1)
	# base 50 + at_war (-45) = 5 → below the first threshold (furious).
	assert_eq(Diplomacy.attitude_level(gs, gs.db, 1, 2), Diplomacy.FURIOUS)

func test_shared_religion_warms_attitude() -> void:
	var gs = make_gs(2)
	gs.get_player(1).state_religion = "faith"
	gs.get_player(2).state_religion = "faith"
	var shared: int = Diplomacy.attitude_score(gs, gs.db, 1, 2)
	gs.get_player(2).state_religion = "other"
	assert_true(shared > Diplomacy.attitude_score(gs, gs.db, 1, 2),
		"a shared faith reads warmer than a clashing one")

func test_active_deal_warms_attitude() -> void:
	var gs = make_gs(2)
	var before: int = Diplomacy.attitude_score(gs, gs.db, 1, 2)
	gs.deals.append({"a_alliance": 1, "b_alliance": 2, "recurring": {}})
	assert_true(Diplomacy.attitude_score(gs, gs.db, 1, 2) > before,
		"an active deal lifts attitude")

func test_declared_war_memory_sours_then_decays() -> void:
	var gs = make_gs(2)
	Diplomacy.record(gs, gs.db, 1, 2, "declared_war")
	var soured: int = Diplomacy.memory_total(gs.get_player(1), 2)
	assert_eq(soured, int(gs.db.get_diplomacy()["memory_kinds"]["declared_war"]["value"]))
	assert_true(soured < 0)
	Diplomacy.decay(gs, gs.db)
	assert_eq(Diplomacy.memory_total(gs.get_player(1), 2), soured + 1,
		"a -30 grievance decays by 1 toward zero")

func test_memory_decays_fully_and_clears_entry() -> void:
	var gs = make_gs(2)
	gs.get_player(1).diplo_memory[2] = {"made_peace": 2}
	Diplomacy.decay(gs, gs.db)
	Diplomacy.decay(gs, gs.db)
	assert_eq(Diplomacy.memory_total(gs.get_player(1), 2), 0)
	assert_false(gs.get_player(1).diplo_memory.has(2),
		"a fully-decayed rival entry is dropped")

func test_record_ignores_self_and_unknown_kinds() -> void:
	var gs = make_gs(2)
	Diplomacy.record(gs, gs.db, 1, 1, "declared_war")  # self
	Diplomacy.record(gs, gs.db, 1, 2, "no_such_kind")  # unknown
	assert_eq(gs.get_player(1).diplo_memory.size(), 0)

func test_memory_is_capped() -> void:
	var gs = make_gs(2)
	var cap: int = int(gs.db.get_diplomacy().get("memory_cap", 120))
	for _i in range(100):
		Diplomacy.record(gs, gs.db, 1, 2, "razed_city")  # -40 each
	assert_eq(Diplomacy.memory_total(gs.get_player(1), 2), -cap,
		"memory magnitude is clamped to the cap")

func test_grievance_lowers_attitude_level() -> void:
	var gs = make_gs(2)
	var before: int = Diplomacy.attitude_level(gs, gs.db, 1, 2)
	Diplomacy.record(gs, gs.db, 1, 2, "razed_city")
	Diplomacy.record(gs, gs.db, 1, 2, "declared_war")
	assert_true(Diplomacy.attitude_level(gs, gs.db, 1, 2) < before,
		"stacked grievances drop the attitude level")

func test_memory_survives_save_load_as_ints() -> void:
	var gs = make_gs(2)
	Diplomacy.record(gs, gs.db, 1, 2, "declared_war")
	var p2 = load("res://src/sim/player.gd").deserialize(
		JSON.parse(JSON.print(gs.get_player(1).serialize())).result)
	assert_true(p2.diplo_memory.has(2), "rival key coerced back to int after JSON roundtrip")
	assert_eq(Diplomacy.memory_total(p2, 2),
		int(gs.db.get_diplomacy()["memory_kinds"]["declared_war"]["value"]))

func test_declare_war_records_memory_on_victim() -> void:
	var gs = make_gs(2)
	var f = bare_facade(gs)
	gs.current_player_id = 1
	f.apply_command(Commands.declare_war(1, 2))
	# Player 2 (the victim) now holds a war grievance against the aggressor, player 1.
	assert_true(Diplomacy.memory_total(gs.get_player(2), 1) < 0,
		"the attacked player remembers the declaration")
