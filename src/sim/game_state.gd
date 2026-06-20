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

# Save format version. Bumped to 2 when the movement scale changed from 100 to
# MOVE_DENOMINATOR=60 (§5.2); deserialize migrates pre-2 saves' unit movement.
const SAVE_VERSION: int = 2

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
var world_size_id: String = "standard"  # feeds the §6.3 research cost chain
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

# Timed random events in progress (§9 lifecycle): each {event_id, player_id,
# turns_left}. Ticked down per owner each player step; the event's expire_effects
# apply when turns_left hits 0. Serialized so a persisting event survives save/load
# and stays on the determinism gate (deserialize coerces player_id/turns_left).
var active_events: Array = []

# Random-event choices a human still owes (§9): each {event_id, player_id,
# trigger_id}. The event fired but its branch is unresolved; the facade raises a
# CHOOSE_EVENT popup at the player's turn start and clears the entry on resolve.
# Serialized so a pending choice survives save/load (deserialize coerces player_id).
var pending_event_choices: Array = []

# Active persistent diplomatic deals (§7). A deal is an accepted agreement between
# two alliances bundling one-off items (delivered once on acceptance) and recurring
# per-turn items (delivered each whole-world step). It is cancellable once its
# minimum duration has elapsed. Each entry is a Dictionary:
#   {id, a_alliance, b_alliance, proposer_player_id, accepter_player_id,
#    recurring: {give:{...}, receive:{...}}, start_turn, min_duration}
# where give = proposer→accepter, receive = accepter→proposer. Serialized; the
# deserialize path coerces the int id/alliance/player fields (the recurring JSON-key
# gotcha). The transient cancellation/expiry notices ride pending_deal_events.
var deals: Array = []

# Transient deal lifecycle notices produced by the §7 deal step (delivered/expired/
# cancelled), drained by SimFacade into notifications + the deal_cancelled signal.
# Not serialized. Each entry is {"kind": String, "deal_id": int, ...}.
var pending_deal_events: Array = []

# Transient fired/expired event descriptors produced by the §9 event step, drained
# by SimFacade into notifications + the event_emitted signal. Not serialized.
var pending_events: Array = []

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

# Transient first-contact records produced by TurnEngine._ensure_mutual_contact
# the first time two players meet (§7), drained by SimFacade into notifications +
# the first_contact signal. Not serialized: contact established this world step is
# always drained before the turn ends, and Alliance.contacts carries the
# persistent met state.
# Each entry is {"player_id": int, "other_player_id": int}.
var pending_first_contacts: Array = []

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

# Transient worker-build completions produced by TurnEngine._advance_worker_build
# when a worker finishes constructing an improvement, drained by SimFacade into
# notifications. Not serialized (always empty between turns).
# Each entry is {"player_id": int, "improvement_id": String, "x": int, "y": int}.
var pending_improvements: Array = []

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
		"save_version": SAVE_VERSION,
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
		"world_size_id": world_size_id,
		"current_player_id": current_player_id,
		"enabled_win_conditions": enabled_win_conditions.duplicate(),
		"winning_alliance_id": winning_alliance_id,
		"wild_aggressive": wild_aggressive,
		"permanent_alliances": permanent_alliances,
		"founded_beliefs": founded_beliefs.duplicate(),
		"founded_econ_orgs": founded_econ_orgs.duplicate(),
		"endgame_project_stages": endgame_project_stages.duplicate(),
		"assembly": assembly.duplicate(true),
		"deals": deals.duplicate(true),
		"active_events": active_events.duplicate(true),
		"pending_event_choices": pending_event_choices.duplicate(true),
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
	# Migration: pre-2 saves stored movement on the old 100-unit scale; rescale to
	# the MOVE_DENOMINATOR=60 scale so resumed units move the right distance (§5.2).
	if int(d.get("save_version", 1)) < 2:
		for u in gs.units:
			u.movement_total = (u.movement_total * Fixed.MOVE_DENOMINATOR) / 100
			u.movement_left = (u.movement_left * Fixed.MOVE_DENOMINATOR) / 100
	for ad in d["alliances"]:
		gs.alliances.append(Alliance.deserialize(ad))
	gs.turn_number = int(d.get("turn_number", 0))
	gs.max_turns = int(d.get("max_turns", 500))
	gs.pace_id = str(d.get("pace_id", "normal"))
	gs.difficulty_id = str(d.get("difficulty_id", "prince"))
	gs.world_size_id = str(d.get("world_size_id", "standard"))
	gs.current_player_id = int(d.get("current_player_id", -1))
	gs.enabled_win_conditions = d.get("enabled_win_conditions", []).duplicate()
	gs.winning_alliance_id = int(d.get("winning_alliance_id", -1))
	gs.wild_aggressive = bool(d.get("wild_aggressive", false))
	gs.permanent_alliances = bool(d.get("permanent_alliances", false))
	gs.founded_beliefs = d.get("founded_beliefs", {}).duplicate()
	gs.founded_econ_orgs = d.get("founded_econ_orgs", {}).duplicate()
	gs.endgame_project_stages = d.get("endgame_project_stages", {}).duplicate()
	gs.assembly = d.get("assembly", {}).duplicate(true)
	# Active deals (§7): coerce the int id/alliance/player fields back to int so the
	# loaded keys match later lookups (the recurring JSON float/string-key gotcha).
	# The recurring give/receive item dicts hold gold (int) and tech-id/resource-id
	# arrays (strings) — strings survive the roundtrip, so only the numeric envelope
	# fields need coercion.
	gs.deals = []
	for dl in d.get("deals", []):
		gs.deals.append({
			"id": int(dl.get("id", 0)),
			"a_alliance": int(dl.get("a_alliance", -1)),
			"b_alliance": int(dl.get("b_alliance", -1)),
			"proposer_player_id": int(dl.get("proposer_player_id", -1)),
			"accepter_player_id": int(dl.get("accepter_player_id", -1)),
			"recurring": dl.get("recurring", {}).duplicate(true),
			"start_turn": int(dl.get("start_turn", 0)),
			"min_duration": int(dl.get("min_duration", 0))
		})
	# Timed events & pending human choices: coerce JSON-loaded numeric fields back to
	# int (the recurring float/string-key gotcha) so post-load lookups still match.
	gs.active_events = []
	for inst in d.get("active_events", []):
		gs.active_events.append({
			"event_id": str(inst.get("event_id", "")),
			"player_id": int(inst.get("player_id", -1)),
			"turns_left": int(inst.get("turns_left", 0))
		})
	gs.pending_event_choices = []
	for pc in d.get("pending_event_choices", []):
		gs.pending_event_choices.append({
			"event_id": str(pc.get("event_id", "")),
			"player_id": int(pc.get("player_id", -1)),
			"trigger_id": str(pc.get("trigger_id", ""))
		})
	gs._next_unit_id = int(d.get("_next_unit_id", 1))
	gs._next_settlement_id = int(d.get("_next_settlement_id", 1))
	gs._next_alliance_id = int(d.get("_next_alliance_id", 1))
	gs._next_player_id = int(d.get("_next_player_id", 1))
	gs._next_trade_id = int(d.get("_next_trade_id", 1))
	return gs
