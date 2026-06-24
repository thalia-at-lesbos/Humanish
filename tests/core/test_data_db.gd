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

# DataDB loading mechanics and content integrity. Everything the engine reads at
# runtime — tables, cross-references, the tech tree shape, civics, starting
# units — must be present and internally consistent before any rule runs.

func _db():
	var db = load("res://src/core/data_db.gd").new()
	db.load_all()
	return db

# ── Loading & getters ──────────────────────────────────────────────────────────

func test_loads_without_errors() -> void:
	var db = _db()
	if not db.get_errors().empty():
		for err in db.get_errors():
			gut.p("DataDB error: " + err)
	assert_true(db.get_errors().empty(),
		"DataDB.load_all() must succeed with no cross-reference errors")

func test_terrains_present() -> void:
	var db = _db()
	assert_true(db.terrains.has("grassland"), "grassland terrain must exist")
	assert_true(db.terrains.has("ocean"), "ocean terrain must exist")

func test_get_constant_default() -> void:
	var db = _db()
	assert_eq(db.get_constant("nonexistent_key", 42), 42,
		"Missing key returns default value")

func test_get_constant_loaded() -> void:
	var db = _db()
	assert_gt(db.get_constant("combat_scale", 0), 0,
		"combat_scale must be a positive integer")

# ── Tech tree shape ──────────────────────────────────────────────────────────

func test_tech_tree_ages_present() -> void:
	var db = _db()
	for tid in ["agriculture", "pottery", "writing", "alphabet"]:
		assert_false(db.get_technology(tid).empty(), "Tech '%s' must exist" % tid)

func test_tech_tree_is_linear_progression() -> void:
	var db = _db()
	assert_eq(db.get_technology("pottery").get("prereqs_all"), ["agriculture"],
		"pottery requires agriculture")
	assert_eq(db.get_technology("writing").get("prereqs_all"), ["pottery"],
		"writing requires pottery")
	assert_eq(db.get_technology("alphabet").get("prereqs_all"), ["writing"],
		"alphabet requires writing")

# ── Civics ───────────────────────────────────────────────────────────────────

func test_policy_categories_are_the_five_design_categories() -> void:
	var db = _db()
	assert_eq(db.policies.get("categories", []),
		["government", "legal", "labor", "economic", "religion"],
		"policies.json defines exactly the five §8 design categories")

func test_sample_civics_present_in_expected_categories() -> void:
	var db = _db()
	var pols = db.policies.get("policies", {})
	var expected = {
		"hereditary_rule": "government", "free_speech": "legal",
		"caste_system": "labor", "free_market": "economic", "theocracy": "religion",
	}
	for cid in expected:
		assert_true(pols.has(cid), "Civic '%s' must exist" % cid)
		assert_eq(str(pols[cid].get("category", "")), expected[cid],
			"Civic '%s' is in the '%s' category" % [cid, expected[cid]])

# ── Units & societies ──────────────────────────────────────────────────────────

func test_scout_unit_exists() -> void:
	var db = _db()
	assert_false(db.get_unit("scout").empty(), "A 'scout' unit type must exist")

func test_every_society_starts_with_settler_plus_tech_escort() -> void:
	# Every society opens with exactly a settler plus one escort unit, derived
	# from its starting techs: a scout when Hunting is known, else a warrior.
	var db = _db()
	for sid in db.get_societies():
		var techs = db.get_society(sid).get("starting_techs", [])
		var su = db.starting_units_for_techs(techs)
		var escort = "scout" if "hunting" in techs else "warrior"
		assert_eq(su, ["settler", escort],
			"Society '%s' (techs %s) should start with [settler, %s]" % [sid, techs, escort])

func test_starting_units_default_to_warrior_without_hunting() -> void:
	var db = _db()
	assert_eq(db.starting_units_for_techs(["agriculture", "mining"]),
		["settler", "warrior"], "No Hunting → settler + warrior")
	assert_eq(db.starting_units_for_techs(["fishing", "hunting"]),
		["settler", "scout"], "Hunting → settler + scout")

# Every society must carry a city_names list of exactly 20 distinct non-empty
# names, capital first (index 0), so founded cities can draw historical names.
func test_every_society_has_twenty_city_names() -> void:
	var db = _db()
	for sid in db.get_societies():
		var names = db.get_city_names(sid)
		assert_true(names is Array, "Society '%s' must have a city_names array" % sid)
		assert_eq(names.size(), 20,
			"Society '%s' must list exactly 20 city names" % sid)
		assert_true(str(names[0]).strip_edges() != "",
			"Society '%s' capital (index 0) must be non-empty" % sid)
		var seen := {}
		for n in names:
			assert_true(str(n).strip_edges() != "",
				"Society '%s' has an empty city name" % sid)
			assert_false(seen.has(n),
				"Society '%s' has a duplicate city name '%s'" % [sid, str(n)])
			seen[n] = true

# society_id_for_leader reverse-maps each society's unique leader to its id.
func test_society_id_for_leader_reverse_lookup() -> void:
	var db = _db()
	var socs = db.get_societies()
	for sid in socs:
		var lid = str(socs[sid].get("leader_id", ""))
		if lid == "":
			continue
		assert_eq(db.society_id_for_leader(lid), sid,
			"leader '%s' should map back to society '%s'" % [lid, sid])
	assert_eq(db.society_id_for_leader("nonexistent_leader_xyz"), "",
		"Unknown leader maps to empty society id")

# ── Trait AI focus (§C1) ───────────────────────────────────────────────────────

# Every trait must carry an `ai_focus` block over the four strategic axes, all
# integers, so PlayerAI._focus_profile can sum a leader's direction without a
# missing-key guard. (Phase C — trait-driven strategic focus.)
func test_every_trait_has_ai_focus() -> void:
	var db = _db()
	var traits: Dictionary = db.leaders_traits.get("traits", {})
	assert_false(traits.empty(), "Traits table must be present")
	var axes := ["expand", "military", "economy", "science"]
	for tid in traits:
		var focus = traits[tid].get("ai_focus", null)
		assert_true(focus is Dictionary, "Trait '%s' must declare an ai_focus dict" % tid)
		for axis in axes:
			assert_true(focus.has(axis), "Trait '%s' ai_focus needs a '%s' axis" % [tid, axis])
			assert_true(typeof(focus[axis]) == TYPE_REAL or typeof(focus[axis]) == TYPE_INT,
				"Trait '%s' ai_focus.%s must be numeric" % [tid, axis])

# ── Specialists table (§6.5 / §14.5) ────────────────────────────────────────────

func test_specialists_table_has_fourteen_types() -> void:
	var db = _db()
	var working := ["citizen", "priest", "artist", "scientist", "merchant", "engineer", "spy"]
	var great := ["great_priest", "great_artist", "great_scientist", "great_merchant",
		"great_engineer", "great_general", "great_spy"]
	for sid in working + great:
		assert_false(db.get_specialist(sid).empty(),
			"Specialist '%s' must exist in the table" % sid)

func test_specialist_records_are_well_formed() -> void:
	var db = _db()
	for sid in db.get_specialists():
		if sid == "_comment":
			continue
		var rec: Dictionary = db.get_specialist(sid)
		assert_true(rec.has("output") and rec["output"] is Dictionary,
			"Specialist '%s' needs an output dict" % sid)
		assert_true(rec.has("gp_points"), "Specialist '%s' needs gp_points" % sid)
		assert_true(rec.has("default_slots"), "Specialist '%s' needs default_slots" % sid)
		# Output channels must be known yield channels.
		for ch in rec["output"]:
			assert_true(ch in Specialists.CHANNELS,
				"Specialist '%s' output channel '%s' is not a known channel" % [sid, ch])

func test_specialist_great_person_units_resolve() -> void:
	var db = _db()
	for sid in db.get_specialists():
		if sid == "_comment":
			continue
		var gp_unit = db.get_specialist(sid).get("great_person_unit", "")
		if gp_unit != "":
			assert_true(db.units.has(gp_unit),
				"Specialist '%s' great_person_unit '%s' must be a real unit" % [sid, gp_unit])

func test_structure_specialist_slots_name_known_types() -> void:
	var db = _db()
	for struct_id in db.structures:
		var slots: Dictionary = db.structures[struct_id].get("specialist_slots", {})
		for stype in slots:
			assert_false(db.get_specialist(stype).empty(),
				"Structure '%s' specialist slot '%s' must be a known specialist" % [struct_id, stype])

# ── Goody-hut table (§9) ─────────────────────────────────────────────────────────

func test_goodies_table_loads_and_is_well_formed() -> void:
	var db = _db()
	var goodies = db.get_goodies()
	assert_true(goodies.size() > 0, "goodies.json must define some rewards")
	for g in goodies:
		assert_true(str(g.get("id", "")) != "", "every goody needs an id")
		assert_true(int(g.get("weight", 0)) > 0, "goody '%s' needs a positive weight" % g.get("id", ""))

func test_goody_unit_types_resolve() -> void:
	var db = _db()
	for g in db.get_goodies():
		var ut = g.get("unit_type", "")
		if ut != null and ut != "":
			assert_true(db.units.has(str(ut)),
				"goody '%s' unit_type '%s' must be a real unit" % [g.get("id", ""), ut])

# ── Random-event lifecycle tables (§9) ───────────────────────────────────────────

func test_event_tables_load_and_are_well_formed() -> void:
	var db = _db()
	assert_true(db.get_events().size() > 1, "events.json defines a catalogue")
	assert_true(db.get_errors().empty(), "DataDB loads cleanly with the reworked event table")

func test_events_carry_inline_selection_fields() -> void:
	# The reworked schema folds the trigger predicates into each event: every real
	# event carries an `active` inclusion percent and a selection `weight`.
	var db = _db()
	for eid in db.get_events():
		if eid == "_comment":
			continue
		var ev = db.get_events()[eid]
		assert_true(ev.has("active"), "event '%s' declares an active inclusion percent" % eid)
		assert_true(ev.has("weight"), "event '%s' declares a selection weight" % eid)

func test_event_effect_refs_resolve() -> void:
	# Every unit/structure/promotion/resource referenced by an event effect (begin,
	# choice, expire, or nested chance.then) must exist. The loader enforces this;
	# assert directly so a bad ref is caught here too.
	var db = _db()
	for eid in db.get_events():
		if eid == "_comment":
			continue
		var ev = db.get_events()[eid]
		var lists = [ev.get("effects", []), ev.get("expire_effects", [])]
		for ch in ev.get("choices", []):
			lists.append(ch.get("effects", []))
		for effects in lists:
			_assert_event_effects_resolve(db, eid, effects)

func _assert_event_effects_resolve(db, eid, effects) -> void:
	for eff in effects:
		match str(eff.get("verb", "")):
			"unit", "spawn_wild":
				assert_true(db.units.has(str(eff.get("unit_type", ""))),
					"event '%s' unit effect must name a real unit" % eid)
			"building":
				assert_true(db.structures.has(str(eff.get("structure_id", ""))),
					"event '%s' building effect must name a real structure" % eid)
			"grant_promotion":
				assert_true(db.promotions.has(str(eff.get("promotion", ""))),
					"event '%s' grant_promotion must name a real promotion" % eid)
			"place_resource":
				assert_true(db.resources.has(str(eff.get("resource", ""))),
					"event '%s' place_resource must name a real resource" % eid)
			"chance":
				_assert_event_effects_resolve(db, eid, eff.get("then", []))

# ── Corporations (§14.6) ─────────────────────────────────────────────────────

func test_corporations_table_is_well_formed() -> void:
	var db = _db()
	assert_false(db.econ_orgs.empty(), "corporations table must load")
	for org_id in db.econ_orgs:
		var org = db.econ_orgs[org_id]
		assert_false(org.get("input_resources", []).empty(),
			"corporation '%s' must list input resources" % org_id)
		assert_true(org.has("hq_structure"), "corporation '%s' must name an HQ structure" % org_id)
		assert_true(org.has("maintenance"), "corporation '%s' must set per-city maintenance" % org_id)
		assert_true(org.has("hq_gold_per_input"), "corporation '%s' must set HQ gold rate" % org_id)

func test_corporation_refs_resolve() -> void:
	# The loader cross-checks HQ structure / executive unit / input resources; assert
	# directly so a bad ref is caught here too.
	var db = _db()
	for org_id in db.econ_orgs:
		var org = db.econ_orgs[org_id]
		var hq = str(org.get("hq_structure", ""))
		assert_true(db.structures.has(hq), "corporation '%s' HQ structure must exist" % org_id)
		assert_true(bool(db.structures[hq].get("corporation_hq", false)),
			"corporation HQ '%s' must carry the corporation_hq flag" % hq)
		assert_true(db.units.has(str(org.get("executive_unit", ""))),
			"corporation '%s' executive unit must exist" % org_id)
		for res_id in org.get("input_resources", []):
			assert_true(db.resources.has(res_id),
				"corporation '%s' input resource '%s' must exist" % [org_id, res_id])

# ── Espionage missions (§7.1) ──────────────────────────────────────────────────

func test_espionage_missions_table_is_well_formed() -> void:
	var db = _db()
	var missions = db.get_espionage_missions()
	assert_true(missions.size() > 0, "espionage_missions.json must define some missions")
	var known := ["steal_tech", "sabotage", "incite_unrest", "steal_gold", "poison_water"]
	for m in missions:
		assert_true(str(m.get("id", "")) != "", "every espionage mission needs an id")
		assert_true(int(m.get("cost_multiplier", 0)) > 0,
			"mission '%s' needs a positive cost_multiplier" % m.get("id", ""))
		assert_true(str(m.get("effect", "")) in known,
			"mission '%s' effect '%s' must be a known verb" % [m.get("id", ""), m.get("effect", "")])

func test_get_espionage_mission_returns_record_and_empty() -> void:
	var db = _db()
	assert_eq(str(db.get_espionage_mission("steal_tech").get("id", "")), "steal_tech",
		"get_espionage_mission resolves a known id")
	assert_true(db.get_espionage_mission("no_such_mission").empty(),
		"get_espionage_mission returns {} for an unknown id")

func test_diplomacy_table_is_well_formed() -> void:
	var db = _db()
	var dip = db.get_diplomacy()
	assert_eq(dip.get("attitude_levels", []).size(), 5,
		"diplomacy defines the five attitude levels")
	assert_eq(dip.get("attitude_thresholds", []).size(), 4,
		"one fewer threshold than levels")
	# Thresholds ascend.
	var th = dip.get("attitude_thresholds", [])
	for i in range(1, th.size()):
		assert_true(int(th[i]) > int(th[i - 1]), "attitude_thresholds must ascend")
	# Every memory kind carries a value and a positive decay.
	var kinds = dip.get("memory_kinds", {})
	assert_true(kinds.size() > 0, "diplomacy defines memory kinds")
	for k in kinds:
		assert_true(kinds[k].has("value"), "memory kind '%s' has a value" % k)
		assert_true(int(kinds[k].get("decay", 0)) > 0, "memory kind '%s' decays" % k)
