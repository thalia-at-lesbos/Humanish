# Humanish — a turn-based 4X strategy game.
# Copyright (C) 2026 thalia-at-lesbos
# SPDX-License-Identifier: GPL-3.0-or-later
#
# This program is free software: you can redistribute it and/or modify it
# under the terms of the GNU General Public License as published by the Free
# Software Foundation, either version 3 of the License, or (at your option)
# any later version. See the LICENSE file for the full text and warranty
# disclaimer.

class_name Player
extends Reference

var id: int = 0
var name: String = ""
var leader_id: String = ""
var traits: Array = []        # Array of trait IDs

# Economy
var treasury: int = 0
# Sliders are percentages and must sum to 100. A new player pours everything into
# research by default so the tech tree advances from turn one without the player
# having to touch the sliders.
var slider_finance: int = 0
var slider_research: int = 100
var slider_culture: int = 0
var slider_intel: int = 0

# Policy selections per category
var policies: Dictionary = {}  # category -> policy_id

# State religion (§8): the belief_id this player has adopted empire-wide, or ""
# for none. Every player starts with no state religion; "none" is a valid choice.
# Switching away from an existing state religion triggers anarchy (see
# transition_turns), unless this is the first adoption or the player is Spiritual.
var state_religion: String = ""

# Research
var current_research_id: String = ""
var research_store: int = 0     # accumulated research points

# Technologies known
var technologies: Array = []    # Array of tech IDs

# Current era index (§1), a *cache* of the highest era among researched techs.
# Recomputed by Eras.refresh whenever techs change; mechanics read the era live via
# Eras.player_era, so this only exists to detect advancement for the notification.
var era: int = 0

# Espionage accumulation per target alliance_id
var intel_points: Dictionary = {}   # alliance_id -> int

# Decaying diplomatic memory of other players' acts (§7, Diplomacy): keyed by the
# remembered rival's player_id, each a {memory_kind -> signed points} Dictionary.
# Points accrue when the rival acts (Diplomacy.record) and decay toward zero each
# turn (Diplomacy.decay); the running total feeds the AI's attitude. Serialized
# with int-key coercion on load (the recurring JSON float/string-key gotcha).
var diplo_memory: Dictionary = {}   # rival_player_id -> {kind: points}

# Alliance membership
var alliance_id: int = -1

# Free early wins remaining (from difficulty)
var free_early_wins: int = 0

# Anarchy turns remaining (§8): the interregnum after switching an established
# civic or state religion. While > 0 the player's settlements yield no commerce
# (no gold, research, culture, or intelligence); food and production continue.
# Ticks down once per turn. The first adoption in a category (from none) is free,
# as is any switch for a Spiritual leader.
var transition_turns: int = 0

# Score cache (updated each turn)
var score: int = 0

# Is the player eliminated?
var is_eliminated: bool = false

# Is this player driven by the computer (PlayerAI) rather than a human?
var is_ai: bool = false

# Active celebration turns
var celebration_turns: int = 0

# IDs of scripted events already fired for this player (so once-only events
# do not repeat).
var events_fired: Array = []

# Consecutive turns the player has been insolvent; selling/disbanding only kicks
# in once this passes the grace period (§6.1).
var insolvent_turns: int = 0

# Golden Age state (§14.4). golden_age_turns counts down each turn while active;
# golden_age_count is how many have been started (escalates the GP cost of the
# next); pending_golden_age_gp accumulates Great Persons sacrificed toward the
# next/extended Golden Age.
var golden_age_turns: int = 0
var golden_age_count: int = 0
var pending_golden_age_gp: int = 0

# Great General accumulation from combat (§14.2). Points come from combat
# victories; when they cross the rising threshold a Great General is born in the
# field. great_general_threshold == 0 means "use the data default on first use".
var great_general_points: int = 0
var great_general_threshold: int = 0
var great_generals_produced: int = 0

func has_tech(tech_id: String) -> bool:
	return tech_id in technologies

func get_slider_sum() -> int:
	return slider_finance + slider_research + slider_culture + slider_intel

# Split a total commerce value according to sliders. Returns [finance, research, culture, intel].
func split_commerce(total_commerce: int) -> Array:
	var fin: int = Fixed.scale(total_commerce, slider_finance)
	var res: int = Fixed.scale(total_commerce, slider_research)
	var cul: int = Fixed.scale(total_commerce, slider_culture)
	var itl: int = total_commerce - fin - res - cul  # remainder goes to intel
	return [fin, res, cul, itl]

func serialize() -> Dictionary:
	return {
		"id": id, "name": name, "leader_id": leader_id, "traits": traits.duplicate(),
		"treasury": treasury,
		"slider_finance": slider_finance, "slider_research": slider_research,
		"slider_culture": slider_culture, "slider_intel": slider_intel,
		"policies": policies.duplicate(),
		"current_research_id": current_research_id,
		"research_store": research_store,
		"technologies": technologies.duplicate(),
		"era": era,
		"intel_points": intel_points.duplicate(),
		"diplo_memory": diplo_memory.duplicate(true),
		"alliance_id": alliance_id,
		"free_early_wins": free_early_wins,
		"transition_turns": transition_turns,
		"state_religion": state_religion,
		"score": score,
		"is_eliminated": is_eliminated,
		"is_ai": is_ai,
		"celebration_turns": celebration_turns,
		"events_fired": events_fired.duplicate(),
		"insolvent_turns": insolvent_turns,
		"golden_age_turns": golden_age_turns,
		"golden_age_count": golden_age_count,
		"pending_golden_age_gp": pending_golden_age_gp,
		"great_general_points": great_general_points,
		"great_general_threshold": great_general_threshold,
		"great_generals_produced": great_generals_produced
	}

static func deserialize(d: Dictionary):
	var p = load("res://src/sim/player.gd").new()
	p.id = int(d["id"])
	p.name = str(d.get("name", ""))
	p.leader_id = str(d.get("leader_id", ""))
	p.traits = d.get("traits", []).duplicate()
	p.treasury = int(d.get("treasury", 0))
	p.slider_finance = int(d.get("slider_finance", 0))
	p.slider_research = int(d.get("slider_research", 100))
	p.slider_culture = int(d.get("slider_culture", 0))
	p.slider_intel = int(d.get("slider_intel", 0))
	p.policies = d.get("policies", {}).duplicate()
	p.current_research_id = str(d.get("current_research_id", ""))
	p.research_store = int(d.get("research_store", 0))
	p.technologies = d.get("technologies", []).duplicate()
	p.era = int(d.get("era", 0))
	# intel_points is keyed by alliance_id (int). JSON turns every dict key into a
	# string on save, so coerce back to int on load — otherwise the loaded "2" key
	# never matches the int lookups in _apply_intelligence and a phantom duplicate
	# entry accumulates separately (a save/load determinism break).
	p.intel_points = {}
	var loaded_intel: Dictionary = d.get("intel_points", {})
	for k in loaded_intel:
		p.intel_points[int(k)] = int(loaded_intel[k])
	# diplo_memory is rival_player_id(int) -> {kind(str): points(int)}. JSON turns the
	# outer key into a string and the points into floats, so coerce both back on load.
	p.diplo_memory = {}
	var loaded_mem: Dictionary = d.get("diplo_memory", {})
	for rk in loaded_mem:
		var kinds: Dictionary = {}
		for kind in loaded_mem[rk]:
			kinds[str(kind)] = int(loaded_mem[rk][kind])
		p.diplo_memory[int(rk)] = kinds
	p.alliance_id = int(d.get("alliance_id", -1))
	p.free_early_wins = int(d.get("free_early_wins", 0))
	p.transition_turns = int(d.get("transition_turns", 0))
	p.state_religion = str(d.get("state_religion", ""))
	p.score = int(d.get("score", 0))
	p.is_eliminated = bool(d.get("is_eliminated", false))
	p.is_ai = bool(d.get("is_ai", false))
	p.celebration_turns = int(d.get("celebration_turns", 0))
	p.events_fired = d.get("events_fired", []).duplicate()
	p.insolvent_turns = int(d.get("insolvent_turns", 0))
	p.golden_age_turns = int(d.get("golden_age_turns", 0))
	p.golden_age_count = int(d.get("golden_age_count", 0))
	p.pending_golden_age_gp = int(d.get("pending_golden_age_gp", 0))
	p.great_general_points = int(d.get("great_general_points", 0))
	p.great_general_threshold = int(d.get("great_general_threshold", 0))
	p.great_generals_produced = int(d.get("great_generals_produced", 0))
	return p
