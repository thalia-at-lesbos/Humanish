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
var ages: Dictionary = {}
var paces: Dictionary = {}
var difficulties: Dictionary = {}
var world_sizes: Dictionary = {}
var map_types: Dictionary = {}
var leaders_traits: Dictionary = {}
var projects: Dictionary = {}
var win_conditions: Dictionary = {}
var events: Dictionary = {}
# Diplomatic-assembly elections & resolutions (§18, provisional).
var resolutions: Dictionary = {}

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
	ages         = _load_json("res://data/ages.json")
	paces        = _load_json("res://data/paces.json")
	difficulties = _load_json("res://data/difficulties.json")
	world_sizes  = _load_json("res://data/world_sizes.json")
	map_types    = _load_json("res://data/map_types.json")
	leaders_traits = _load_json("res://data/leaders_traits.json")
	projects     = _load_json("res://data/projects.json")
	win_conditions = _load_json("res://data/win_conditions.json")
	events       = _load_json("res://data/events.json")
	resolutions  = _load_json("res://data/resolutions.json")
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

func get_resolution(id: String) -> Dictionary:
	# Skip the leading "_comment" documentation key (not a resolution).
	return resolutions.get(id, {})

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
