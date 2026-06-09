# Humanish — a turn-based 4X strategy game.
# Copyright (C) 2026 thalia-at-lesbos
# SPDX-License-Identifier: GPL-3.0-or-later
#
# This program is free software: you can redistribute it and/or modify it
# under the terms of the GNU General Public License as published by the Free
# Software Foundation, either version 3 of the License, or (at your option)
# any later version. See the LICENSE file for the full text and warranty
# disclaimer.

class_name Settlement
extends Reference

var id: int = 0
var name: String = ""
var owner_player_id: int = -1
var x: int = 0
var y: int = 0

# Population
var population: int = 1
var food_store: int = 0       # accumulated surplus sustenance

# Output (cached, recomputed each turn from worked tiles + specialists + structures)
var output_food: int = 0
var output_production: int = 0
var output_commerce: int = 0

# Production queue: Array of {"type": "unit"/"structure"/"project", "id": String}
var production_queue: Array = []
var production_store: int = 0   # accumulated production

# Culture
var culture_total: int = 0      # total accumulated culture
var culture_ring: int = 1       # current border ring (1 = just own tile + immediate)

# Contentment
var positive_sentiment: int = 0
var negative_sentiment: int = 0  # = anger_percent * population / 100
var discontented: int = 0        # = clamp(negative - positive, 0, population)
var in_disorder: bool = false

# Wellbeing
var wellbeing_positive: int = 0
var wellbeing_negative: int = 0
var wellbeing_deficit: int = 0   # max(0, negative - positive)

# Worked tiles: Array of [x, y] pairs (plus specialist slots)
var worked_tiles: Array = []
var specialists: Dictionary = {}  # specialist_type -> count
# Manual citizen management (§11 city screen): tiles the player has explicitly
# locked to be worked, and whether unlocked worker slots are auto-filled.
# Locked tiles are always worked (capacity permitting); when auto is on the
# remaining slots fill automatically (the historical behaviour), when off only
# the locked tiles are worked.
var locked_tiles: Array = []          # Array of [x, y] pairs
var manage_citizens_auto: bool = true

# Structures built
var structures: Array = []        # Array of structure IDs

# Beliefs/affiliations
var belief_id: String = ""
var econ_org_id: String = ""

# Special person progress
var special_person_points: int = 0
var special_person_threshold: int = 100
var special_persons_produced: int = 0

# Rushing penalty turns
var rush_anger_turns: int = 0

# Entrenchment for garrison (number of turns garrisoned)
var garrison_turns: int = 0

# Defense value (from walls + culture)
var defence_value: int = 0

# Conquest (§4.8). `health` is the city's defensive integrity (siege HP): an
# assault on the undefended city tile lowers it, and the city falls at 0. It
# regenerates each owner turn up to its maximum (see TurnEngine.city_max_health).
# `peak_population` is the largest size the city has ever reached — a size-1 city
# that has never been bigger is auto-razed on capture. `revolt_turns` counts
# down post-capture occupation, during which the city produces nothing.
var health: int = -1            # -1 = "full"; normalised to max on first use
var peak_population: int = 1
var revolt_turns: int = 0
var produce_nothing: bool = false
# Cultural-revolt progress (§4.9): successful revolt checks accumulated against
# this settlement; it flips once they reach revolt_required_successes, and resets
# to 0 whenever no rival out-cultures the owner on its tile (pressure relieved).
var revolt_progress: int = 0

# Raider-camp alert state (§9 wild forces, provisional). A camp (owner -2) whose
# scout has sighted a player raises an alert: it musters one unit per world step
# toward `alert_target` while `alert_turns` > 0, then enters `alert_cooldown`
# before it can be roused again. All zero/-1 on non-camp settlements.
var alert_turns: int = 0
var alert_target_x: int = -1
var alert_target_y: int = -1
var alert_cooldown: int = 0

func has_structure(struct_id: String) -> bool:
	return struct_id in structures

func effective_workers() -> int:
	return 0 if population <= discontented else population - discontented

func serialize() -> Dictionary:
	return {
		"id": id, "name": name, "owner_player_id": owner_player_id,
		"x": x, "y": y, "population": population, "food_store": food_store,
		"output_food": output_food, "output_production": output_production,
		"output_commerce": output_commerce,
		"production_queue": production_queue.duplicate(true),
		"production_store": production_store,
		"culture_total": culture_total, "culture_ring": culture_ring,
		"positive_sentiment": positive_sentiment,
		"negative_sentiment": negative_sentiment,
		"discontented": discontented, "in_disorder": in_disorder,
		"wellbeing_positive": wellbeing_positive,
		"wellbeing_negative": wellbeing_negative,
		"wellbeing_deficit": wellbeing_deficit,
		"worked_tiles": worked_tiles.duplicate(true),
		"locked_tiles": locked_tiles.duplicate(true),
		"manage_citizens_auto": manage_citizens_auto,
		"specialists": specialists.duplicate(),
		"structures": structures.duplicate(),
		"belief_id": belief_id, "econ_org_id": econ_org_id,
		"special_person_points": special_person_points,
		"special_person_threshold": special_person_threshold,
		"special_persons_produced": special_persons_produced,
		"rush_anger_turns": rush_anger_turns,
		"garrison_turns": garrison_turns,
		"defence_value": defence_value,
		"health": health, "peak_population": peak_population,
		"revolt_turns": revolt_turns, "revolt_progress": revolt_progress,
		"produce_nothing": produce_nothing,
		"alert_turns": alert_turns, "alert_target_x": alert_target_x,
		"alert_target_y": alert_target_y, "alert_cooldown": alert_cooldown
	}

static func deserialize(d: Dictionary):
	var s = load("res://src/sim/settlement.gd").new()
	s.id = int(d["id"]); s.name = str(d.get("name", ""))
	s.owner_player_id = int(d.get("owner_player_id", -1))
	s.x = int(d["x"]); s.y = int(d["y"])
	s.population = int(d.get("population", 1))
	s.food_store = int(d.get("food_store", 0))
	s.output_food = int(d.get("output_food", 0))
	s.output_production = int(d.get("output_production", 0))
	s.output_commerce = int(d.get("output_commerce", 0))
	s.production_queue = d.get("production_queue", []).duplicate(true)
	s.production_store = int(d.get("production_store", 0))
	s.culture_total = int(d.get("culture_total", 0))
	s.culture_ring = int(d.get("culture_ring", 1))
	s.positive_sentiment = int(d.get("positive_sentiment", 0))
	s.negative_sentiment = int(d.get("negative_sentiment", 0))
	s.discontented = int(d.get("discontented", 0))
	s.in_disorder = bool(d.get("in_disorder", false))
	s.wellbeing_positive = int(d.get("wellbeing_positive", 0))
	s.wellbeing_negative = int(d.get("wellbeing_negative", 0))
	s.wellbeing_deficit = int(d.get("wellbeing_deficit", 0))
	s.worked_tiles = d.get("worked_tiles", []).duplicate(true)
	s.locked_tiles = d.get("locked_tiles", []).duplicate(true)
	s.manage_citizens_auto = bool(d.get("manage_citizens_auto", true))
	s.specialists = d.get("specialists", {}).duplicate()
	s.structures = d.get("structures", []).duplicate()
	s.belief_id = str(d.get("belief_id", ""))
	s.econ_org_id = str(d.get("econ_org_id", ""))
	s.special_person_points = int(d.get("special_person_points", 0))
	s.special_person_threshold = int(d.get("special_person_threshold", 100))
	s.special_persons_produced = int(d.get("special_persons_produced", 0))
	s.rush_anger_turns = int(d.get("rush_anger_turns", 0))
	s.garrison_turns = int(d.get("garrison_turns", 0))
	s.defence_value = int(d.get("defence_value", 0))
	s.health = int(d.get("health", -1))
	s.peak_population = int(d.get("peak_population", s.population))
	s.revolt_turns = int(d.get("revolt_turns", 0))
	s.revolt_progress = int(d.get("revolt_progress", 0))
	s.produce_nothing = bool(d.get("produce_nothing", false))
	s.alert_turns = int(d.get("alert_turns", 0))
	s.alert_target_x = int(d.get("alert_target_x", -1))
	s.alert_target_y = int(d.get("alert_target_y", -1))
	s.alert_cooldown = int(d.get("alert_cooldown", 0))
	return s
