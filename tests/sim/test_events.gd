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

# Events & exploration (§9): the events table loads, scripted events fire once
# after their min-turn, and entering a discovery site consumes it for a reward.

func test_events_table_loads() -> void:
	var gs = make_gs()
	assert_true(gs.db.events.has("ancient_windfall"), "events.json loads into DataDB")
	assert_true(gs.db.get_errors().empty(), "DataDB still loads cleanly with the events table")

# Isolate the certain prob-100 ancient_windfall trigger by pre-firing the other
# probabilistic one-shots so only it can arm — deterministic regardless of seed.
func _only_windfall(gs) -> void:
	var p = gs.get_player(1)
	for tid in gs.db.get_event_triggers():
		if tid != "_comment" and tid != "trig_ancient_windfall":
			p.events_fired.append(tid)

func test_scripted_event_fires_once_after_min_turn() -> void:
	var gs = make_gs()
	_only_windfall(gs)
	var p = gs.get_player(1)
	p.treasury = 0
	gs.turn_number = 10  # >= min_turn 8
	var fired = Events.process_player_events(p, gs, gs.rng)
	assert_eq(fired.size(), 1, "Event fires when its trigger's min_turn is reached")
	assert_eq(str(fired[0].get("event_id", "")), "ancient_windfall", "windfall fired")
	assert_eq(p.treasury, 50, "Event gold effect applied")
	Events.process_player_events(p, gs, gs.rng)
	assert_eq(p.treasury, 50, "A once-fired one-shot trigger does not repeat")

func test_scripted_event_held_before_min_turn() -> void:
	var gs = make_gs()
	_only_windfall(gs)
	gs.turn_number = 2  # < min_turn 8
	var fired = Events.process_player_events(gs.get_player(1), gs, gs.rng)
	assert_true(fired.empty(), "Event does not fire before its trigger's min_turn")

# ── Trigger predicates (§9) ──────────────────────────────────────────────────────

func test_trigger_turn_window() -> void:
	var gs = make_gs()
	var p = gs.get_player(1)
	var trig = {"id": "t", "min_turn": 5, "max_turn": 10}
	gs.turn_number = 4
	assert_false(Events.trigger_holds(trig, p, gs), "before the window the trigger is inert")
	gs.turn_number = 7
	assert_true(Events.trigger_holds(trig, p, gs), "inside the window the trigger holds")
	gs.turn_number = 11
	assert_false(Events.trigger_holds(trig, p, gs), "past max_turn the trigger is inert")

func test_trigger_tech_gate() -> void:
	var gs = make_gs()
	var p = gs.get_player(1)
	var trig = {"id": "t", "tech_required": "writing"}
	assert_false(Events.trigger_holds(trig, p, gs), "no tech -> predicate fails")
	p.technologies.append("writing")
	assert_true(Events.trigger_holds(trig, p, gs), "with the tech -> predicate holds")

func test_trigger_building_gate() -> void:
	var gs = make_gs()
	var p = gs.get_player(1)
	var trig = {"id": "t", "building_required": "granary"}
	assert_false(Events.trigger_holds(trig, p, gs), "no granary -> predicate fails")
	var s = make_settlement(gs, 1, 5, 5)
	s.structures.append("granary")
	assert_true(Events.trigger_holds(trig, p, gs), "owning a granary -> predicate holds")

func test_trigger_war_gate() -> void:
	var gs = make_gs()
	var trig = {"id": "t", "at_war": true}
	assert_false(Events.trigger_holds(trig, gs.get_player(1), gs), "at peace -> war predicate fails")
	# Players 1 and 2 start in separate alliances (id == player id); set them at war.
	gs.get_alliance(1).at_war_with.append(2)
	gs.get_alliance(2).at_war_with.append(1)
	assert_true(Events.trigger_holds(trig, gs.get_player(1), gs), "at war -> predicate holds")

func test_trigger_one_shot_blocks_refire() -> void:
	var gs = make_gs()
	var p = gs.get_player(1)
	var trig = {"id": "trig_x", "one_shot": true}
	assert_true(Events.trigger_holds(trig, p, gs), "unfired one-shot is eligible")
	p.events_fired.append("trig_x")
	assert_false(Events.trigger_holds(trig, p, gs), "a fired one-shot is no longer eligible")

# ── Effect verbs (§9) ────────────────────────────────────────────────────────────

func test_begin_effects_gold_and_unit_and_building() -> void:
	var gs = make_gs()
	var p = gs.get_player(1)
	p.treasury = 0
	var cap = make_settlement(gs, 1, 5, 5)
	var before_units = gs.units.size()
	Events.apply_event_begin({
		"effects": [
			{"verb": "gold", "amount": 25},
			{"verb": "unit", "unit_type": "worker", "count": 2},
			{"verb": "building", "structure_id": "monument"}
		]}, p, gs)
	assert_eq(p.treasury, 25, "gold verb banks gold")
	assert_eq(gs.units.size(), before_units + 2, "unit verb spawns count units at the capital")
	assert_true(cap.has_structure("monument"), "building verb adds a free structure to the capital")

func test_capital_of_prefers_palace() -> void:
	var gs = make_gs()
	make_settlement(gs, 1, 5, 5)            # lower id, no palace
	var pal = make_settlement(gs, 1, 8, 8)  # higher id, palace
	pal.structures.append("palace")
	assert_eq(Events.capital_of(1, gs).id, pal.id, "the Palace city is the event capital")

# ── Choice events (§9) ───────────────────────────────────────────────────────────

func test_choice_event_ai_auto_resolves() -> void:
	var gs = make_gs()
	var p = gs.get_player(1)
	p.is_ai = true
	p.treasury = 0
	make_settlement(gs, 1, 5, 5)
	var trig = {"id": "trig_wandering_nomads", "event_id": "wandering_nomads"}
	var d = Events._fire(trig, p, gs)
	assert_eq(str(d.get("kind", "")), "event_fired", "an AI resolves a choice event in-pipeline")
	assert_true(gs.pending_event_choices.empty(), "no human choice is queued for an AI")

func test_choice_event_blocks_then_applies_branch() -> void:
	# A human's choice event parks a pending choice + raises a popup; resolving it
	# applies exactly the chosen branch.
	var f = setup_facade()
	var gs = f.get_state()
	var p = gs.get_player(1)
	p.is_ai = false
	p.treasury = 0
	var trig = {"id": "trig_wandering_nomads", "event_id": "wandering_nomads"}
	Events._fire(trig, p, gs)
	assert_eq(gs.pending_event_choices.size(), 1, "a human choice event parks a pending choice")
	f._maybe_raise_event_popup(1)
	assert_eq(int(f.get_pending_popup().get("type", -1)), IDs.PopupType.EVENT,
		"the human is shown the event popup")
	var before_units = gs.units.size()
	assert_true(f.apply_command(Commands.resolve_event(1, "wandering_nomads", "tax")),
		"resolving the choice succeeds")
	assert_eq(p.treasury, 30, "the chosen 'tax' branch (gold 30) applied")
	assert_eq(gs.units.size(), before_units, "the unchosen 'welcome' branch (worker) did not apply")
	assert_true(gs.pending_event_choices.empty(), "the pending choice is cleared after resolving")
	assert_true(f.get_pending_popup().empty(), "the popup is popped after resolving")

# ── Timed events (§9) ────────────────────────────────────────────────────────────

func test_timed_event_expires_on_schedule() -> void:
	var gs = make_gs()
	var p = gs.get_player(1)
	var cap = make_settlement(gs, 1, 5, 5)
	cap.health = 100
	Events.apply_event_begin(gs.db.get_event("great_plague"), p, gs)
	assert_eq(cap.health, 96, "the plague's begin effect lowers capital health")
	assert_eq(gs.active_events.size(), 1, "a timed event is registered as active")
	# duration 5: it persists for 4 ticks, expiring (restoring) on the 5th.
	for i in range(4):
		var produced = Events.tick_active_events(p, gs)
		assert_true(produced.empty(), "still active on tick %d" % (i + 1))
		assert_eq(cap.health, 96, "health unchanged while the event persists")
	var last = Events.tick_active_events(p, gs)
	assert_eq(last.size(), 1, "the event expires on its scheduled tick")
	assert_eq(str(last[0].get("kind", "")), "event_expired", "an expiry descriptor is produced")
	assert_eq(cap.health, 100, "the expire effect restores capital health")
	assert_true(gs.active_events.empty(), "the expired event is removed from the active list")

# A timed event already running for a player must not re-fire — otherwise a
# non-one_shot timed trigger (the plague) re-arms each turn while still active,
# stacking overlapping instances that spam begin/expire log lines and stack their
# health deltas. The guard lives in trigger_holds so it is checked before the roll.
func test_active_timed_event_blocks_refire() -> void:
	var gs = make_gs()
	var p = gs.get_player(1)
	make_settlement(gs, 1, 5, 5).health = 100
	gs.turn_number = 30  # past the plague's min_turn (25)
	# A plague is already running for this player.
	Events.apply_event_begin(gs.db.get_event("great_plague"), p, gs)
	assert_eq(gs.active_events.size(), 1, "one plague active")
	var trig = gs.db.event_triggers["trig_great_plague"]
	assert_false(Events.trigger_holds(trig, p, gs),
		"the plague trigger does not hold while a plague is already active")
	# A different player with no active plague is still eligible.
	if gs.players.size() > 1:
		assert_true(Events.trigger_holds(trig, gs.get_player(2), gs),
			"another player without an active plague is still eligible")

# Drive the plague over many turns at probability 100 and assert it never overlaps
# itself: at most one active instance at a time, and the begin/expire log entries
# come in clean single pairs (no per-turn start/stop spam).
func test_plague_does_not_re_fire_while_active() -> void:
	var gs = make_gs()
	var p = gs.get_player(1)
	make_settlement(gs, 1, 5, 5).health = 100
	# Force the plague to be the only eligible trigger and certain to fire.
	for tid in gs.db.get_event_triggers():
		if tid != "_comment" and tid != "trig_great_plague":
			p.events_fired.append(tid)
	gs.db.event_triggers["trig_great_plague"]["probability"] = 100
	var begins = 0
	var expires = 0
	var max_active = 0
	for t in range(30, 60):
		gs.turn_number = t
		var produced = Events.process_player_events(p, gs, gs.rng)
		for d in produced:
			match str(d.get("kind", "")):
				"event_fired":
					if str(d.get("event_id", "")) == "great_plague":
						begins += 1
				"event_expired":
					if str(d.get("event_id", "")) == "great_plague":
						expires += 1
		if gs.active_events.size() > max_active:
			max_active = gs.active_events.size()
	assert_eq(max_active, 1, "never more than one plague active at a time")
	assert_true(begins >= 1, "the plague does begin at least once")
	# With duration 5 and no overlap, begins and expires stay within one of each
	# other (an in-flight plague may not have expired by the final turn).
	assert_true(abs(begins - expires) <= 1,
		"begin/expire entries are paired — no per-turn start/stop spam (begins=%d expires=%d)" % [begins, expires])

func test_timed_event_survives_save_load() -> void:
	# Determinism: an in-progress timed event + a parked human choice roundtrip
	# through save/load with their int fields intact (the JSON-key gotcha).
	var gs = make_gs()
	var p = gs.get_player(1)
	make_settlement(gs, 1, 5, 5).health = 100
	Events.apply_event_begin(gs.db.get_event("great_plague"), p, gs)
	gs.pending_event_choices.append({"event_id": "wandering_nomads", "player_id": 1, "trigger_id": "t"})
	var gs2 = GameState.deserialize(gs.serialize(), gs.db)
	assert_eq(gs2.active_events.size(), 1, "active timed event roundtrips")
	assert_eq(typeof(gs2.active_events[0]["turns_left"]), TYPE_INT, "turns_left coerced to int")
	assert_eq(int(gs2.active_events[0]["player_id"]), 1, "active event player_id coerced to int")
	assert_eq(gs2.pending_event_choices.size(), 1, "parked human choice roundtrips")
	assert_eq(int(gs2.pending_event_choices[0]["player_id"]), 1, "pending-choice player_id coerced to int")

func test_entering_discovery_site_yields_reward() -> void:
	var gs = make_gs()
	var f = bare_facade(gs)
	gs.map.get_tile(6, 5).has_discovery = true
	make_unit(gs, "warrior", 1, 5, 5)
	f._cmd_move_stack({"player_id": 1, "from_x": 5, "from_y": 5, "to_x": 6, "to_y": 5})
	assert_false(gs.map.get_tile(6, 5).has_discovery, "Discovery site is consumed on entry")

# ── Goody-hut reward table (§9) ──────────────────────────────────────────────────

func test_goodies_table_loads() -> void:
	var gs = make_gs()
	assert_true(gs.db.get_goodies().size() > 0, "goodies.json loads a non-empty reward list")
	assert_true(gs.db.get_errors().empty(), "DataDB still loads cleanly with the goodies table")

func test_goody_treasury_adds_gold() -> void:
	var gs = make_gs()
	var u = make_unit(gs, "warrior", 1, 5, 5)
	gs.get_player(1).treasury = 0
	var r = Events._apply_goody({"type": "treasury", "min": 50, "max": 50}, u, gs, gs.rng)
	assert_eq(r["type"], "treasury")
	assert_eq(gs.get_player(1).treasury, 50, "treasury goody banks gold for the owner")

func test_goody_heal_restores_unit() -> void:
	var gs = make_gs()
	var u = make_unit(gs, "warrior", 1, 5, 5)
	u.health = 10
	Events._apply_goody({"type": "heal"}, u, gs, gs.rng)
	assert_eq(u.health, gs.db.get_constant("max_hp", 100), "heal goody restores full health")

func test_goody_experience_adds_xp() -> void:
	var gs = make_gs()
	var u = make_unit(gs, "warrior", 1, 5, 5)
	u.experience = 0
	Events._apply_goody({"type": "experience", "min": 7, "max": 7}, u, gs, gs.rng)
	assert_eq(u.experience, 7, "experience goody adds XP to the discoverer")

func test_goody_unit_spawns_free_unit() -> void:
	var gs = make_gs()
	var u = make_unit(gs, "warrior", 1, 5, 5)
	var before = gs.units.size()
	var r = Events._apply_goody({"type": "unit", "unit_type": "warrior"}, u, gs, gs.rng)
	assert_eq(gs.units.size(), before + 1, "unit goody spawns a free unit")
	assert_true(int(r.get("unit_id", -1)) >= 0, "unit goody returns the new unit id")
	var spawned = gs.get_unit(int(r["unit_id"]))
	assert_eq(spawned.owner_player_id, 1, "the free unit belongs to the discoverer")
	assert_eq([spawned.x, spawned.y], [5, 5], "the free unit appears on the discoverer's tile")

func test_goody_tech_grants_free_tech() -> void:
	var gs = make_gs()
	var u = make_unit(gs, "warrior", 1, 5, 5)
	var p = gs.get_player(1)
	p.technologies = ["agriculture"]
	var before = p.technologies.size()
	var r = Events._apply_goody({"type": "tech"}, u, gs, gs.rng)
	assert_true(str(r.get("tech_id", "")) != "", "tech goody grants a researchable tech")
	assert_eq(p.technologies.size(), before + 1, "the granted tech is added to the player")

func test_goody_ambush_hurts_but_never_kills() -> void:
	var gs = make_gs()
	var u = make_unit(gs, "warrior", 1, 5, 5)
	u.health = 30
	Events._apply_goody({"type": "ambush", "damage": 50}, u, gs, gs.rng)
	assert_eq(u.health, 1, "ambush floors the discoverer at 1 health, never killing it")

func test_exploration_reward_is_rng_deterministic() -> void:
	var a = make_gs(1, 4242)
	var ua = make_unit(a, "warrior", 1, 5, 5)
	var ra = Events.exploration_reward(ua, a, a.rng)
	var b = make_gs(1, 4242)
	var ub = make_unit(b, "warrior", 1, 5, 5)
	var rb = Events.exploration_reward(ub, b, b.rng)
	assert_eq(ra["type"], rb["type"], "the same seed rolls the same goody type")
