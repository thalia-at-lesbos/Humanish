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
# Trigger predicates that decide when an event fires (§9 lifecycle).
var event_triggers: Dictionary = {}
# Goody-hut / discovery-site reward table (§9).
var goodies: Dictionary = {}
# Diplomatic-assembly elections & resolutions (§18, provisional).
var resolutions: Dictionary = {}
# Espionage mission catalogue spent against rival alliances (§7.1, provisional).
var espionage_missions: Dictionary = {}

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
	event_triggers = _load_json("res://data/event_triggers.json")
	goodies      = _load_json("res://data/goodies.json")
	resolutions  = _load_json("res://data/resolutions.json")
	espionage_missions = _load_json("res://data/espionage_missions.json")
	_validate()
	return _errors.empty()

func get_errors() -> Array:
	return _errors

func get_constant(key: String, default_val: int = 0) -> int:
	return int(constants.get(key, default_val))

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

# All trigger predicates (callers iterating must skip the leading "_comment" key).
func get_event_triggers() -> Dictionary:
	return event_triggers

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
	_validate_improvement_tech_refs()
	_validate_specialist_refs()
	_validate_goody_refs()
	_validate_event_refs()
	_validate_econ_org_refs()
	_validate_espionage_mission_refs()

func _validate_tech_prereqs() -> void:
	for tech_id in technologies:
		var tech: Dictionary = technologies[tech_id]
		for prereq in tech.get("prereqs_all", []):
			if not technologies.has(prereq):
				_errors.append("Tech '%s' prereq_all '%s' not found" % [tech_id, prereq])
		for prereq in tech.get("prereqs_any", []):
			if not technologies.has(prereq):
				_errors.append("Tech '%s' prereq_any '%s' not found" % [tech_id, prereq])

func _validate_unit_tech_refs() -> void:
	for unit_id in units:
		var u: Dictionary = units[unit_id]
		var req = u.get("tech_required", null)
		if req != null and req != "" and not technologies.has(req):
			_errors.append("Unit '%s' tech_required '%s' not found" % [unit_id, req])

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

# Every goody must carry an id and a positive weight; a "unit" goody must name a
# unit type that exists in the units table.
func _validate_goody_refs() -> void:
	for g in get_goodies():
		var gid = str(g.get("id", ""))
		if gid == "":
			_errors.append("Goody entry missing an id")
			continue
		if int(g.get("weight", 0)) <= 0:
			_errors.append("Goody '%s' must have a positive weight" % gid)
		var ut = g.get("unit_type", "")
		if ut != null and ut != "" and not units.has(str(ut)):
			_errors.append("Goody '%s' unit_type '%s' not in units table" % [gid, ut])

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

# Every espionage mission (§7.1) must carry an id, a positive cost_multiplier, and
# an effect verb SimFacade._espionage_apply knows how to dispatch.
func _validate_espionage_mission_refs() -> void:
	var known := ["steal_tech", "sabotage", "incite_unrest", "steal_gold", "poison_water"]
	for m in get_espionage_missions():
		var mid = str(m.get("id", ""))
		if mid == "":
			_errors.append("Espionage mission missing an id")
			continue
		if int(m.get("cost_multiplier", 0)) <= 0:
			_errors.append("Espionage mission '%s' must have a positive cost_multiplier" % mid)
		var effect = str(m.get("effect", ""))
		if not (effect in known):
			_errors.append("Espionage mission '%s' has unknown effect '%s'" % [mid, effect])

# Every trigger must name an event that exists; every event effect (begin, choice,
# or expire) must use a known verb and resolve its unit/structure/tech reference.
func _validate_event_refs() -> void:
	for tid in event_triggers:
		if tid == "_comment":
			continue
		var trig: Dictionary = event_triggers[tid]
		var eid = str(trig.get("event_id", ""))
		if eid == "" or not events.has(eid):
			_errors.append("Event trigger '%s' event_id '%s' not in events table" % [tid, eid])
		var treq = trig.get("tech_required", "")
		if treq != null and treq != "" and not technologies.has(str(treq)):
			_errors.append("Event trigger '%s' tech_required '%s' not found" % [tid, treq])
		var breq = trig.get("building_required", "")
		if breq != null and breq != "" and not structures.has(str(breq)):
			_errors.append("Event trigger '%s' building_required '%s' not found" % [tid, breq])
	for eid in events:
		if eid == "_comment":
			continue
		var ev: Dictionary = events[eid]
		_validate_event_effects(eid, ev.get("effects", []))
		_validate_event_effects(eid, ev.get("expire_effects", []))
		for ch in ev.get("choices", []):
			_validate_event_effects(eid, ch.get("effects", []))

func _validate_event_effects(eid: String, effects: Array) -> void:
	var known := ["gold", "research", "culture", "tech", "unit", "building",
		"capital_health", "heal_units"]
	for eff in effects:
		var verb = str(eff.get("verb", ""))
		if not (verb in known):
			_errors.append("Event '%s' uses unknown effect verb '%s'" % [eid, verb])
		if verb == "unit":
			var ut = str(eff.get("unit_type", ""))
			if not units.has(ut):
				_errors.append("Event '%s' unit effect type '%s' not in units table" % [eid, ut])
		elif verb == "building":
			var st = str(eff.get("structure_id", ""))
			if not structures.has(st):
				_errors.append("Event '%s' building effect '%s' not in structures table" % [eid, st])
		elif verb == "tech":
			var tid = str(eff.get("tech_id", ""))
			if tid != "" and not technologies.has(tid):
				_errors.append("Event '%s' tech effect '%s' not found" % [eid, tid])
