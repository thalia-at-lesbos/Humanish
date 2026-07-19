# Humanish — a turn-based 4X strategy game.
# Copyright (C) 2026 thalia-at-lesbos
# SPDX-License-Identifier: GPL-3.0-or-later
#
# This program is free software: you can redistribute it and/or modify it
# under the terms of the GNU General Public License as published by the Free
# Software Foundation, either version 3 of the License, or (at your option)
# any later version. See the LICENSE file for the full text and warranty
# disclaimer.

class_name DataDB
extends Reference

# Loads and validates all JSON data tables from res://data/.
# All rule code reads from here; no magic numbers in sim/.

var constants: Dictionary = {}
var terrains: Dictionary = {}
var features: Dictionary = {}
var resources: Dictionary = {}
var improvements: Dictionary = {}
var transport: Dictionary = {}
var units: Dictionary = {}
var structures: Dictionary = {}
var technologies: Dictionary = {}
var policies: Dictionary = {}
var promotions: Dictionary = {}
var beliefs: Dictionary = {}
var econ_orgs: Dictionary = {}
var specialists: Dictionary = {}
var ages: Dictionary = {}
var paces: Dictionary = {}
var difficulties: Dictionary = {}
var world_sizes: Dictionary = {}
var map_types: Dictionary = {}
var leaders_traits: Dictionary = {}
var projects: Dictionary = {}
var win_conditions: Dictionary = {}
var events: Dictionary = {}
# Multi-turn quest catalogue (§4); read by the Quests module.
var quests: Dictionary = {}
# Goody-hut / discovery-site reward table (§9).
var goodies: Dictionary = {}
# Diplomatic-assembly elections & resolutions (§18, provisional).
var resolutions: Dictionary = {}
# Espionage mission catalogue spent against rival alliances (§7.1, provisional).
var espionage_missions: Dictionary = {}
# AI diplomatic attitude factors & memory kinds (§7, Phase 7).
var diplomacy: Dictionary = {}

var _errors: Array = []

func load_all() -> bool:
	_errors = []
	constants    = _load_json("res://data/constants.json")
	terrains     = _load_json("res://data/terrains.json")
	features     = _load_json("res://data/features.json")
	resources    = _load_json("res://data/resources.json")
	improvements = _load_json("res://data/improvements.json")
	transport    = _load_json("res://data/transport.json")
	units        = _load_json("res://data/units.json")
	structures   = _load_json("res://data/structures.json")
	technologies = _load_json("res://data/technologies.json")
	policies     = _load_json("res://data/policies.json")
	promotions   = _load_json("res://data/promotions.json")
	beliefs      = _load_json("res://data/beliefs.json")
	econ_orgs    = _load_json("res://data/econ_orgs.json")
	specialists  = _load_json("res://data/specialists.json")
	ages         = _load_json("res://data/ages.json")
	paces        = _load_json("res://data/paces.json")
	difficulties = _load_json("res://data/difficulties.json")
	world_sizes  = _load_json("res://data/world_sizes.json")
	map_types    = _load_json("res://data/map_types.json")
	leaders_traits = _load_json("res://data/leaders_traits.json")
	projects     = _load_json("res://data/projects.json")
	win_conditions = _load_json("res://data/win_conditions.json")
	events       = _load_json("res://data/events.json")
	quests       = _load_json("res://data/quests.json")
	goodies      = _load_json("res://data/goodies.json")
	resolutions  = _load_json("res://data/resolutions.json")
	espionage_missions = _load_json("res://data/espionage_missions.json")
	diplomacy    = _load_json("res://data/diplomacy.json")
	_validate()
	return _errors.empty()

func get_errors() -> Array:
	return _errors

func get_constant(key: String, default_val: int = 0) -> int:
	return int(constants.get(key, default_val))

# String-valued constant (e.g. ocean_travel_tech). get_constant coerces to int, so
# non-numeric constants need their own typed accessor.
func get_constant_str(key: String, default_val: String = "") -> String:
	return str(constants.get(key, default_val))

func get_terrain(id: String) -> Dictionary:
	return terrains.get(id, {})

func get_feature(id: String) -> Dictionary:
	return features.get(id, {})

func get_resource(id: String) -> Dictionary:
	return resources.get(id, {})

func get_improvement(id: String) -> Dictionary:
	return improvements.get(id, {})

func get_unit(id: String) -> Dictionary:
	return units.get(id, {})

func get_structure(id: String) -> Dictionary:
	return structures.get(id, {})

func get_specialist(id: String) -> Dictionary:
	return specialists.get(id, {})

# All specialist records (includes the leading "_comment" documentation key —
# callers iterating types must skip it).
func get_specialists() -> Dictionary:
	return specialists

# The weighted goody-hut reward list (data/goodies.json "goodies" array). Empty
# when the table failed to load.
func get_goodies() -> Array:
	return goodies.get("goodies", [])

# A single random-event definition (data/events.json); empty for unknown ids.
func get_event(id: String) -> Dictionary:
	return events.get(id, {})

# All event definitions (callers iterating must skip the leading "_comment" key).
func get_events() -> Dictionary:
	return events

# A single multi-turn quest definition (data/quests.json); empty for unknown ids.
func get_quest(id: String) -> Dictionary:
	return quests.get(id, {})

# All quest definitions (callers iterating must skip the leading "_comment" key).
func get_quests() -> Dictionary:
	return quests

func get_resolution(id: String) -> Dictionary:
	# Skip the leading "_comment" documentation key (not a resolution).
	return resolutions.get(id, {})

# A single espionage-mission record (data/espionage_missions.json); empty for
# unknown ids.
func get_espionage_mission(id: String) -> Dictionary:
	for m in get_espionage_missions():
		if str(m.get("id", "")) == id:
			return m
	return {}

# The espionage-mission catalogue (data/espionage_missions.json "missions" array).
# Empty when the table failed to load.
func get_espionage_missions() -> Array:
	return espionage_missions.get("missions", [])

# AI diplomatic attitude/memory tuning (data/diplomacy.json, §7). Empty when the
# table failed to load.
func get_diplomacy() -> Dictionary:
	return diplomacy

func get_technology(id: String) -> Dictionary:
	return technologies.get(id, {})

func get_pace(id: String) -> Dictionary:
	return paces.get(id, paces.get("normal", {}))

func get_difficulty(id: String) -> Dictionary:
	return difficulties.get(id, difficulties.get("prince", {}))

func get_world_size(id: String) -> Dictionary:
	return world_sizes.get(id, world_sizes.get("standard", {}))

func get_map_types() -> Dictionary:
	return map_types

func get_map_type(id: String) -> Dictionary:
	return map_types.get(id, map_types.get("continents", {}))

func get_promotion(id: String) -> Dictionary:
	return promotions.get(id, {})

func get_trait(id: String) -> Dictionary:
	return leaders_traits.get("traits", {}).get(id, {})

func get_societies() -> Dictionary:
	return leaders_traits.get("societies", {})

func get_society(id: String) -> Dictionary:
	return get_societies().get(id, {})

# Historical city names for a society (data/leaders_traits.json "city_names" array,
# capital first). Returns [] when the society is unknown or has no list.
func get_city_names(society_id: String) -> Array:
	return get_society(society_id).get("city_names", [])

# Reverse-lookup the society id whose default leader matches `leader_id` (each
# society has a unique leader_id). Returns "" when no society claims that leader.
# Used to recover a player's society when only the leader_id is known.
func society_id_for_leader(leader_id: String) -> String:
	if leader_id == "":
		return ""
	var socs: Dictionary = get_societies()
	for sid in socs:
		if str(socs[sid].get("leader_id", "")) == leader_id:
			return sid
	return ""

func get_leaders() -> Dictionary:
	return leaders_traits.get("leaders", {})

func get_leader(id: String) -> Dictionary:
	return get_leaders().get(id, {})

# The leader ids belonging to a society — every leader whose `faction` matches the
# society id (e.g. society "greek" → ["alexander", "pericles"]). The society's own
# `leader_id` is always among them. Returned in the leaders table's declared order.
func get_society_leaders(society_id: String) -> Array:
	var result: Array = []
	var leaders: Dictionary = get_leaders()
	for lid in leaders.keys():
		if str(leaders[lid].get("faction", "")) == society_id:
			result.append(lid)
	return result

# Derive a player's opening units from their starting techs (game-data.md §3):
# always a settler, plus a single escort unit — a scout when a starting tech
# grants one (Hunting → Scout), otherwise the default warrior. The rule lives in
# data/constants.json so adding e.g. another tech→escort mapping needs no code.
func starting_units_for_techs(techs: Array) -> Array:
	var units: Array = constants.get("starting_units_base", ["settler"]).duplicate()
	var by_tech: Dictionary = constants.get("starting_unit_by_tech", {})
	var escort: String = str(constants.get("starting_unit_default", "warrior"))
	for tech_id in techs:
		if by_tech.has(tech_id):
			escort = str(by_tech[tech_id])
			break
	units.append(escort)
	return units

# ── internals ─────────────────────────────────────────────────────────────────

func _load_json(path: String) -> Dictionary:
	var f := File.new()
	if f.open(path, File.READ) != OK:
		_errors.append("Cannot open: " + path)
		return {}
	var text := f.get_as_text()
	f.close()
	var result := JSON.parse(text)
	if result.error != OK:
		_errors.append("JSON parse error in %s at line %d: %s" % [
			path, result.error_line, result.error_string])
		return {}
	if not result.result is Dictionary:
		_errors.append("Expected Dictionary at root of: " + path)
		return {}
	return result.result

func _validate() -> void:
	_validate_tech_prereqs()
	_validate_unit_tech_refs()
	_validate_unit_resource_refs()
	_validate_improvement_tech_refs()
	_validate_specialist_refs()
	_validate_goody_refs()
	_validate_event_refs()
	_validate_quest_refs()
	_validate_econ_org_refs()
	_validate_espionage_mission_refs()
	_validate_diplomacy_refs()
	_validate_belief_refs()
	_validate_trait_refs()
	_validate_structure_obsolete_refs()
	_validate_structure_not_buildable()

# A structure's `obsoleted_by` (§15.17) must name a real technology — a dangling
# id would ship a structure that silently never obsoletes (or, worse, a typo'd
# roster entry that keeps a wonder's effects alive forever).
func _validate_structure_obsolete_refs() -> void:
	for sid in structures:
		if sid == "_comment":
			continue
		var obs = structures[sid].get("obsoleted_by", null)
		if obs == null:
			continue
		if not (obs is String) or obs == "" or not technologies.has(str(obs)):
			_errors.append("Structure '%s' obsoleted_by '%s' not in technologies table" % [sid, obs])

# A `not_buildable` structure (M7: the Military Academy) is barred from every
# city production queue, so it must be a boolean and the structure must remain
# reachable some other way — a Great Person `build_<sid>` action (the generic
# §14 verb) or an event/quest `building` reward. Otherwise the entry would be
# silently unobtainable.
func _validate_structure_not_buildable() -> void:
	for sid in structures:
		if sid == "_comment":
			continue
		if not structures[sid].has("not_buildable"):
			continue
		var flag = structures[sid]["not_buildable"]
		if not (flag is bool):
			_errors.append("Structure '%s' not_buildable must be a boolean" % sid)
			continue
		if not flag:
			continue
		if not _has_grant_path(str(sid)):
			_errors.append("Structure '%s' is not_buildable but nothing grants it" % sid)

# True if some non-queue path can grant the structure: a great-person
# `build_<sid>` action, or a `building` effect in an event or quest reward.
func _has_grant_path(sid: String) -> bool:
	for uid in units:
		if uid == "_comment":
			continue
		if ("build_" + sid) in units[uid].get("actions", []):
			return true
	for eid in events:
		if eid == "_comment":
			continue
		var ev: Dictionary = events[eid]
		var pools: Array = [ev.get("effects", []), ev.get("expire_effects", [])]
		for ch in ev.get("choices", []):
			pools.append(ch.get("effects", []))
		for pool in pools:
			for fx in pool:
				if str(fx.get("verb", "")) == "building" \
						and str(fx.get("structure_id", "")) == sid:
					return true
	for qid in quests:
		if qid == "_comment":
			continue
		var reward: Dictionary = quests[qid].get("reward", {})
		var qpools: Array = [reward.get("effects", [])]
		for ch in reward.get("choices", []):
			qpools.append(ch.get("effects", []))
		for pool in qpools:
			for fx in pool:
				if str(fx.get("verb", "")) == "building" \
						and str(fx.get("structure_id", "")) == sid:
					return true
	return false

# Every structure a trait grants free (`free_structures`) or builds at double
# speed (`double_production_structures`, B4) must exist in the structures table,
# and every `unit_production_modifiers` key (B4: per-unit +% build speed, e.g.
# Imperialistic settler) must name a real unit — a dangling id would silently
# grant nothing.
func _validate_trait_refs() -> void:
	for tid in leaders_traits.get("traits", {}):
		var t: Dictionary = leaders_traits["traits"][tid]
		for key in ["free_structures", "double_production_structures"]:
			for sid in t.get(key, []):
				if not structures.has(str(sid)):
					_errors.append("Trait '%s' %s '%s' not in structures table" % [tid, key, sid])
		for uid in t.get("unit_production_modifiers", {}):
			if not units.has(str(uid)):
				_errors.append("Trait '%s' unit_production_modifiers '%s' not in units table" % [tid, uid])

# Every structure id a belief references (temple/monastery/cathedral tiers and the
# holy_site_structure) must exist in the structures table, and a non-null
# founding_tech must name a real tech — a dangling id ships an unfoundable or
# undisplayable religion (the sun_faith/temple_of_sun class of bug).
func _validate_belief_refs() -> void:
	for bid in beliefs:
		if bid == "_comment":
			continue
		var belief: Dictionary = beliefs[bid]
		for key in ["temple", "monastery", "cathedral", "holy_site_structure"]:
			var sid = belief.get(key, null)
			if sid != null and sid != "" and not structures.has(str(sid)):
				_errors.append("Belief '%s' %s '%s' not in structures table" % [bid, key, sid])
		var tech = belief.get("founding_tech", null)
		if tech != null and tech != "" and not technologies.has(str(tech)):
			_errors.append("Belief '%s' founding_tech '%s' not found" % [bid, tech])

func _validate_tech_prereqs() -> void:
	for tech_id in technologies:
		var tech: Dictionary = technologies[tech_id]
		for prereq in tech.get("prereqs_all", []):
			if not technologies.has(prereq):
				_errors.append("Tech '%s' prereq_all '%s' not found" % [tech_id, prereq])
			elif str(prereq) == str(tech_id):
				_errors.append("Tech '%s' lists itself as a prereq_all" % tech_id)
		for prereq in tech.get("prereqs_any", []):
			if not technologies.has(prereq):
				_errors.append("Tech '%s' prereq_any '%s' not found" % [tech_id, prereq])
			elif str(prereq) == str(tech_id):
				_errors.append("Tech '%s' lists itself as a prereq_any" % tech_id)

# A unit's tech_required may be null, a single tech id, or a list of tech ids
# (compound AND form, §15.12). Every listed id must exist in the tech table.
func _validate_unit_tech_refs() -> void:
	for unit_id in units:
		var u: Dictionary = units[unit_id]
		var req = u.get("tech_required", null)
		if req != null and not (req is String) and not (req is Array):
			_errors.append("Unit '%s' tech_required must be null, a tech id, or a list of tech ids" % unit_id)
			continue
		for tech_id in UnitPrereqs.tech_list(req):
			if not technologies.has(tech_id):
				_errors.append("Unit '%s' tech_required '%s' not found" % [unit_id, tech_id])

# A unit's resource_required may be null, a single resource id, or a Dictionary
# with "all" / "any" lists (compound form, §15.12). Every referenced id must
# exist in the resources table, and a dictionary form may only carry the two
# known keys so a typo ("anyy") cannot silently drop a gate.
func _validate_unit_resource_refs() -> void:
	for unit_id in units:
		var u: Dictionary = units[unit_id]
		var req = u.get("resource_required", null)
		if req != null and not (req is String) and not (req is Dictionary):
			_errors.append("Unit '%s' resource_required must be null, a resource id, or {all/any} lists" % unit_id)
			continue
		if req is Dictionary:
			for key in req:
				if not (key in ["all", "any"]):
					_errors.append("Unit '%s' resource_required has unknown key '%s' (only all/any)" % [unit_id, key])
		for res_id in UnitPrereqs.resource_ids(req):
			if not resources.has(res_id):
				_errors.append("Unit '%s' resource_required '%s' not in resources table" % [unit_id, res_id])

func _validate_improvement_tech_refs() -> void:
	for imp_id in improvements:
		var imp: Dictionary = improvements[imp_id]
		var req = imp.get("tech_required", null)
		if req != null and req != "" and not technologies.has(req):
			_errors.append("Improvement '%s' tech_required '%s' not found" % [imp_id, req])

# Every great_person_unit referenced by a specialist must be a great-person unit,
# and every specialist_slots key on a structure must name a known specialist type.
func _validate_specialist_refs() -> void:
	for sid in specialists:
		if sid == "_comment":
			continue
		var spec: Dictionary = specialists[sid]
		var gp_unit = spec.get("great_person_unit", "")
		if gp_unit != null and gp_unit != "" and not units.has(gp_unit):
			_errors.append("Specialist '%s' great_person_unit '%s' not found" % [sid, gp_unit])
	for struct_id in structures:
		var slots: Dictionary = structures[struct_id].get("specialist_slots", {})
		for stype in slots:
			if not specialists.has(stype):
				_errors.append("Structure '%s' specialist_slots type '%s' not in specialists table" % [
					struct_id, stype])

# Every goody must carry an id and a non-negative weight (0 = only rolled where a
# difficulty overrides it upward, §24); a "unit" goody must name a unit type that
# exists in the units table, and an ambush's `spawn_unit` must resolve too. Every
# difficulty `goody_weights` override key must name a real goody.
func _validate_goody_refs() -> void:
	var goody_ids: Dictionary = {}
	for g in get_goodies():
		var gid = str(g.get("id", ""))
		if gid == "":
			_errors.append("Goody entry missing an id")
			continue
		goody_ids[gid] = true
		if int(g.get("weight", 0)) < 0:
			_errors.append("Goody '%s' must have a non-negative weight" % gid)
		var ut = g.get("unit_type", "")
		if ut != null and ut != "" and not units.has(str(ut)):
			_errors.append("Goody '%s' unit_type '%s' not in units table" % [gid, ut])
		var su = g.get("spawn_unit", "")
		if su != null and su != "" and not units.has(str(su)):
			_errors.append("Goody '%s' spawn_unit '%s' not in units table" % [gid, su])
	for diff_id in difficulties:
		var gw: Dictionary = difficulties[diff_id].get("goody_weights", {})
		for k in gw:
			if not goody_ids.has(str(k)):
				_errors.append("Difficulty '%s' goody_weights key '%s' not in goodies table" % [diff_id, k])

# Every corporation (§14.6) must resolve its HQ structure, executive unit, and
# input resources, and the HQ must be flagged so it is not offered as a normal build.
func _validate_econ_org_refs() -> void:
	for org_id in econ_orgs:
		if org_id == "_comment":
			continue
		var org: Dictionary = econ_orgs[org_id]
		var hq = str(org.get("hq_structure", ""))
		if hq != "":
			if not structures.has(hq):
				_errors.append("Corporation '%s' hq_structure '%s' not in structures table" % [org_id, hq])
			elif not bool(structures[hq].get("corporation_hq", false)):
				_errors.append("Corporation '%s' hq_structure '%s' missing corporation_hq flag" % [org_id, hq])
		var exe = str(org.get("executive_unit", ""))
		if exe != "" and not units.has(exe):
			_errors.append("Corporation '%s' executive_unit '%s' not in units table" % [org_id, exe])
		for res_id in org.get("input_resources", []):
			if not resources.has(res_id):
				_errors.append("Corporation '%s' input_resource '%s' not in resources table" % [org_id, res_id])
		var produced = str(org.get("produces_resource", ""))
		if produced != "" and not resources.has(produced):
			_errors.append("Corporation '%s' produces_resource '%s' not in resources table" % [org_id, produced])
		var channels := ["food", "production", "commerce", "gold", "research", "culture"]
		for ch in org.get("output_per_resource", {}):
			if not (str(ch) in channels):
				_errors.append("Corporation '%s' output_per_resource channel '%s' unknown" % [org_id, ch])

# Every espionage mission (§7.1) must carry an id and an effect verb the engine
# knows. Active records need a positive cost_multiplier (they are paid for and
# dispatched by SimFacade._espionage_apply); passive records (kind "passive",
# §25.6) instead need a positive threshold_multiplier and a valid scope — they
# are standing reveal thresholds, never executed.
func _validate_espionage_mission_refs() -> void:
	var known := ["steal_tech", "sabotage", "destroy_building", "destroy_project",
		"destroy_improvement", "steal_gold", "poison_water", "insert_culture",
		"incite_unhappiness", "incite_revolt", "switch_civic", "switch_religion",
		"counterespionage"]
	var known_passive := ["see_demographics", "investigate_city", "see_research",
		"city_visibility", "detect_missions"]
	for m in get_espionage_missions():
		var mid = str(m.get("id", ""))
		if mid == "":
			_errors.append("Espionage mission missing an id")
			continue
		var effect = str(m.get("effect", ""))
		if str(m.get("kind", "active")) == "passive":
			if int(m.get("threshold_multiplier", 0)) <= 0:
				_errors.append("Passive espionage mission '%s' must have a positive threshold_multiplier" % mid)
			if not (str(m.get("scope", "")) in ["alliance", "city"]):
				_errors.append("Passive espionage mission '%s' needs scope 'alliance' or 'city'" % mid)
			if not (effect in known_passive):
				_errors.append("Espionage mission '%s' has unknown passive effect '%s'" % [mid, effect])
			continue
		if int(m.get("cost_multiplier", 0)) <= 0:
			_errors.append("Espionage mission '%s' must have a positive cost_multiplier" % mid)
		if not (effect in known):
			_errors.append("Espionage mission '%s' has unknown effect '%s'" % [mid, effect])

# The AI diplomacy table (§7) must define the five attitude levels, one fewer
# threshold than levels (each ascending bucket), and a value+decay per memory kind.
func _validate_diplomacy_refs() -> void:
	if diplomacy.empty():
		_errors.append("data/diplomacy.json failed to load")
		return
	var levels: Array = diplomacy.get("attitude_levels", [])
	if levels.size() != 5:
		_errors.append("diplomacy.attitude_levels must list 5 levels, got %d" % levels.size())
	var thresholds: Array = diplomacy.get("attitude_thresholds", [])
	if thresholds.size() != levels.size() - 1:
		_errors.append("diplomacy.attitude_thresholds must have one fewer entry than attitude_levels")
	for i in range(1, thresholds.size()):
		if int(thresholds[i]) <= int(thresholds[i - 1]):
			_errors.append("diplomacy.attitude_thresholds must ascend")
			break
	var kinds: Dictionary = diplomacy.get("memory_kinds", {})
	if kinds.empty():
		_errors.append("diplomacy.memory_kinds must define at least one memory kind")
	for k in kinds:
		var spec: Dictionary = kinds[k]
		if not spec.has("value") or not spec.has("decay"):
			_errors.append("diplomacy.memory_kinds '%s' needs both value and decay" % k)
		elif int(spec.get("decay", 0)) <= 0:
			_errors.append("diplomacy.memory_kinds '%s' decay must be positive" % k)
	# The §7 denial-reason table must cover every reason id Diplomacy.evaluate_deal
	# can return, each with nonempty display text (surfaced in the trade UI).
	var denials: Dictionary = diplomacy.get("denial_reasons", {})
	for rid in ["no_trade_with_warring_party", "worst_enemy", "attitude_too_low",
			"tech_refusal", "insufficient_value"]:
		if str(denials.get(rid, {}).get("text", "")) == "":
			_errors.append("diplomacy.denial_reasons '%s' must define nonempty text" % rid)

# Every trigger must name an event that exists; every event effect (begin, choice,
# or expire) must use a known verb and resolve its unit/structure/tech reference.
# Every event's prereq/obsolete references must resolve, and every effect (begin,
# choice, expire, or nested `chance.then`) must use a known verb and resolve its
# unit/structure/tech/resource/promotion references.
func _validate_event_refs() -> void:
	for eid in events:
		if eid == "_comment":
			continue
		var ev: Dictionary = events[eid]
		_validate_event_prereq(eid, ev.get("prereq", {}))
		for t in ev.get("obsolete", []):
			if not technologies.has(str(t)):
				_errors.append("Event '%s' obsolete tech '%s' not found" % [eid, t])
		_validate_event_effects(eid, ev.get("effects", []))
		_validate_event_effects(eid, ev.get("expire_effects", []))
		for ch in ev.get("choices", []):
			_validate_event_effects(eid, ch.get("effects", []))

func _validate_event_prereq(eid: String, pr: Dictionary) -> void:
	for t in pr.get("tech_all", []):
		if not technologies.has(str(t)):
			_errors.append("Event '%s' prereq tech_all '%s' not found" % [eid, t])
	for t in pr.get("tech_any", []):
		if not technologies.has(str(t)):
			_errors.append("Event '%s' prereq tech_any '%s' not found" % [eid, t])
	if pr.has("players_tech"):
		var pt = str(pr["players_tech"].get("tech", ""))
		if not technologies.has(pt):
			_errors.append("Event '%s' prereq players_tech '%s' not found" % [eid, pt])
	if pr.has("building") and not structures.has(str(pr["building"])):
		_errors.append("Event '%s' prereq building '%s' not in structures" % [eid, pr["building"]])
	if pr.has("civic") and not policies.get("policies", {}).has(str(pr["civic"])):
		_errors.append("Event '%s' prereq civic '%s' not a policy" % [eid, pr["civic"]])
	if pr.has("resource_absent") and not resources.has(str(pr["resource_absent"])):
		_errors.append("Event '%s' prereq resource_absent '%s' not a resource" % [eid, pr["resource_absent"]])
	if pr.has("can_have_resource"):
		var crr = str(pr["can_have_resource"].get("resource", ""))
		if not resources.has(crr):
			_errors.append("Event '%s' prereq can_have_resource '%s' not a resource" % [eid, crr])
	if pr.has("society"):
		var socs: Dictionary = leaders_traits.get("societies", {})
		var sv = pr["society"]
		var slist: Array = sv if typeof(sv) == TYPE_ARRAY else [sv]
		for sid in slist:
			if not socs.has(str(sid)):
				_errors.append("Event '%s' prereq society '%s' not a society" % [eid, sid])

func _validate_event_effects(eid: String, effects: Array) -> void:
	var known := ["gold", "research", "research_pct_remaining", "research_pct_loss",
		"culture", "tech", "unit", "building", "capital_health", "capital_pop",
		"nearby_pop", "heal_units", "food_store", "golden_age", "attitude",
		"grant_promotion", "city_happy_timed", "place_resource", "tile_yield",
		"remove_feature", "remove_improvement", "remove_route", "spawn_wild", "chance",
		"structure_yield", "specialist", "settle_great_person", "spread_religion",
		"destroy_building", "pillage", "revolt", "make_peace", "declare_war",
		"espionage", "unit_state", "city_health_timed", "reveal_resource",
		"place_improvement", "add_feature", "destroy_unit", "draft", "unit_support",
		"inflation", "route_speed", "movie_bonus", "spaceship_bonus", "resource_gift"]
	for eff in effects:
		var verb = str(eff.get("verb", ""))
		if not (verb in known):
			_errors.append("Event '%s' uses unknown effect verb '%s'" % [eid, verb])
		match verb:
			"unit", "spawn_wild":
				if not units.has(str(eff.get("unit_type", ""))):
					_errors.append("Event '%s' unit effect type '%s' not in units table" % [eid, eff.get("unit_type", "")])
			"building":
				if not structures.has(str(eff.get("structure_id", ""))):
					_errors.append("Event '%s' building effect '%s' not in structures table" % [eid, eff.get("structure_id", "")])
			"tech":
				var tid = str(eff.get("tech_id", ""))
				if tid != "" and not technologies.has(tid):
					_errors.append("Event '%s' tech effect '%s' not found" % [eid, tid])
			"grant_promotion":
				if not promotions.has(str(eff.get("promotion", ""))):
					_errors.append("Event '%s' grant_promotion '%s' not in promotions" % [eid, eff.get("promotion", "")])
			"place_resource":
				if not resources.has(str(eff.get("resource", ""))):
					_errors.append("Event '%s' place_resource '%s' not a resource" % [eid, eff.get("resource", "")])
				if eff.has("add_improvement") and not improvements.has(str(eff["add_improvement"])):
					_errors.append("Event '%s' place_resource add_improvement '%s' not an improvement" % [eid, eff["add_improvement"]])
			"structure_yield":
				if not structures.has(str(eff.get("structure_id", ""))):
					_errors.append("Event '%s' structure_yield '%s' not in structures table" % [eid, eff.get("structure_id", "")])
			"specialist":
				if not specialists.has(str(eff.get("specialist_type", ""))):
					_errors.append("Event '%s' specialist effect type '%s' not a specialist" % [eid, eff.get("specialist_type", "")])
			"settle_great_person":
				var gp_known := ["general", "prophet", "priest", "artist", "scientist", "merchant", "spy", "engineer"]
				if not (str(eff.get("gp_type", "")) in gp_known):
					_errors.append("Event '%s' settle_great_person gp_type '%s' unknown" % [eid, eff.get("gp_type", "")])
			"spread_religion":
				var b = str(eff.get("belief", ""))
				if b != "" and not beliefs.has(b):
					_errors.append("Event '%s' spread_religion belief '%s' not a belief" % [eid, b])
			"reveal_resource":
				if not resources.has(str(eff.get("resource", ""))):
					_errors.append("Event '%s' reveal_resource '%s' not a resource" % [eid, eff.get("resource", "")])
				if eff.has("add_improvement") and not improvements.has(str(eff["add_improvement"])):
					_errors.append("Event '%s' reveal_resource add_improvement '%s' not an improvement" % [eid, eff["add_improvement"]])
			"place_improvement":
				if not improvements.has(str(eff.get("improvement", ""))):
					_errors.append("Event '%s' place_improvement '%s' not an improvement" % [eid, eff.get("improvement", "")])
			"add_feature":
				if not features.has(str(eff.get("feature", ""))):
					_errors.append("Event '%s' add_feature '%s' not a feature" % [eid, eff.get("feature", "")])
			"draft":
				if not units.has(str(eff.get("unit_type", ""))):
					_errors.append("Event '%s' draft unit_type '%s' not in units table" % [eid, eff.get("unit_type", "")])
			"chance":
				_validate_event_effects(eid, eff.get("then", []))

# Every quest (§4) must carry an id, validate its prereq via the SAME path as events
# (the shared prereq vocabulary), declare an aim whose `kind` is a known aim kind, an
# optional constraint whose `kind` is a known constraint kind, and a reward whose begin
# `effects[]` / per-choice `effects[]` use known event-effect verbs (validated via the
# event-effect validator). Structure refs inside a build_count aim are checked too.
func _validate_quest_refs() -> void:
	var aim_kinds := ["build_count", "build_units", "build_fleet",
		"cities_on_landmasses", "control_named_tile", "conquer_resource",
		"conquer_holy_city", "spread_corp", "own_corp_resources"]
	var constraint_kinds := ["never_switch_state_religion", "keep_trigger_city"]
	for qid in quests:
		if qid == "_comment":
			continue
		var q: Dictionary = quests[qid]
		# Reuse the event prereq validator (same vocabulary).
		_validate_event_prereq(qid, q.get("prereq", {}))
		var aim: Dictionary = q.get("aim", {})
		var ak = str(aim.get("kind", ""))
		if not (ak in aim_kinds):
			_errors.append("Quest '%s' has unknown aim kind '%s'" % [qid, ak])
		if ak == "build_count":
			var bs = str(aim.get("structure_id", ""))
			if bs != "" and not structures.has(bs):
				_errors.append("Quest '%s' aim structure_id '%s' not in structures" % [qid, bs])
			for also_id in aim.get("also", []):
				if not structures.has(str(also_id)):
					_errors.append("Quest '%s' aim also '%s' not in structures" % [qid, also_id])
			for w_id in aim.get("weights", {}):
				if not structures.has(str(w_id)):
					_errors.append("Quest '%s' aim weights '%s' not in structures" % [qid, w_id])
		if ak == "build_units":
			var ut := []
			if aim.has("unit_types"):
				ut = aim["unit_types"]
			elif str(aim.get("unit_type", "")) != "":
				ut = [str(aim["unit_type"])]
			for uid in ut:
				if not units.has(str(uid)):
					_errors.append("Quest '%s' aim unit_type '%s' not in units" % [qid, uid])
		if ak == "build_fleet":
			for uid in aim.get("composition", {}):
				if not units.has(str(uid)):
					_errors.append("Quest '%s' aim composition '%s' not in units" % [qid, uid])
		if ak == "conquer_resource":
			var rl := []
			if aim.has("resources"):
				rl = aim["resources"]
			elif str(aim.get("resource", "")) != "":
				rl = [str(aim["resource"])]
			for rid in rl:
				if not resources.has(str(rid)):
					_errors.append("Quest '%s' aim resource '%s' not a resource" % [qid, rid])
		if q.has("constraint"):
			var ck = str(q["constraint"].get("kind", ""))
			if not (ck in constraint_kinds):
				_errors.append("Quest '%s' has unknown constraint kind '%s'" % [qid, ck])
		# Reward effects (begin or per-choice) reuse the event-effect validator.
		var reward: Dictionary = q.get("reward", {})
		_validate_event_effects(qid, reward.get("effects", []))
		for ch in reward.get("choices", []):
			_validate_event_effects(qid, ch.get("effects", []))
