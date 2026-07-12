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

# ── Traits & leaders reference parity (A9) ─────────────────────────────────────

# A9 data pass (audit §1.8 + §10): pin the retuned trait values and leader trait
# pairs so a regression back to the pre-parity numbers fails loudly.
func test_traits_and_leaders_carry_a9_reference_values() -> void:
	var db = _db()
	var traits: Dictionary = db.leaders_traits.get("traits", {})
	assert_eq(int(traits["imperialistic"].get("great_general_rate_bonus", 0)), 100,
		"Imperialistic GG emergence rate is +100% (reference)")
	assert_eq(db.get_constant("imperialistic_great_general_pct", 0), 100,
		"The live imperialistic GG constant matches the trait (reference 100)")
	assert_false("library" in traits["creative"].get("free_structures", []),
		"Creative's building list drops the library (reference)")
	assert_true("theatre" in traits["creative"].get("free_structures", []),
		"Creative keeps the theatre")
	assert_true("colosseum" in traits["creative"].get("free_structures", []),
		"Creative keeps the colosseum")
	assert_eq(int(traits["charismatic"].get("promotion_xp_reduction", 0)), 25,
		"Charismatic is the reference -25%-XP-needed model")
	assert_false(traits["charismatic"].has("xp_bonus"),
		"Charismatic's old xp_bonus approximation is retired")
	assert_false(traits["charismatic"].has("promotion_cost_reduction"),
		"Charismatic's old promotion_cost_reduction approximation is retired")
	var leaders: Dictionary = db.leaders_traits.get("leaders", {})
	assert_eq(leaders["hammurabi"].get("traits", []), ["aggressive", "organized"],
		"Hammurabi is aggressive+organized (reference)")
	assert_eq(leaders["brennus"].get("traits", []), ["charismatic", "spiritual"],
		"Brennus is charismatic+spiritual (reference)")
	assert_eq(leaders["gilgamesh"].get("traits", []), ["creative", "protective"],
		"Gilgamesh is creative+protective (reference)")

func test_globals_carry_a11_reference_values() -> void:
	# A11 data pass (audit §11): the reference global constants.
	var db = _db()
	assert_eq(db.get_constant("growth_threshold_base", 0), 20,
		"Growth threshold base is 20 (reference BASE_CITY_GROWTH_THRESHOLD)")
	assert_eq(db.get_constant("growth_threshold_per_pop", 0), 2,
		"Growth threshold per pop is 2 (reference CITY_GROWTH_MULTIPLIER)")
	assert_eq(db.get_constant("min_settlement_distance", 0), 2,
		"Min settlement distance is 2 (reference MIN_CITY_RANGE)")
	assert_eq(db.get_constant("healing_in_settlement", 0), 20,
		"Heal rate in a city is 20 (reference)")
	assert_eq(db.get_constant("healing_friendly_territory", 0), 15,
		"Heal rate in friendly territory is 15 (reference)")
	assert_eq(db.get_constant("healing_allied_territory", 0), 15,
		"Allied territory heals at the reference friendly rate (no allied tier)")
	assert_eq(db.get_constant("healing_neutral_territory", 0), 10,
		"Heal rate in neutral territory is 10 (reference)")
	assert_eq(db.get_constant("healing_hostile_territory", 0), 5,
		"Heal rate in enemy territory is 5 (reference; the 0 extra is dropped)")
	assert_eq(db.get_constant("experience_per_combat_cap", 0), 10,
		"XP per combat caps at 10 (reference MAX_EXPERIENCE_PER_COMBAT)")
	assert_eq(db.get_constant("experience_vs_wild_cap", 0), 10,
		"XP vs wild forces caps at 10 (reference barbarian cap)")
	assert_eq(db.get_constant("withdrawal_chance_max", 0), 90,
		"Total withdrawal chance clamps at 90 (reference)")
	assert_false(db.constants.has("max_xp_from_barbarians"),
		"Dead duplicate max_xp_from_barbarians is retired (live key: experience_vs_wild_cap)")

func test_science_rows_and_spy_verified_against_reference() -> void:
	# Economy-unblock pass (2026-07-11): the science% rows the A2 audit flagged
	# "unverified" are now read straight from the reference's research commerce
	# modifiers, and the spy specialist from its specialist table — all matched
	# the shipped values, pinned here so they stay put.
	var db = _db()
	var science := {"library": 25, "university": 25, "observatory": 25,
		"laboratory": 25, "academy": 50, "seowon": 35}
	for sid in science:
		assert_eq(int(db.get_structure(sid).get("science_bonus", 0)), int(science[sid]),
			"'%s' carries the reference research modifier" % sid)
	var spy: Dictionary = db.get_specialist("spy").get("output", {})
	assert_eq(int(spy.get("espionage", 0)), 4, "Spy yields 4 espionage (reference)")
	assert_eq(int(spy.get("science", 0)), 1, "Spy yields 1 research (reference)")

func test_techs_carry_a13_reference_eras_and_cost() -> void:
	# A13 data pass (audit §3): era moves + the future_tech cost. The AND/OR
	# prereq-graph rewiring is D1, not pinned here.
	var db = _db()
	assert_eq(str(db.get_technology("calendar").get("era", "")), "classical",
		"Calendar is classical (reference)")
	assert_eq(str(db.get_technology("iron_working").get("era", "")), "classical",
		"Iron Working is classical (reference)")
	assert_eq(str(db.get_technology("genetics").get("era", "")), "future",
		"Genetics is future (reference)")
	assert_eq(str(db.get_technology("stealth").get("era", "")), "future",
		"Stealth is future (reference)")
	assert_eq(int(db.get_technology("future_tech").get("cost", 0)), 10000,
		"Future Tech costs 10000 (reference)")

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

func test_great_person_units_have_settled_specialist_records() -> void:
	# Settling a Great Person adds the matching `great_*` specialist record
	# (GreatPeople join_city / the events SGP verb): every great_person unit's
	# generator must resolve to one, so a settle can never add an unknown type.
	var db = _db()
	for uid in db.units:
		var u: Dictionary = db.units[uid]
		if not (u is Dictionary) or str(u.get("classification", "")) != "great_person":
			continue
		var gen: String = str(u.get("generated_by", ""))
		var settled: String = "great_" + gen
		if gen == "" or gen == "combat_xp":
			settled = "great_general"
		assert_false(db.get_specialist(settled).empty(),
			"Great Person unit '%s' needs a settled specialist record '%s'" % [uid, settled])

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
	assert_eq(goodies.size(), 12, "goodies.json defines the full 12-record catalogue (§24)")
	for g in goodies:
		assert_true(str(g.get("id", "")) != "", "every goody needs an id")
		assert_true(int(g.get("weight", -1)) >= 0,
			"goody '%s' needs a non-negative weight (0 = difficulty-enabled only)" % g.get("id", ""))

func test_goody_unit_types_resolve() -> void:
	var db = _db()
	for g in db.get_goodies():
		var ut = g.get("unit_type", "")
		if ut != null and ut != "":
			assert_true(db.units.has(str(ut)),
				"goody '%s' unit_type '%s' must be a real unit" % [g.get("id", ""), ut])
		var su = g.get("spawn_unit", "")
		if su != null and su != "":
			assert_true(db.units.has(str(su)),
				"goody '%s' spawn_unit '%s' must be a real unit" % [g.get("id", ""), su])

func test_structures_carry_no_gold_upkeep() -> void:
	# Reference parity (audit §1.6, retuned with C1 2026-07-12): buildings pay no
	# per-building gold upkeep — the economy's drag is city maintenance + civic
	# upkeep + inflation. The read path (`_settlement_upkeep`) stays for mods, so
	# the shipped table simply must not carry the field.
	var db = _db()
	for sid in db.structures:
		assert_eq(int(db.structures[sid].get("upkeep", 0)), 0,
			"structure '%s' pays no gold upkeep" % sid)

func test_paces_and_difficulties_carry_inflation_columns() -> void:
	# §15.1 inflation reads a per-pace percent/offset (§29.5) and a per-difficulty
	# handicap percent (§29.10); every row must carry them explicitly.
	var db = _db()
	for pace_id in db.paces:
		assert_true(db.paces[pace_id].has("inflation_percent"),
			"pace '%s' has inflation_percent" % pace_id)
		assert_true(db.paces[pace_id].has("inflation_offset"),
			"pace '%s' has inflation_offset" % pace_id)
		assert_true(int(db.paces[pace_id]["inflation_offset"]) <= 0,
			"pace '%s' offset delays onset (≤ 0)" % pace_id)
	for diff_id in db.difficulties:
		assert_true(db.difficulties[diff_id].has("inflation_percent"),
			"difficulty '%s' has inflation_percent" % diff_id)

func test_paces_carry_hurry_scale_column() -> void:
	# §15.2 population rush scales hammers-per-pop by the pace's hurry percent
	# (§29.8); every pace row must carry the column explicitly.
	var db = _db()
	for pace_id in db.paces:
		assert_true(int(db.paces[pace_id].get("hurry_scale", 0)) > 0,
			"pace '%s' has a positive hurry_scale" % pace_id)

func test_paces_carry_c3_scaling_columns() -> void:
	# §15.3 pace scaling (C3): every pace carries its own anarchy / golden-age /
	# victory-delay / wild columns, pinned to the reference §29.5 table — note wild
	# is its own curve (marathon 400), NOT a reuse of build_scale (marathon 300).
	var expected := {
		"quick":    {"anarchy_scale": 67,  "golden_age_scale": 80,
			"victory_delay_scale": 67,  "wild_scale": 67},
		"normal":   {"anarchy_scale": 100, "golden_age_scale": 100,
			"victory_delay_scale": 100, "wild_scale": 100},
		"epic":     {"anarchy_scale": 150, "golden_age_scale": 125,
			"victory_delay_scale": 150, "wild_scale": 150},
		"marathon": {"anarchy_scale": 200, "golden_age_scale": 200,
			"victory_delay_scale": 300, "wild_scale": 400},
	}
	var db = _db()
	for pace_id in expected:
		assert_true(db.paces.has(pace_id), "pace '%s' exists" % pace_id)
		for col in expected[pace_id]:
			assert_eq(int(db.paces[pace_id].get(col, 0)), int(expected[pace_id][col]),
				"pace '%s' %s matches the reference" % [pace_id, col])

func test_goody_weight_overrides_are_full_normalised_tables() -> void:
	# §24: every difficulty carries a full goody_weights column — one entry per
	# goody id, summing to 100 — so the per-difficulty reward mix is explicit.
	var db = _db()
	var goody_ids = {}
	for g in db.get_goodies():
		goody_ids[str(g.get("id", ""))] = true
	for diff_id in db.difficulties:
		var gw = db.difficulties[diff_id].get("goody_weights", {})
		assert_eq(gw.size(), goody_ids.size(),
			"difficulty '%s' overrides every goody id" % diff_id)
		var total = 0
		for k in gw:
			assert_true(goody_ids.has(str(k)),
				"difficulty '%s' goody_weights key '%s' is a real goody" % [diff_id, k])
			total += int(gw[k])
		assert_eq(total, 100, "difficulty '%s' goody_weights sum to 100" % diff_id)

func test_first_strike_fields_are_non_negative_ints() -> void:
	# §15.5: first_strikes / chance_first_strikes on units and the promotion
	# bonus forms must be non-negative integers wherever present — a negative
	# or fractional value would corrupt the integer combat loop.
	var db = _db()
	for uid in db.units:
		var u = db.units[uid]
		for key in ["first_strikes", "chance_first_strikes"]:
			if u.has(key):
				assert_true(int(u[key]) >= 0 and int(u[key]) == u[key],
					"unit '%s' %s is a non-negative int" % [uid, key])
	for pid in db.promotions:
		var p = db.promotions[pid]
		for key in ["first_strikes_bonus", "chance_first_strikes_bonus"]:
			if p.has(key):
				assert_true(int(p[key]) >= 0 and int(p[key]) == p[key],
					"promotion '%s' %s is a non-negative int" % [pid, key])

func test_belief_refs_resolve() -> void:
	# Every structure a belief references (temple/monastery/cathedral tiers and its
	# holy_site_structure) must exist in structures.json, and a non-null
	# founding_tech must be a real tech. Guards the dangling-holy-site class of bug
	# (sun_faith → temple_of_sun shipped without the structure).
	var db = _db()
	for bid in db.beliefs:
		if bid == "_comment":
			continue
		var belief = db.beliefs[bid]
		for key in ["temple", "monastery", "cathedral", "holy_site_structure"]:
			var sid = belief.get(key, null)
			if sid != null and sid != "":
				assert_true(db.structures.has(str(sid)),
					"belief '%s' %s '%s' must be a real structure" % [bid, key, sid])
		var tech = belief.get("founding_tech", null)
		if tech != null and tech != "":
			assert_true(db.technologies.has(str(tech)),
				"belief '%s' founding_tech '%s' must be a real tech" % [bid, tech])

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
	var known := ["steal_tech", "sabotage", "destroy_building", "destroy_project",
		"destroy_improvement", "steal_gold", "poison_water", "insert_culture",
		"incite_unhappiness", "incite_revolt", "switch_civic", "switch_religion",
		"counterespionage"]
	var known_passive := ["see_demographics", "investigate_city", "see_research",
		"city_visibility", "detect_missions"]
	for m in missions:
		assert_true(str(m.get("id", "")) != "", "every espionage mission needs an id")
		if str(m.get("kind", "active")) == "passive":
			# Passive records (§25.6) are reveal thresholds, not runnable missions.
			assert_true(int(m.get("threshold_multiplier", 0)) > 0,
				"passive mission '%s' needs a positive threshold_multiplier" % m.get("id", ""))
			assert_true(str(m.get("scope", "")) in ["alliance", "city"],
				"passive mission '%s' needs scope alliance/city" % m.get("id", ""))
			assert_true(str(m.get("effect", "")) in known_passive,
				"mission '%s' effect '%s' must be a known passive verb" % [m.get("id", ""), m.get("effect", "")])
			continue
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

# ── Compound unit prerequisites (§15.12) ─────────────────────────────────────────

func test_unit_tech_list_form_validates_clean() -> void:
	# A list-form tech_required of real techs must not raise validation errors —
	# the shipped knight carries the compound ["guilds", "horseback_riding"] set.
	var db = _db()
	var knight_req = db.get_unit("knight").get("tech_required", null)
	assert_true(knight_req is Array, "knight ships a list-form tech_required")
	assert_true("guilds" in knight_req and "horseback_riding" in knight_req,
		"knight requires Guilds + Horseback Riding")
	assert_true(db.get_errors().empty(), "list-form tech prereqs validate cleanly")

func test_unit_tech_list_bad_id_fails_validation() -> void:
	var db = _db()
	db.units["bogus_unit"] = {"id": "bogus_unit",
		"tech_required": ["guilds", "no_such_tech"], "resource_required": null}
	db._validate_unit_tech_refs()
	var found := false
	for err in db.get_errors():
		if "bogus_unit" in err and "no_such_tech" in err:
			found = true
	assert_true(found, "an unknown tech inside a list-form tech_required is reported")

func test_unit_tech_wrong_type_fails_validation() -> void:
	var db = _db()
	db.units["bogus_unit"] = {"id": "bogus_unit", "tech_required": 7}
	db._validate_unit_tech_refs()
	var found := false
	for err in db.get_errors():
		if "bogus_unit" in err and "tech_required" in err:
			found = true
	assert_true(found, "a non-null/String/Array tech_required is reported")

func test_unit_resource_forms_validate_clean() -> void:
	# The shipped data uses all three resource forms: single (swordsman "iron"),
	# all-set (knight horse+iron) and any-set (maceman copper-or-iron).
	var db = _db()
	var knight_res = db.get_unit("knight").get("resource_required", null)
	assert_true(knight_res is Dictionary and knight_res.get("all", []).size() == 2,
		"knight ships an all-form resource_required (horse + iron)")
	var mace_res = db.get_unit("maceman").get("resource_required", null)
	assert_true(mace_res is Dictionary and mace_res.get("any", []).size() == 2,
		"maceman ships an any-form resource_required (copper or iron)")
	assert_true(db.get_errors().empty(), "compound resource prereqs validate cleanly")

func test_unit_resource_bad_id_fails_validation() -> void:
	var db = _db()
	db.units["bogus_unit"] = {"id": "bogus_unit",
		"resource_required": {"all": ["iron"], "any": ["unobtainium"]}}
	db._validate_unit_resource_refs()
	var found := false
	for err in db.get_errors():
		if "bogus_unit" in err and "unobtainium" in err:
			found = true
	assert_true(found, "an unknown resource id in either list is reported")

func test_unit_resource_single_bad_id_fails_validation() -> void:
	var db = _db()
	db.units["bogus_unit"] = {"id": "bogus_unit", "resource_required": "unobtainium"}
	db._validate_unit_resource_refs()
	var found := false
	for err in db.get_errors():
		if "bogus_unit" in err and "unobtainium" in err:
			found = true
	assert_true(found, "an unknown single-form resource id is reported")

func test_unit_resource_unknown_key_fails_validation() -> void:
	var db = _db()
	db.units["bogus_unit"] = {"id": "bogus_unit",
		"resource_required": {"anyy": ["iron"]}}
	db._validate_unit_resource_refs()
	var found := false
	for err in db.get_errors():
		if "bogus_unit" in err and "anyy" in err:
			found = true
	assert_true(found, "a typoed all/any key cannot silently drop a resource gate")
