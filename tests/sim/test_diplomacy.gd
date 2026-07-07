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

func test_first_contact_via_own_territory_vision() -> void:
	# Player 1 owns a tile but has NO unit or city anywhere near it. A rival unit
	# standing directly on that owned tile must still establish contact, because a
	# player watches their own cultural territory.
	var gs = make_gs(2)
	gs.map.get_tile(10, 10).owner_player_id = 1
	make_unit(gs, "warrior", 2, 10, 10)   # rival sitting inside player 1's border
	# No player-1 unit/city is in normal sight range of (10,10).
	assert_false(gs.get_player_alliance(1).has_contact_with(2),
		"No contact before the territory sweep")
	TurnEngine._detect_sight_contact(gs)
	assert_true(gs.get_player_alliance(1).has_contact_with(2),
		"A rival inside my borders meets me via territory vision")
	assert_true(gs.get_player_alliance(2).has_contact_with(1), "…mutually")

func test_first_contact_via_territory_one_ring() -> void:
	# A rival unit one tile OUTSIDE player 1's border (on the one-ring fringe) also
	# establishes contact, with no friendly unit/city anywhere near.
	var gs = make_gs(2)
	gs.map.get_tile(10, 10).owner_player_id = 1
	make_unit(gs, "warrior", 2, 11, 10)   # adjacent to the border tile (ring 1)
	TurnEngine._detect_sight_contact(gs)
	assert_true(gs.get_player_alliance(1).has_contact_with(2),
		"A rival stepping adjacent to my border meets me via the one-ring fringe")

func test_no_first_contact_two_rings_beyond_border() -> void:
	# A rival two tiles beyond the border (outside the default one-ring fringe),
	# with no friendly sight source near, does NOT establish contact.
	var gs = make_gs(2)
	gs.map.get_tile(10, 10).owner_player_id = 1
	make_unit(gs, "warrior", 2, 13, 10)   # two tiles beyond the ring-1 fringe
	TurnEngine._detect_sight_contact(gs)
	assert_false(gs.get_player_alliance(1).has_contact_with(2),
		"A rival two rings beyond my border is not met via territory vision")

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

# ── First-contact notification queue (§7) ────────────────────────────────────

func test_first_contact_enqueues_one_record_per_player() -> void:
	# A fresh meeting must enqueue exactly one first-contact record per direction
	# (two players → two records), each naming the other player.
	var gs = make_gs(2)
	make_unit(gs, "warrior", 1, 5, 5)
	make_unit(gs, "warrior", 2, 6, 5)
	assert_true(gs.pending_first_contacts.empty(),
		"No first-contact records before the sweep")
	TurnEngine._detect_sight_contact(gs)
	assert_eq(gs.pending_first_contacts.size(), 2,
		"One first-contact record per player (mutual)")
	var seen_for: Dictionary = {}
	for fc in gs.pending_first_contacts:
		seen_for[int(fc["player_id"])] = int(fc["other_player_id"])
	assert_eq(seen_for.get(1, -1), 2, "Player 1's record names player 2")
	assert_eq(seen_for.get(2, -1), 1, "Player 2's record names player 1")

func test_first_contact_not_re_enqueued_on_later_sweeps() -> void:
	# Once met, a subsequent sweep must not enqueue the same contact again.
	var gs = make_gs(2)
	make_unit(gs, "warrior", 1, 5, 5)
	make_unit(gs, "warrior", 2, 6, 5)
	TurnEngine._detect_sight_contact(gs)
	gs.pending_first_contacts = []   # simulate the facade draining
	TurnEngine._detect_sight_contact(gs)
	assert_true(gs.pending_first_contacts.empty(),
		"An already-met pair does not re-enqueue a first-contact record")

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

func test_deal_resources_route_to_the_correct_recipient() -> void:
	# give.resources flow proposer→accepter; receive.resources flow accepter→proposer.
	var gs = make_gs(2)
	gs.deals.append({
		"id": 1, "a_alliance": 1, "b_alliance": 2,
		"proposer_player_id": 1, "accepter_player_id": 2,
		"recurring": {"give": {"resources": ["iron"]}, "receive": {"resources": ["wheat"]}},
		"start_turn": 0, "min_duration": 10
	})
	assert_true(Diplomacy.deal_resources_for(gs, 2).has("iron"),
		"the accepter receives the proposer's give-resources")
	assert_true(Diplomacy.deal_resources_for(gs, 1).has("wheat"),
		"the proposer receives the accepter's receive-resources")
	assert_false(Diplomacy.deal_resources_for(gs, 1).has("iron"),
		"the proposer does not gain access to what it gave away")

func test_declare_war_records_memory_on_victim() -> void:
	var gs = make_gs(2)
	var f = bare_facade(gs)
	gs.current_player_id = 1
	f.apply_command(Commands.declare_war(1, 2))
	# Player 2 (the victim) now holds a war grievance against the aggressor, player 1.
	assert_true(Diplomacy.memory_total(gs.get_player(2), 1) < 0,
		"the attacked player remembers the declaration")

# ── Open borders agreement (§7) ──────────────────────────────────────────────
# A bilateral, Writing-gated agreement granting mutual passage. Proposed via a trade
# carrying the open_borders flag, accepted by the other side, recorded on game state,
# torn up by war, and surviving save/load with int coercion.

func _give_tech(gs, pid, tech):
	gs.get_player(pid).technologies.append(tech)

func test_open_borders_requires_writing_to_propose() -> void:
	var gs = make_gs(2)
	var f = bare_facade(gs)
	gs.current_player_id = 1
	# Player 1 lacks Writing → the proposal is rejected and no offer is recorded.
	assert_false(f.apply_command(Commands.propose_open_borders(1, 2)),
		"Open-borders proposal rejected without the gating tech")
	assert_true(gs.get_alliance(1).pending_trades.empty(),
		"No pending trade is created by a rejected proposal")

func test_open_borders_proposable_with_writing() -> void:
	var gs = make_gs(2)
	_give_tech(gs, 1, "writing")
	var f = bare_facade(gs)
	gs.current_player_id = 1
	assert_true(f.apply_command(Commands.propose_open_borders(1, 2)),
		"With Writing the proposal is accepted onto the pending-trade queue")
	assert_eq(gs.get_alliance(1).pending_trades.size(), 1, "One offer pending")
	assert_true(bool(gs.get_alliance(1).pending_trades[0].get("open_borders", false)),
		"The pending offer carries the open_borders flag")

func test_open_borders_recorded_on_acceptance() -> void:
	var gs = make_gs(2)
	_give_tech(gs, 1, "writing")
	_give_tech(gs, 2, "writing")
	var f = bare_facade(gs)
	gs.current_player_id = 1
	f.apply_command(Commands.propose_open_borders(1, 2))
	var tid: int = int(gs.get_alliance(1).pending_trades[0].get("id", -1))
	gs.current_player_id = 2
	assert_true(f.apply_command(Commands.accept_trade(2, tid)), "Player 2 accepts")
	assert_true(gs.has_open_borders(1, 2), "Agreement recorded between the two players")
	assert_true(gs.has_open_borders(2, 1), "Agreement is order-independent")
	assert_true(Diplomacy.has_open_borders(gs, 1, 2), "Diplomacy reports the agreement")

func test_open_borders_not_recorded_when_accepter_lacks_tech() -> void:
	var gs = make_gs(2)
	_give_tech(gs, 1, "writing")  # only the proposer has it
	var f = bare_facade(gs)
	gs.current_player_id = 1
	f.apply_command(Commands.propose_open_borders(1, 2))
	var tid: int = int(gs.get_alliance(1).pending_trades[0].get("id", -1))
	gs.current_player_id = 2
	f.apply_command(Commands.accept_trade(2, tid))
	assert_false(gs.has_open_borders(1, 2),
		"No agreement forms when the accepting side lacks the gating tech")

func test_ai_accepts_open_borders_via_attitude() -> void:
	# PlayerAI._answer_trade_offers accepts a non-negative offer from a non-loathed
	# rival; an open-borders offer is value-neutral so a neutral AI accepts it.
	var gs = make_gs(2)
	_give_tech(gs, 1, "writing")
	_give_tech(gs, 2, "writing")
	gs.get_player(2).is_ai = true
	var f = bare_facade(gs)
	gs.current_player_id = 1
	f.apply_command(Commands.propose_open_borders(1, 2))
	gs.current_player_id = 2
	PlayerAI.manage_diplomacy(f, 2)
	assert_true(gs.has_open_borders(1, 2), "A neutral AI accepts a value-neutral open-borders offer")

func test_ai_declines_open_borders_when_furious() -> void:
	var gs = make_gs(2)
	_give_tech(gs, 1, "writing")
	_give_tech(gs, 2, "writing")
	gs.get_player(2).is_ai = true
	# Sour player 2's attitude toward player 1 below the accept threshold.
	for _i in range(6):
		Diplomacy.record(gs, gs.db, 2, 1, "declared_war")
	var f = bare_facade(gs)
	gs.current_player_id = 1
	f.apply_command(Commands.propose_open_borders(1, 2))
	gs.current_player_id = 2
	PlayerAI.manage_diplomacy(f, 2)
	assert_false(gs.has_open_borders(1, 2), "A furious AI declines the open-borders offer")

func test_declaring_war_ends_open_borders() -> void:
	var gs = make_gs(2)
	gs.add_open_borders(1, 2)
	var f = bare_facade(gs)
	gs.current_player_id = 1
	assert_true(gs.has_open_borders(1, 2), "Agreement stands before war")
	f.apply_command(Commands.declare_war(1, 2))
	assert_false(gs.has_open_borders(1, 2),
		"Declaring war tears up the open-borders agreement (at war you invade anyway)")

func test_cancel_open_borders_command() -> void:
	var gs = make_gs(2)
	gs.add_open_borders(1, 2)
	var f = bare_facade(gs)
	gs.current_player_id = 1
	assert_true(f.apply_command(Commands.cancel_open_borders(1, 2)), "Cancel accepted")
	assert_false(gs.has_open_borders(1, 2), "Agreement removed after cancel")
	# Cancelling again is a no-op (nothing to remove).
	assert_false(f.apply_command(Commands.cancel_open_borders(1, 2)),
		"Cancelling a nonexistent agreement is a no-op")

func test_open_borders_survives_save_load_with_int_coercion() -> void:
	var gs = make_gs(2)
	gs.add_open_borders(1, 2)
	var json = load("res://src/api/save_load.gd").save_to_string(gs)
	var gs2 = load("res://src/api/save_load.gd").load_from_string(json, gs.db)
	assert_true(gs2.has_open_borders(1, 2), "Agreement survives the save/load roundtrip")
	# The deserialized pair must use int keys, not JSON floats — has_open_borders
	# matches on int equality, so a float key would silently miss.
	assert_eq(typeof(int(gs2.open_borders[0]["a"])), TYPE_INT, "ids coerced to int")
	assert_true(gs2.has_open_borders(2, 1), "Lookup is order-independent post-load")

# ── §7 Deal denial reasons ────────────────────────────────────────────────────
# Diplomacy.evaluate_deal keeps the long-standing accept decision (net value >= 0
# AND attitude >= deal_accept_min_attitude) but names refusals with a structured
# reason id, resolved to display text from diplomacy.json denial_reasons.

# A pending-trades record from player 2 (alliance 2) addressed to alliance 1.
func _offer_from_2(gs, give, receive, peace = false):
	return {"id": gs.next_trade_id(), "proposer_player_id": 2,
		"from_alliance": 2, "to_alliance": 1,
		"give": give, "receive": receive, "peace": peace,
		"expires_turn": gs.turn_number + 20}

func test_evaluate_deal_accepts_a_fair_offer_with_no_reason() -> void:
	var gs = make_gs(2)
	var t = _offer_from_2(gs, {"gold": 50}, {})
	assert_eq(Diplomacy.evaluate_deal(gs, gs.db, 1, t), "",
		"a net-positive offer from a neutral rival is accepted (empty reason)")

func test_attitude_gate_returns_attitude_too_low() -> void:
	# Three players: the proposer (2) is furious-level but NOT the worst enemy —
	# player 3 scores even lower — so the plain attitude reason is named.
	var gs = make_gs(3)
	gs.get_alliance(1).contacts.append(2)
	gs.get_alliance(1).contacts.append(3)
	Diplomacy.record(gs, gs.db, 1, 2, "razed_city")       # score 10 (furious)
	Diplomacy.record(gs, gs.db, 1, 3, "razed_city")
	Diplomacy.record(gs, gs.db, 1, 3, "declared_war")     # score 0 (the worst)
	assert_true(Diplomacy.attitude_level(gs, gs.db, 1, 2) <
		int(gs.db.get_diplomacy().get("deal_accept_min_attitude", 1)),
		"precondition: attitude below the deal gate")
	var t = _offer_from_2(gs, {"gold": 50}, {})
	assert_eq(Diplomacy.evaluate_deal(gs, gs.db, 1, t), "attitude_too_low",
		"the deal_accept_min_attitude gate names its reason")

func test_worst_enemy_refines_the_attitude_reason() -> void:
	# Two players: the furious-level proposer is necessarily the lowest-scoring met
	# rival, so the refusal is reported as worst_enemy (decision unchanged).
	var gs = make_gs(2)
	gs.get_alliance(1).contacts.append(2)
	Diplomacy.record(gs, gs.db, 1, 2, "razed_city")
	assert_eq(Diplomacy.attitude_level(gs, gs.db, 1, 2), Diplomacy.FURIOUS,
		"precondition: the proposer is loathed")
	var t = _offer_from_2(gs, {"gold": 50}, {})
	assert_eq(Diplomacy.evaluate_deal(gs, gs.db, 1, t), "worst_enemy",
		"a furious lowest-scoring rival is refused as the worst enemy")

func test_war_without_peace_clause_returns_no_trade_with_warring_party() -> void:
	var gs = make_gs(2)
	gs.get_alliance(1).at_war_with = [2]
	gs.get_alliance(2).at_war_with = [1]
	var t = _offer_from_2(gs, {"gold": 50}, {})   # good value, but we are at war
	assert_eq(Diplomacy.evaluate_deal(gs, gs.db, 1, t), "no_trade_with_warring_party",
		"a non-peace offer from a warring party names the war as the reason")

func test_peace_clause_offer_is_not_war_blocked() -> void:
	# A peace-clause offer at war is evaluated on its merits: the peace clause is
	# worth a tech's weight, so the value gate passes and only attitude refuses it.
	var gs = make_gs(2)
	gs.get_alliance(1).at_war_with = [2]
	gs.get_alliance(2).at_war_with = [1]
	var t = _offer_from_2(gs, {}, {}, true)
	var reason: String = Diplomacy.evaluate_deal(gs, gs.db, 1, t)
	assert_true(reason != "no_trade_with_warring_party",
		"a peace offer is never refused as trade-with-warring-party (got '%s')" % reason)

func test_tech_ask_returns_tech_refusal() -> void:
	var gs = make_gs(2)
	gs.get_player(1).technologies = ["mining"]
	var t = _offer_from_2(gs, {}, {"techs": ["mining"]})  # pry a tech off us for free
	assert_eq(Diplomacy.evaluate_deal(gs, gs.db, 1, t), "tech_refusal",
		"an uncompensated tech ask is refused as a tech refusal")

func test_bad_bargain_returns_insufficient_value() -> void:
	var gs = make_gs(2)
	var t = _offer_from_2(gs, {}, {"gold": 40})   # we pay 40 for nothing
	assert_eq(Diplomacy.evaluate_deal(gs, gs.db, 1, t), "insufficient_value",
		"a plain bad bargain is refused for insufficient value")

func test_denial_text_covers_every_reason_id() -> void:
	var gs = make_gs(2)
	for rid in ["no_trade_with_warring_party", "worst_enemy", "attitude_too_low",
			"tech_refusal", "insufficient_value"]:
		assert_true(Diplomacy.denial_text(gs.db, rid) != "",
			"denial reason '%s' resolves to display text" % rid)
	assert_eq(Diplomacy.denial_text(gs.db, "no_such_reason"), "",
		"an unknown reason id resolves to empty text")

func test_reject_with_reason_records_denial_and_event() -> void:
	var gs = make_gs(2)
	var f = bare_facade(gs)
	f._cmd_propose_trade({"player_id": 1, "target_alliance_id": 2,
		"give": {}, "receive": {"gold": 40}, "peace": false})
	var tid: int = int(gs.alliances[0].pending_trades[0]["id"])
	gs.current_player_id = 2
	assert_true(f.apply_command(Commands.reject_trade(2, tid, "insufficient_value")),
		"reject with a reason succeeds")
	var denial: Dictionary = gs.deal_denials.get(1, {}).get(2, {})
	assert_eq(str(denial.get("reason", "")), "insufficient_value",
		"the denial is remembered against the proposer/rejector pair")
	var found: bool = false
	for e in gs.pending_deal_events:
		if str(e.get("kind", "")) == "deal_rejected" \
				and str(e.get("reason", "")) == "insufficient_value":
			found = true
	assert_true(found, "a deal_rejected event is queued for surfacing")

func test_reject_without_reason_stays_silent() -> void:
	var gs = make_gs(2)
	var f = bare_facade(gs)
	f._cmd_propose_trade({"player_id": 1, "target_alliance_id": 2,
		"give": {}, "receive": {"gold": 40}, "peace": false})
	var tid: int = int(gs.alliances[0].pending_trades[0]["id"])
	gs.current_player_id = 2
	assert_true(f.apply_command(Commands.reject_trade(2, tid)), "bare reject succeeds")
	assert_true(gs.deal_denials.empty(), "no denial recorded for a silent rejection")
	assert_true(gs.pending_deal_events.empty(), "no surfacing event for a silent rejection")

func test_deal_rejected_event_drains_to_a_reasoned_notification() -> void:
	var gs = make_gs(2)
	var f = bare_facade(gs)
	gs.pending_deal_events.append({"kind": "deal_rejected", "trade_id": 7,
		"reason": "attitude_too_low", "rejector_player_id": 2, "proposer_player_id": 1})
	f._drain_deal_events()
	var text: String = ""
	for n in f.get_notification_queue():
		text += str(n.get("text", "")) + "\n"
	assert_true(Diplomacy.denial_text(gs.db, "attitude_too_low") in text,
		"the drained notification carries the denial display text")
	assert_true(gs.get_player(2).name in text,
		"the drained notification names the rejector")

func test_deal_denials_survive_save_load_as_ints() -> void:
	var gs = make_gs(2)
	gs.deal_denials[1] = {2: {"reason": "worst_enemy", "turn": 3}}
	var json = load("res://src/api/save_load.gd").save_to_string(gs)
	var gs2 = load("res://src/api/save_load.gd").load_from_string(json, gs.db)
	assert_true(gs2.deal_denials.has(1),
		"the proposer key is coerced back to int after the JSON roundtrip")
	assert_true(gs2.deal_denials[1].has(2),
		"the rejector key is coerced back to int after the JSON roundtrip")
	assert_eq(str(gs2.deal_denials[1][2].get("reason", "")), "worst_enemy",
		"the reason id survives the roundtrip")
	assert_eq(int(gs2.deal_denials[1][2].get("turn", -1)), 3,
		"the turn stamp survives (and is an int)")
