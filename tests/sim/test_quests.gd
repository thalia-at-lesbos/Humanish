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

# Multi-turn quest tracking subsystem (§4). The catalogue loads & validates, eligible
# quests arm deterministically, an aim completes over turns and queues its reward, a
# 3-choice reward parks a pending choice reusing the event machinery, a violated
# constraint drops the quest, and a quest record survives save/load with int typing.

# Give a player a tech directly (refreshing the era cache like Events does).
func _grant_tech(gs, pid, tech_id):
	var p = gs.get_player(pid)
	if not p.has_tech(tech_id):
		p.technologies.append(tech_id)
		Eras.refresh(p, gs.db)

# A settlement for `pid` that holds a library (the build_count aim counts one per city).
func _city_with_library(gs, pid, x, y):
	var s = make_settlement(gs, pid, x, y, 3)
	s.structures.append("library")
	return s

# ── Canary (per the GUT script-load gotcha) ──────────────────────────────────────

func test_quests_script_can_instance() -> void:
	var script = load("res://src/sim/quests.gd")
	assert_true(script.can_instance(), "quests.gd compiles (guards the GUT green-on-load-error gotcha)")

# ── Catalogue loads & validates ──────────────────────────────────────────────────

func test_quests_table_loads_and_validates() -> void:
	var gs = make_gs()
	assert_true(gs.db.get_quests().has("classic_literature"), "quests.json loads into DataDB")
	assert_true(gs.db.get_errors().empty(), "DataDB validates the quest catalogue cleanly")

func test_full_18_quest_catalogue_present_and_parses() -> void:
	var gs = make_gs()
	var quests = gs.db.get_quests()
	# 18 quests + the leading _comment schema key = 19 entries.
	var real := []
	for qid in quests:
		if qid != "_comment":
			real.append(qid)
	assert_eq(real.size(), 18, "all 18 quests are present in the catalogue")
	# Every quest declares an id, aim kind, and reward (effects or choices).
	for qid in real:
		var q = quests[qid]
		assert_eq(str(q.get("id", "")), qid, "quest '%s' carries a matching id" % qid)
		assert_ne(str(q.get("aim", {}).get("kind", "")), "", "quest '%s' declares an aim kind" % qid)
		var reward = q.get("reward", {})
		assert_true(not reward.get("effects", []).empty() or not reward.get("choices", []).empty(),
			"quest '%s' declares a reward (effects or choices)" % qid)
	assert_true(gs.db.get_errors().empty(), "the full 18-quest catalogue validates cleanly")

func test_roll_active_quests_includes_active_100_quest() -> void:
	var gs = make_gs()
	Quests.roll_active_quests(gs)
	assert_true("classic_literature" in gs.active_quest_ids, "an active=100 quest is always rostered")

func test_roll_active_quests_is_deterministic() -> void:
	var a = make_gs(2, 555)
	Quests.roll_active_quests(a)
	var b = make_gs(2, 555)
	Quests.roll_active_quests(b)
	assert_eq(a.active_quest_ids, b.active_quest_ids, "the same seed rolls the same quest roster")

# ── Arming: prereq gating ────────────────────────────────────────────────────────

func test_quest_arms_when_prereq_met() -> void:
	var gs = make_gs()
	var p = gs.get_player(1)
	make_settlement(gs, 1, 5, 5)
	_grant_tech(gs, 1, "writing")
	assert_true(Quests.quest_eligible("classic_literature", p, gs),
		"a quest whose prereq holds is eligible to arm")
	var armed = Quests.arm_quest("classic_literature", p, gs)
	assert_eq(str(armed.get("kind", "")), "quest_armed", "arm_quest reports an armed descriptor")
	assert_eq(gs.active_quests.size(), 1, "the armed quest is tracked on active_quests")
	# The descriptor carries the flavour text and the concrete objective so the UI
	# can describe the quest to the player when it starts (§4).
	assert_true(str(armed.get("text", "")) != "", "arm descriptor carries the quest flavour text")
	assert_eq(str(armed.get("objective", "")), "Build 7 libraries.",
		"arm descriptor carries the authored objective")

func test_every_quest_has_an_objective() -> void:
	var db = make_db()
	for qid in db.get_quests():
		if qid == "_comment":
			continue
		var q = db.get_quest(qid)
		assert_true(str(q.get("objective", "")) != "",
			"quest '%s' has an authored objective" % qid)

func test_quest_not_eligible_without_prereq() -> void:
	var gs = make_gs()
	var p = gs.get_player(1)
	make_settlement(gs, 1, 5, 5)
	# No writing tech → prereq fails.
	assert_false(Quests.quest_eligible("classic_literature", p, gs),
		"a quest whose prereq fails is not eligible")

func test_quest_not_re_armed_when_already_active_or_completed() -> void:
	var gs = make_gs()
	var p = gs.get_player(1)
	make_settlement(gs, 1, 5, 5)
	_grant_tech(gs, 1, "writing")
	Quests.arm_quest("classic_literature", p, gs)
	assert_false(Quests.quest_eligible("classic_literature", p, gs),
		"an already-active quest is not eligible to re-arm")
	gs.active_quests = []
	p.quests_completed.append("classic_literature")
	assert_false(Quests.quest_eligible("classic_literature", p, gs),
		"an already-completed quest is not eligible to re-arm")

# ── Arming: grace period + random era-chance trigger ─────────────────────────────

func test_no_quest_arms_during_grace_period() -> void:
	var gs = make_gs()
	var p = gs.get_player(1)
	make_settlement(gs, 1, 5, 5)
	_grant_tech(gs, 1, "writing")  # classic_literature is eligible
	gs.db.constants["quest_era_chance"] = [100, 100, 100, 100, 100, 100, 100]  # force the roll
	gs.turn_number = 5             # within the 20-turn grace
	Quests.process_player_quests(p, gs, gs.rng)
	assert_eq(gs.active_quests.size(), 0, "no quest arms within the grace period")
	gs.turn_number = 25            # past the grace
	Quests.process_player_quests(p, gs, gs.rng)
	assert_eq(gs.active_quests.size(), 1, "a quest can arm once past the grace period")

func test_arming_is_gated_by_the_era_chance() -> void:
	var gs = make_gs()
	var p = gs.get_player(1)
	make_settlement(gs, 1, 5, 5)
	_grant_tech(gs, 1, "writing")
	gs.turn_number = 30
	gs.db.constants["quest_era_chance"] = [0, 0, 0, 0, 0, 0, 0]
	Quests.process_player_quests(p, gs, gs.rng)
	assert_eq(gs.active_quests.size(), 0, "a zero era chance never arms a quest (random trigger)")
	gs.db.constants["quest_era_chance"] = [100, 100, 100, 100, 100, 100, 100]
	Quests.process_player_quests(p, gs, gs.rng)
	assert_eq(gs.active_quests.size(), 1, "a full era chance arms a quest past the grace")

func test_multiple_quests_can_be_active_at_once() -> void:
	var gs = make_gs()
	var p = gs.get_player(1)
	make_settlement(gs, 1, 5, 5)
	_grant_tech(gs, 1, "writing")
	_grant_tech(gs, 1, "animal_husbandry")  # classic_literature + horse_whispering eligible
	gs.turn_number = 25
	gs.db.constants["quest_era_chance"] = [100, 100, 100, 100, 100, 100, 100]
	Quests.process_player_quests(p, gs, gs.rng)
	Quests.process_player_quests(p, gs, gs.rng)
	assert_eq(gs.active_quests.size(), 2, "a player may run multiple quests at once")

# ── Progress + completion + the 3-choice reward ──────────────────────────────────

func test_build_count_progress_advances() -> void:
	var gs = make_gs()
	var p = gs.get_player(1)
	var s = _city_with_library(gs, 1, 5, 5)
	_grant_tech(gs, 1, "writing")
	Quests.arm_quest("classic_literature", p, gs)
	var rec = gs.active_quests[0]
	assert_eq(int(rec.get("progress", 0)), 1, "progress reflects the one library at arming")
	# A second library in another city advances progress on re-evaluation.
	var s2 = _city_with_library(gs, 1, 8, 8)
	Quests._evaluate_active(p, gs)
	assert_eq(int(gs.active_quests[0].get("progress", 0)), 2, "progress advances as libraries are built")

func test_quest_completes_and_parks_pending_choice_for_human() -> void:
	var gs = make_gs()
	var p = gs.get_player(1)
	p.is_ai = false
	# Seven libraries spread across cities (the aim count is 7).
	for i in range(7):
		_city_with_library(gs, 1, 2 + i, 2)
	_grant_tech(gs, 1, "writing")
	Quests.arm_quest("classic_literature", p, gs)
	var produced = Quests._evaluate_active(p, gs)
	assert_eq(gs.active_quests.size(), 0, "the completed quest is removed from active tracking")
	assert_true("classic_literature" in p.quests_completed, "completion is recorded on the player")
	assert_eq(produced.size(), 1, "one completion descriptor is produced")
	assert_eq(str(produced[0].get("kind", "")), "quest_reward_pending",
		"a 3-choice reward parks a pending choice (not auto-applied) for a human")
	# The choice is parked into the SAME pending_event_choices machinery (quest:<id>).
	var pending = gs.pending_event_choices
	assert_eq(pending.size(), 1, "the reward choice is parked into pending_event_choices")
	assert_eq(str(pending[0].get("event_id", "")), "quest:classic_literature",
		"the parked choice carries a synthetic quest event_id")
	assert_eq((pending[0].get("resolved_choices", [])).size(), 3, "all three reward branches are parked")

func test_human_resolves_reward_choice_via_event_path() -> void:
	var gs = make_gs()
	var p = gs.get_player(1)
	p.is_ai = false
	for i in range(7):
		_city_with_library(gs, 1, 2 + i, 2)
	_grant_tech(gs, 1, "writing")
	Quests.arm_quest("classic_literature", p, gs)
	Quests._evaluate_active(p, gs)
	# Resolve the "ancient tech" branch through the shared Events.apply_choice path.
	var before = p.technologies.size()
	var ok = Events.apply_choice("quest:classic_literature", "ancient_tech", p, gs)
	assert_true(ok, "the parked quest reward branch resolves through Events.apply_choice")
	assert_true(p.technologies.size() > before, "the ancient-tech reward granted a free technology")

func test_ai_auto_resolves_reward() -> void:
	var gs = make_gs()
	var p = gs.get_player(1)
	p.is_ai = true
	for i in range(7):
		_city_with_library(gs, 1, 2 + i, 2)
	_grant_tech(gs, 1, "writing")
	Quests.arm_quest("classic_literature", p, gs)
	var produced = Quests._evaluate_active(p, gs)
	assert_eq(str(produced[0].get("kind", "")), "quest_completed",
		"an AI auto-resolves the reward (no pending choice parked)")
	assert_true(gs.pending_event_choices.empty(), "no choice is parked for an AI")
	# ai_prefer branch is research_libraries → every library gains +2 research.
	var lib_bonus = 0
	for s in gs.settlements:
		if s.has_structure("library"):
			lib_bonus = s.structure_yield("research")
			break
	assert_eq(lib_bonus, 2, "the AI took the preferred +2-research-per-library branch")

# ── Constraint violation drops the quest ─────────────────────────────────────────

func test_constraint_violation_drops_quest() -> void:
	var gs = make_gs()
	var p = gs.get_player(1)
	make_settlement(gs, 1, 5, 5)
	_grant_tech(gs, 1, "writing")
	p.state_religion = "judaism"
	# Inject a constraint onto the catalogue copy this state owns (each make_gs has its
	# own DataDB), so the snapshot stamps the religion-at-arming baseline.
	gs.db.quests["classic_literature"]["constraint"] = {"kind": "never_switch_state_religion"}
	Quests.arm_quest("classic_literature", p, gs)
	assert_eq(gs.active_quests.size(), 1, "the quest armed with a constraint snapshot")
	# Switch state religion → constraint violated → dropped on re-evaluation.
	p.state_religion = "christianity"
	var produced = Quests._evaluate_active(p, gs)
	assert_eq(gs.active_quests.size(), 0, "switching state religion drops the constrained quest")
	assert_eq(str(produced[0].get("kind", "")), "quest_failed", "a failure descriptor is produced")

# ── Save/load roundtrip + determinism (the JSON int-key gotcha) ──────────────────

func test_active_quests_survive_save_load_with_int_typing() -> void:
	var gs = make_gs()
	var p = gs.get_player(1)
	# Hand-build a record whose snapshot carries int settlement-id keys/values plus the
	# state-religion sentinel, so the deserialize int-coercion path is exercised.
	gs.active_quests.append({
		"quest_id": "classic_literature",
		"player_id": 1,
		"start_turn": 12,
		"progress": 3,
		"snapshot": {7: 1, 9: 1, Quests.STATE_RELIGION_KEY: "judaism"}
	})
	gs.active_quest_ids = ["classic_literature"]
	var json = JSON.print(gs.serialize())
	var parsed = JSON.parse(json).result
	var gs2 = GameState.deserialize(parsed, gs.db)
	assert_eq(gs2.active_quests.size(), 1, "the quest record survives the roundtrip")
	var rec = gs2.active_quests[0]
	assert_eq(typeof(rec["player_id"]), TYPE_INT, "player_id is int after load")
	assert_eq(typeof(rec["start_turn"]), TYPE_INT, "start_turn is int after load")
	assert_eq(typeof(rec["progress"]), TYPE_INT, "progress is int after load")
	var snap = rec["snapshot"]
	# The int settlement-id keys must be int (not the JSON "7" string) and their values int.
	assert_true(snap.has(7), "snapshot int settlement-id key 7 survives as an int key")
	assert_eq(typeof(snap.keys()[0]), TYPE_INT, "snapshot keys are int after load")
	assert_eq(typeof(snap[7]), TYPE_INT, "snapshot int values survive as int")
	assert_eq(str(snap[Quests.STATE_RELIGION_KEY]), "judaism",
		"the state-religion sentinel snapshot value survives as a string")
	assert_eq(gs2.active_quest_ids, ["classic_literature"], "the quest roster survives the roundtrip")

# ── New aim kinds (full §4 catalogue) ────────────────────────────────────────────

# Paint a rectangular patch of tiles with a terrain (and optional owner). Used to carve
# distinct landmasses out of the default all-grassland map.
func _paint(gs, x0, y0, x1, y1, terrain, owner = -2):
	for y in range(y0, y1 + 1):
		for x in range(x0, x1 + 1):
			var t = gs.map.get_tile(x, y)
			if t != null:
				t.terrain_id = terrain
				if owner != -2:
					t.owner_player_id = owner

func test_cities_on_landmasses_counts_distinct_masses() -> void:
	var gs = make_gs(2, 42, 20, 20)
	var p = gs.get_player(1)
	# Flood the whole map with ocean, then carve three separated land squares.
	_paint(gs, 0, 0, 19, 19, "ocean")
	_paint(gs, 1, 1, 3, 3, "grassland")     # mass A
	_paint(gs, 8, 8, 10, 10, "grassland")   # mass B
	_paint(gs, 15, 15, 17, 17, "grassland") # mass C
	# Cities on two of the three masses.
	make_settlement(gs, 1, 2, 2)
	make_settlement(gs, 1, 9, 9)
	var aim = {"kind": "cities_on_landmasses", "count": 3}
	assert_eq(Quests._aim_progress(aim, {}, p, gs), 2, "two cities on two distinct landmasses → progress 2")
	assert_false(Quests._aim_complete(aim, {}, p, gs), "two of three landmasses is not complete")
	make_settlement(gs, 1, 16, 16)
	assert_eq(Quests._aim_progress(aim, {}, p, gs), 3, "a city on the third mass advances to 3")
	assert_true(Quests._aim_complete(aim, {}, p, gs), "three distinct landmasses completes the aim")

func test_build_units_counts_standing_units() -> void:
	var gs = make_gs()
	var p = gs.get_player(1)
	var aim = {"kind": "build_units", "unit_types": ["chariot"], "count": 3}
	make_unit(gs, "chariot", 1, 2, 2)
	make_unit(gs, "chariot", 1, 3, 3)
	make_unit(gs, "warrior", 1, 4, 4)  # wrong type, ignored
	assert_eq(Quests._aim_progress(aim, {}, p, gs), 2, "two chariots → progress 2")
	assert_false(Quests._aim_complete(aim, {}, p, gs), "two of three is not complete")
	make_unit(gs, "chariot", 1, 5, 5)
	assert_true(Quests._aim_complete(aim, {}, p, gs), "three chariots completes the build_units aim")

func test_build_fleet_requires_every_leg() -> void:
	var gs = make_gs()
	var p = gs.get_player(1)
	var aim = {"kind": "build_fleet", "composition": {"destroyer": 2, "fighter": 1}}
	make_unit(gs, "destroyer", 1, 2, 2)
	make_unit(gs, "destroyer", 1, 3, 3)
	# Destroyers met, but no fighter yet → incomplete.
	assert_eq(Quests._aim_progress(aim, {}, p, gs), 1, "one of two fleet legs met")
	assert_false(Quests._aim_complete(aim, {}, p, gs), "fleet incomplete while a leg is short")
	make_unit(gs, "fighter", 1, 4, 4)
	assert_true(Quests._aim_complete(aim, {}, p, gs), "every fleet leg met completes the aim")

func test_conquer_resource_detects_owned_resource_tile() -> void:
	var gs = make_gs()
	var p = gs.get_player(1)
	var aim = {"kind": "conquer_resource", "resources": ["iron"]}
	assert_false(Quests._aim_complete(aim, {}, p, gs), "no iron yet → not complete")
	var t = gs.map.get_tile(5, 5)
	t.owner_player_id = 1
	t.resource_id = "iron"
	assert_true(Quests._aim_complete(aim, {}, p, gs), "owning an iron tile completes Greed")
	# A rival's iron tile does not count.
	var t2 = gs.map.get_tile(6, 6)
	t2.owner_player_id = 2
	t2.resource_id = "copper"
	var aim2 = {"kind": "conquer_resource", "resources": ["copper"]}
	assert_false(Quests._aim_complete(aim2, {}, p, gs), "a rival's resource tile does not count")

func test_spread_corp_diffs_against_arming_baseline() -> void:
	var gs = make_gs()
	var p = gs.get_player(1)
	# Found a corporation in the player's first city (records founder + stamps econ_org_id).
	var hq = make_settlement(gs, 1, 5, 5)
	EconOrgs.found("merchant_guild", hq, gs)
	# Arm spread_corp; the snapshot baselines the one existing member city.
	gs.db.quests["corporate_expansion"]["aim"] = {"kind": "spread_corp", "count": 2}
	var rec = {"snapshot": Quests._make_snapshot(gs.db.get_quest("corporate_expansion"), p, gs),
		"player_id": 1}
	assert_eq(Quests._aim_progress(gs.db.get_quest("corporate_expansion")["aim"], rec, p, gs), 0,
		"the founding city is the baseline, not new spread")
	# Spread to two more cities.
	var c2 = make_settlement(gs, 1, 7, 7)
	var c3 = make_settlement(gs, 1, 9, 9)
	EconOrgs.spread_to("merchant_guild", c2, gs)
	EconOrgs.spread_to("merchant_guild", c3, gs)
	var aim = gs.db.get_quest("corporate_expansion")["aim"]
	assert_eq(Quests._aim_progress(aim, rec, p, gs), 2, "two NEW member cities since arming → progress 2")
	assert_true(Quests._aim_complete(aim, rec, p, gs), "spreading to the target count completes the aim")

func test_own_corp_resources_completes_when_all_inputs_accessible() -> void:
	var gs = make_gs()
	var p = gs.get_player(1)
	_grant_tech(gs, 1, "masonry")       # marble/stone connection tech (+ a quarry)
	var hq = make_settlement(gs, 1, 5, 5)
	# creative_constructions needs marble + stone (both gated by masonry tech + a quarry).
	EconOrgs.found("creative_constructions", hq, gs)
	var aim = {"kind": "own_corp_resources"}
	assert_false(Quests._aim_complete(aim, {}, p, gs), "missing corp inputs → not complete")
	# Own a connected marble tile and stone tile (tech + quarry improvement).
	var tm = gs.map.get_tile(4, 4); tm.owner_player_id = 1; tm.resource_id = "marble"; tm.improvement_id = "quarry"
	assert_false(Quests._aim_complete(aim, {}, p, gs), "only one of two corp inputs → still incomplete")
	var ts = gs.map.get_tile(6, 6); ts.owner_player_id = 1; ts.resource_id = "stone"; ts.improvement_id = "quarry"
	assert_true(Quests._aim_complete(aim, {}, p, gs), "owning every corp input completes Hostile Takeover")

func test_control_named_tile_detects_settlement_on_match() -> void:
	var gs = make_gs()
	var p = gs.get_player(1)
	var t = gs.map.get_tile(5, 5); t.terrain_id = "hills"
	make_settlement(gs, 1, 5, 5)
	var aim = {"kind": "control_named_tile", "match": {"terrain": "hills"}}
	assert_true(Quests._aim_complete(aim, {}, p, gs), "a city on a matching tile completes the aim")
	var aim2 = {"kind": "control_named_tile", "match": {"terrain": "mountain"}}
	assert_false(Quests._aim_complete(aim2, {}, p, gs), "no matching tile → incomplete")

func test_conquer_holy_city_never_progresses_disabled() -> void:
	var gs = make_gs()
	var p = gs.get_player(1)
	# Crusade ships disabled (no holy-city settlement model); its aim never advances.
	var aim = {"kind": "conquer_holy_city"}
	assert_eq(Quests._aim_progress(aim, {}, p, gs), 0, "conquer_holy_city makes no progress (unmodelled)")
	assert_false(Quests._aim_complete(aim, {}, p, gs), "conquer_holy_city never completes")
	assert_false("crusade" in gs.active_quest_ids and gs.db.get_quest("crusade").get("active", 100) > 0,
		"crusade is shipped disabled (active 0)")
	assert_eq(int(gs.db.get_quest("crusade").get("active", 100)), 0, "crusade active is 0 in data")

# ── keep_trigger_city constraint ─────────────────────────────────────────────────

func test_keep_trigger_city_drops_when_capital_lost() -> void:
	var gs = make_gs()
	var p = gs.get_player(1)
	var cap = make_settlement(gs, 1, 5, 5)
	cap.structures.append("palace")
	cap.structures.append("forge")
	_grant_tech(gs, 1, "metal_casting")  # forge tech (prereq building:forge already met by structure)
	Quests.arm_quest("master_blacksmith", p, gs)
	assert_eq(gs.active_quests.size(), 1, "master_blacksmith armed with a keep_trigger_city snapshot")
	var rec = gs.active_quests[0]
	assert_eq(int(rec["snapshot"].get(Quests.TRIGGER_CITY_KEY, -1)), cap.id,
		"the trigger city baseline is the capital id at arming")
	# Still own it → no violation.
	var produced = Quests._evaluate_active(p, gs)
	assert_eq(gs.active_quests.size(), 1, "keeping the trigger city keeps the quest armed")
	# Lose the city (captured by a rival) → constraint violated → dropped.
	cap.owner_player_id = 2
	produced = Quests._evaluate_active(p, gs)
	assert_eq(gs.active_quests.size(), 0, "losing the trigger city drops the quest")
	assert_eq(str(produced[0].get("kind", "")), "quest_failed", "a failure descriptor is produced")

func test_keep_trigger_city_survives_save_load() -> void:
	var gs = make_gs()
	var p = gs.get_player(1)
	gs.active_quests.append({
		"quest_id": "master_blacksmith", "player_id": 1, "start_turn": 4, "progress": 1,
		"snapshot": {Quests.TRIGGER_CITY_KEY: 3}
	})
	var parsed = JSON.parse(JSON.print(gs.serialize())).result
	var gs2 = GameState.deserialize(parsed, gs.db)
	var snap = gs2.active_quests[0]["snapshot"]
	assert_true(snap.has(Quests.TRIGGER_CITY_KEY), "the trigger-city sentinel key survives the roundtrip")
	assert_eq(typeof(snap[Quests.TRIGGER_CITY_KEY]), TYPE_INT, "the trigger-city id survives as int")
	assert_eq(int(snap[Quests.TRIGGER_CITY_KEY]), 3, "the trigger-city id value is preserved")

# ── min_water_fraction prereq (shared event vocabulary) ──────────────────────────

func test_min_water_fraction_prereq_gates_naval_quests() -> void:
	var gs = make_gs(2, 42, 10, 10)
	var p = gs.get_player(1)
	make_settlement(gs, 1, 5, 5)
	_grant_tech(gs, 1, "compass")
	# All-grassland map → 0% water → Harbormaster (needs 40%) not eligible.
	assert_false(Quests.quest_eligible("harbormaster", p, gs),
		"a dry map fails the min_water_fraction gate")
	# Flood half the map with ocean → 50% water → eligible.
	for y in range(0, 5):
		for x in range(0, 10):
			gs.map.get_tile(x, y).terrain_id = "ocean"
	assert_true(Quests.quest_eligible("harbormaster", p, gs),
		"a ≥40%-water map satisfies the min_water_fraction gate")

# ── Quest-armed info popup (facade transient queue) ──────────────────────────────

func test_armed_quest_enqueues_info_popup_for_human() -> void:
	var gs = make_gs(2, 42)
	var f = bare_facade(gs)
	gs.pending_quest_events = [{
		"kind": "quest_armed", "player_id": 1, "quest_id": "classic_literature",
		"name": "Classic Literature", "text": "Build libraries.",
		"objective": "Build 7 libraries."
	}]
	f._drain_quest_events()
	var info = f.get_pending_quest_info(1)
	assert_false(info.empty(), "a human's armed quest enqueues an info popup")
	assert_eq(str(info.get("objective", "")), "Build 7 libraries.",
		"the info popup carries the objective")
	assert_true(info.get("reward_lines", []).size() > 0,
		"the info popup carries reward summary lines")
	f.ack_quest_info(1, "classic_literature")
	assert_true(f.get_pending_quest_info(1).empty(), "ack clears the info popup")

func test_ai_armed_quest_does_not_enqueue_info_popup() -> void:
	var gs = make_gs(2, 42)
	gs.get_player(1).is_ai = true
	var f = bare_facade(gs)
	gs.pending_quest_events = [{
		"kind": "quest_armed", "player_id": 1, "quest_id": "classic_literature",
		"name": "Classic Literature", "text": "Build libraries.",
		"objective": "Build 7 libraries."
	}]
	f._drain_quest_events()
	assert_true(f.get_pending_quest_info(1).empty(),
		"an AI's armed quest queues no info popup")
