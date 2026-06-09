# Humanish — a turn-based 4X strategy game.
# Copyright (C) 2026 thalia-at-lesbos
# SPDX-License-Identifier: GPL-3.0-or-later
#
# This program is free software: you can redistribute it and/or modify it
# under the terms of the GNU General Public License as published by the Free
# Software Foundation, either version 3 of the License, or (at your option)
# any later version. See the LICENSE file for the full text and warranty
# disclaimer.

class_name GameState
extends Reference

# Root aggregate for the entire simulation. The single source of truth.
# All mutable state lives here; nothing in sim/ maintains state outside this object.

var db: DataDB
var rng: RNG
var map: WorldMap

var players: Array = []        # Array of Player
var settlements: Array = []    # Array of Settlement
var units: Array = []          # Array of Unit
var alliances: Array = []      # Array of Alliance

var turn_number: int = 0
var max_turns: int = 500
var pace_id: String = "normal"
var difficulty_id: String = "prince"
var current_player_id: int = -1  # whose turn it is (-1 = world step)

var enabled_win_conditions: Array = []
var winning_alliance_id: int = -1  # -1 = game still running

# Optional §9 setting: when true, wild/raider forces muster longer waves with
# shorter cooldowns and a wider scout reach (WildAI). Off by default.
var wild_aggressive: bool = false

# Optional rule: when true, players who are at peace may form permanent alliances
# via the Propose Permanent Alliance diplomatic action (locked for the rest of the
# game). Off by default.
var permanent_alliances: bool = false

# Founded beliefs and econ orgs (globally tracked)
var founded_beliefs: Dictionary = {}   # belief_id -> founder player_id
var founded_econ_orgs: Dictionary = {} # org_id -> founder player_id

# Endgame project stages completed per alliance
var endgame_project_stages: Dictionary = {}  # alliance_id -> int

# Diplomatic assembly tally: votes cast for each alliance's candidate.
# Populated by the assembly/voting phase (§3 world-step 7); read by the
# diplomatic win condition (§10).
var diplomatic_votes: Dictionary = {}  # alliance_id -> int votes

# Diplomatic assembly state (§7.2, provisional). Empty until a founding wonder
# (Apostolic Palace / United Nations) creates an assembly. Once active:
#   {kind, belief_id, resident_player_id, last_session_turn,
#    standing: {<effect>: payload}, pending: {resolution_id, candidate_player_id,
#    target_alliance_id, belief_id, text, votes:{<pid>:"yea"/"nay"/"abstain"}}}
# Managed by the Assembly module; serialized so a session in progress survives
# save/load and stays on the determinism gate.
var assembly: Dictionary = {}

# Transient assembly records (session opened / resolution resolved) produced by
# the Assembly module during the world step, drained by SimFacade into
# notifications + the assembly_event signal. Not serialized.
var pending_assembly_events: Array = []  # [{kind, ...payload}]

# Transient cultural-flip records produced by the §4.9 revolt phase during a
# player step, drained by SimFacade into notifications + the city_flipped signal.
# Not serialized: it never survives past the end of the turn that produced it.
var pending_flips: Array = []  # [{settlement_id, from_player_id, to_player_id}]

# Transient era-advancement records produced when a player crosses into a new era
# (§1) during a player step, drained by SimFacade into notifications + the
# era_advanced signal. Not serialized: it never survives past the turn that
# produced it (Player.era carries the persistent state).
var pending_era_advances: Array = []  # [{player_id, from, to}]

# Transient wild-forces combat/conquest records produced by WildAI during the
# world step (§9), drained by SimFacade into notifications + combat/conquest
# signals. Not serialized: it never survives past the turn that produced it.
# Each entry is {"kind": "combat"/"captured"/"razed", ...payload}.
var pending_wild_events: Array = []

# Transient tech-completion records produced by TurnEngine._apply_research and
# _apply_special_person during a player step, drained by SimFacade into
# notifications + the technology_completed signal. Not serialized.
# Each entry is {"player_id": int, "tech_id": String}.
var pending_tech_completions: Array = []

# Transient great-person birth records produced by GreatPeople.birth_from_settlement
# and award_combat_points during a player/world step, drained by SimFacade into
# notifications. Not serialized.
# Each entry is {"player_id": int, "unit_type_id": String}.
var pending_great_people: Array = []

# Transient wonder/project-completion records produced by TurnEngine._complete_item
# during a player step, drained by SimFacade into notifications. Not serialized.
# Each entry is {"player_id": int, "settlement_name": String, "item_type": String, "item_id": String, "item_name": String}.
var pending_productions: Array = []

# Transient city-growth records produced by TurnEngine._settlement_growth during
# a player step, drained by SimFacade into notifications. Not serialized.
# Each entry is {"player_id": int, "settlement_name": String, "population": int}.
var pending_growth: Array = []

# Auto-incrementing IDs
var _next_unit_id: int = 1
var _next_settlement_id: int = 1
var _next_alliance_id: int = 1
var _next_player_id: int = 1
var _next_trade_id: int = 1

func next_unit_id() -> int:
	var id: int = _next_unit_id
	_next_unit_id += 1
	return id

func next_settlement_id() -> int:
	var id: int = _next_settlement_id
	_next_settlement_id += 1
	return id

func next_alliance_id() -> int:
	var id: int = _next_alliance_id
	_next_alliance_id += 1
	return id

func next_player_id() -> int:
	var id: int = _next_player_id
	_next_player_id += 1
	return id

func next_trade_id() -> int:
	var id: int = _next_trade_id
	_next_trade_id += 1
	return id

# ── Lookups ───────────────────────────────────────────────────────────────────

func get_player(player_id: int) -> Player:
	for p in players:
		if p.id == player_id:
			return p
	return null

func get_settlement(settlement_id: int) -> Settlement:
	for s in settlements:
		if s.id == settlement_id:
			return s
	return null

func get_settlement_at(x: int, y: int) -> Settlement:
	for s in settlements:
		if s.x == x and s.y == y:
			return s
	return null

func get_unit(unit_id: int) -> Unit:
	for u in units:
		if u.id == unit_id:
			return u
	return null

func get_alliance(alliance_id: int) -> Alliance:
	for a in alliances:
		if a.id == alliance_id:
			return a
	return null

func get_player_alliance(player_id: int) -> Alliance:
	var p: Player = get_player(player_id)
	if p == null:
		return null
	return get_alliance(p.alliance_id)

func are_at_war(player_a_id: int, player_b_id: int) -> bool:
	var a: Player = get_player(player_a_id)
	var b: Player = get_player(player_b_id)
	if a == null or b == null:
		return false
	if a.alliance_id == b.alliance_id:
		return false
	var aa: Alliance = get_alliance(a.alliance_id)
	if aa == null:
		return false
	return aa.is_at_war_with(b.alliance_id)

# ── Serialization ─────────────────────────────────────────────────────────────

func serialize() -> Dictionary:
	var player_data := []
	for p in players:
		player_data.append(p.serialize())
	var settlement_data := []
	for s in settlements:
		settlement_data.append(s.serialize())
	var unit_data := []
	for u in units:
		unit_data.append(u.serialize())
	var alliance_data := []
	for a in alliances:
		alliance_data.append(a.serialize())

	return {
		"rng_state": rng.get_state(),
		"map": map.serialize(),
		"players": player_data,
		"settlements": settlement_data,
		"units": unit_data,
		"alliances": alliance_data,
		"turn_number": turn_number,
		"max_turns": max_turns,
		"pace_id": pace_id,
		"difficulty_id": difficulty_id,
		"current_player_id": current_player_id,
		"enabled_win_conditions": enabled_win_conditions.duplicate(),
		"winning_alliance_id": winning_alliance_id,
		"wild_aggressive": wild_aggressive,
		"permanent_alliances": permanent_alliances,
		"founded_beliefs": founded_beliefs.duplicate(),
		"founded_econ_orgs": founded_econ_orgs.duplicate(),
		"endgame_project_stages": endgame_project_stages.duplicate(),
		"diplomatic_votes": diplomatic_votes.duplicate(),
		"assembly": assembly.duplicate(true),
		"_next_unit_id": _next_unit_id,
		"_next_settlement_id": _next_settlement_id,
		"_next_alliance_id": _next_alliance_id,
		"_next_player_id": _next_player_id,
		"_next_trade_id": _next_trade_id
	}

static func deserialize(d: Dictionary, db_ref):
	var gs = load("res://src/sim/game_state.gd").new()
	gs.db = db_ref
	gs.rng = RNG.new()
	gs.rng.restore_state(d["rng_state"])
	gs.map = WorldMap.deserialize(d["map"])
	for pd in d["players"]:
		gs.players.append(Player.deserialize(pd))
	for sd in d["settlements"]:
		gs.settlements.append(Settlement.deserialize(sd))
	for ud in d["units"]:
		gs.units.append(Unit.deserialize(ud))
	for ad in d["alliances"]:
		gs.alliances.append(Alliance.deserialize(ad))
	gs.turn_number = int(d.get("turn_number", 0))
	gs.max_turns = int(d.get("max_turns", 500))
	gs.pace_id = str(d.get("pace_id", "normal"))
	gs.difficulty_id = str(d.get("difficulty_id", "prince"))
	gs.current_player_id = int(d.get("current_player_id", -1))
	gs.enabled_win_conditions = d.get("enabled_win_conditions", []).duplicate()
	gs.winning_alliance_id = int(d.get("winning_alliance_id", -1))
	gs.wild_aggressive = bool(d.get("wild_aggressive", false))
	gs.permanent_alliances = bool(d.get("permanent_alliances", false))
	gs.founded_beliefs = d.get("founded_beliefs", {}).duplicate()
	gs.founded_econ_orgs = d.get("founded_econ_orgs", {}).duplicate()
	gs.endgame_project_stages = d.get("endgame_project_stages", {}).duplicate()
	gs.diplomatic_votes = d.get("diplomatic_votes", {}).duplicate()
	gs.assembly = d.get("assembly", {}).duplicate(true)
	gs._next_unit_id = int(d.get("_next_unit_id", 1))
	gs._next_settlement_id = int(d.get("_next_settlement_id", 1))
	gs._next_alliance_id = int(d.get("_next_alliance_id", 1))
	gs._next_player_id = int(d.get("_next_player_id", 1))
	gs._next_trade_id = int(d.get("_next_trade_id", 1))
	return gs
