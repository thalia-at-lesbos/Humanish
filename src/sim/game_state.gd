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

# §9/§4 setting (new-game menu): when false, the whole random-event AND multi-turn
# quest system is switched off — no rosters are rolled and both the player-event and
# quest phases are skipped. On by default.
var events_enabled: bool = true

# §11 Global warming: a running count of every nuclear explosion that has ever
# occurred (ICBM, tactical nuke, and Nuclear Plant meltdown). Feeds GW_VALUE in
# GlobalWarming.tick(); incremented by Nuclear.detonate()/meltdown_tick().
var nukes_exploded: int = 0

# Founded beliefs and econ orgs (globally tracked)
var founded_beliefs: Dictionary = {}   # belief_id -> founder player_id
var founded_econ_orgs: Dictionary = {} # org_id -> founder player_id

# Spaceship parts completed per alliance, tallied PER TYPE (§15.16 / M4):
# alliance_id -> {project_id: count}. Each type caps at its `count_needed`
# (duplicates of a filled type no longer advance the race). Replaces the old
# flat per-alliance stage count (alliance_id -> int); deserialize migrates.
var endgame_project_parts: Dictionary = {}  # alliance_id -> {project_id: int}

# Spaceship arrival countdowns in flight (§15.16): alliance_id -> turns left.
# Set when an alliance reaches one of every part type; ticked by WinConditions;
# erased on arrival (roll), on a failed arrival, or when the capital is lost.
var spaceship_countdown: Dictionary = {}  # alliance_id -> int

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

# Per-game random-event roster (§9): the event ids whose `active` inclusion roll
# succeeded at game setup, so they may occur this game. Rolled once from gs.rng in
# fixed event-id order (Events.roll_active_events) and serialized, so the roster is
# stable across save/load and on the determinism gate. An empty roster means "not
# rolled yet" — Events treats it as "all events eligible" only before setup runs.
var active_event_ids: Array = []

# Random-event choices a human still owes (§9): each {event_id, player_id,
# trigger_id}. The event fired but its branch is unresolved; the facade raises a
# CHOOSE_EVENT popup at the player's turn start and clears the entry on resolve.
# Serialized so a pending choice survives save/load (deserialize coerces player_id).
var pending_event_choices: Array = []

# Multi-turn quests in progress (§4): each {quest_id, player_id, start_turn, progress,
# snapshot}. `progress` is a cached aim count; `snapshot` captures a baseline the aim/
# constraint diffs against (e.g. settlement ids that already held a structure at arming,
# or the state religion held at arming). Managed by the Quests module in a player-step
# phase. Serialized so a quest in progress survives save/load and stays on the
# determinism gate; deserialize coerces player_id/start_turn/progress and the int keys/
# values inside snapshot back to int (the JSON float/string-key gotcha).
var active_quests: Array = []

# Per-game quest roster (§4): the quest ids whose `active` inclusion roll succeeded at
# game setup, so they may be armed this game. Rolled once from gs.rng in fixed quest-id
# order (Quests.roll_active_quests) and serialized, so the roster is stable across
# save/load. An empty roster means "not rolled yet" — Quests treats every quest as in.
var active_quest_ids: Array = []

# Transient quest-lifecycle descriptors (armed / completed / reward-pending / failed)
# produced by the §4 quest step, drained by SimFacade into notifications + the
# quest_event signal. Not serialized: it never survives past the turn that produced it
# (active_quests / quests_completed carry the persistent state).
var pending_quest_events: Array = []  # [{kind, player_id, quest_id, ...}]

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

# The last §7 denial reason each proposer received from each rejector:
# proposer_player_id -> {rejector_player_id: {"reason": String, "turn": int}}.
# Written by REJECT_TRADE when the answer carries a reason id (an AI refusal via
# Diplomacy.evaluate_deal); read by the diplomacy screen so a human sees why the
# last offer was turned down. Serialized; both key levels are int player ids and
# are coerced back on load (the JSON string-key gotcha).
var deal_denials: Dictionary = {}

# Active bilateral open-borders agreements (§7). Each entry is an unordered pair of
# player IDs {"a": int, "b": int} (canonicalized a < b) granting each side passage
# through the other's cultural borders. Recorded on trade acceptance (a proposal
# carrying open_borders), gated by the open_borders_tech, and torn up when the two
# players go to war (declare-war purges any matching pair). Serialized; the
# deserialize path coerces a/b back to int (the JSON float-key gotcha).
var open_borders: Array = []

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

# Persistent per-player fog-of-war memory (§fog). For each player that needs fog
# (a non-AI / human player — AIs read full state and never render fog), records
# the set of tiles ever seen plus a compact last-seen snapshot of each, so revealed
# fog and remembered terrain survive save/load. Keyed by player_id (int) → {"x,y" →
# snapshot}. Maintained deterministically in the turn pipeline (SeenMemory.commit_
# visible from TurnEngine.player_step), read by the presentation layer through
# SimFacade.get_seen_memory. Serialized; deserialize coerces the int player-id keys
# and per-snapshot int fields back to int (the JSON float/string-key gotcha) via
# SeenMemory.deserialize.
var seen_memory: Dictionary = {}

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

# ── Open borders (§7) ──────────────────────────────────────────────────────────

# Whether players a and b have an active open-borders agreement (order-independent).
# A player is always considered to have open borders with itself and with members of
# the same alliance (the canonical "friendly passage" set is broader than the signed
# agreement). Pure read of gs.open_borders for the signed-agreement case.
func has_open_borders(player_a_id: int, player_b_id: int) -> bool:
	if player_a_id == player_b_id:
		return true
	for ob in open_borders:
		var x: int = int(ob.get("a", -1))
		var y: int = int(ob.get("b", -1))
		if (x == player_a_id and y == player_b_id) or (x == player_b_id and y == player_a_id):
			return true
	return false

# Record an open-borders agreement between two players (idempotent, canonicalized).
func add_open_borders(player_a_id: int, player_b_id: int) -> void:
	if player_a_id == player_b_id or has_open_borders(player_a_id, player_b_id):
		return
	var lo: int = player_a_id if player_a_id < player_b_id else player_b_id
	var hi: int = player_b_id if player_a_id < player_b_id else player_a_id
	open_borders.append({"a": lo, "b": hi})

# Remove any open-borders agreement involving the given pair (used on war / cancel).
# Returns true if an agreement was removed.
func remove_open_borders(player_a_id: int, player_b_id: int) -> bool:
	var removed: bool = false
	for i in range(open_borders.size() - 1, -1, -1):
		var ob: Dictionary = open_borders[i]
		var x: int = int(ob.get("a", -1))
		var y: int = int(ob.get("b", -1))
		if (x == player_a_id and y == player_b_id) or (x == player_b_id and y == player_a_id):
			open_borders.remove(i)
			removed = true
	return removed

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
		"events_enabled": events_enabled,
		"nukes_exploded": nukes_exploded,
		"founded_beliefs": founded_beliefs.duplicate(),
		"founded_econ_orgs": founded_econ_orgs.duplicate(),
		"endgame_project_parts": endgame_project_parts.duplicate(true),
		"spaceship_countdown": spaceship_countdown.duplicate(),
		"assembly": assembly.duplicate(true),
		"deals": deals.duplicate(true),
		"deal_denials": deal_denials.duplicate(true),
		"open_borders": open_borders.duplicate(true),
		"seen_memory": SeenMemory.serialize(seen_memory),
		"active_events": active_events.duplicate(true),
		"active_event_ids": active_event_ids.duplicate(),
		"pending_event_choices": pending_event_choices.duplicate(true),
		"active_quests": active_quests.duplicate(true),
		"active_quest_ids": active_quest_ids.duplicate(),
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
	gs.events_enabled = bool(d.get("events_enabled", true))
	gs.nukes_exploded = int(d.get("nukes_exploded", 0))
	gs.founded_beliefs = d.get("founded_beliefs", {}).duplicate()
	gs.founded_econ_orgs = d.get("founded_econ_orgs", {}).duplicate()
	# Spaceship part tallies (§15.16 / M4): alliance keys and counts come back
	# from JSON as strings/floats — coerce both to int (the recurring gotcha).
	gs.endgame_project_parts = {}
	var parts_src: Dictionary = d.get("endgame_project_parts", {})
	for ak in parts_src:
		var tally: Dictionary = {}
		for pk in parts_src[ak]:
			tally[str(pk)] = int(parts_src[ak][pk])
		gs.endgame_project_parts[int(ak)] = tally
	# Migration from the pre-M4 flat stage count (alliance_id -> int): k stages
	# become one part each of the first k types in `stage` order, so a resumed
	# mid-race save keeps (approximately) its progress.
	var stages_src: Dictionary = d.get("endgame_project_stages", {})
	for ak in stages_src:
		var aid: int = int(ak)
		if gs.endgame_project_parts.has(aid):
			continue
		var ids: Array = Projects.endgame_ids(db_ref)
		var k: int = int(stages_src[ak])
		var tally2: Dictionary = {}
		for i in range(k if k < ids.size() else ids.size()):
			tally2[str(ids[i])] = 1
		gs.endgame_project_parts[aid] = tally2
	# Arrival countdowns: int-coerce the alliance keys and the turns.
	gs.spaceship_countdown = {}
	var cd_src: Dictionary = d.get("spaceship_countdown", {})
	for ak in cd_src:
		gs.spaceship_countdown[int(ak)] = int(cd_src[ak])
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
	# Last deal denials (§7 denial reasons): both dictionary levels are keyed by int
	# player ids, which JSON.parse returns as strings; coerce both back so the
	# diplomacy screen's int-id lookups still match after a load.
	gs.deal_denials = {}
	var dd_src: Dictionary = d.get("deal_denials", {})
	for pk in dd_src:
		var inner: Dictionary = {}
		for rk in dd_src[pk]:
			var rec: Dictionary = dd_src[pk][rk]
			inner[int(rk)] = {"reason": str(rec.get("reason", "")),
				"turn": int(rec.get("turn", 0))}
		gs.deal_denials[int(pk)] = inner
	# Open-borders agreements (§7): each is a {a,b} player-id pair. JSON.parse yields
	# floats for the ids; coerce back to int so post-load passage lookups still match.
	gs.open_borders = []
	for ob in d.get("open_borders", []):
		gs.open_borders.append({"a": int(ob.get("a", -1)), "b": int(ob.get("b", -1))})
	# Persistent fog memory (§fog): JSON makes the player-id keys strings and the
	# per-snapshot owner/settlement ids floats; SeenMemory.deserialize coerces both
	# back to int so post-load lookups by int player id and border colour match.
	gs.seen_memory = SeenMemory.deserialize(d.get("seen_memory", {}))
	# Timed events & pending human choices: coerce JSON-loaded numeric fields back to
	# int (the recurring float/string-key gotcha) so post-load lookups still match.
	gs.active_events = []
	for inst in d.get("active_events", []):
		gs.active_events.append({
			"event_id": str(inst.get("event_id", "")),
			"player_id": int(inst.get("player_id", -1)),
			"turns_left": int(inst.get("turns_left", 0))
		})
	gs.active_event_ids = []
	for eid in d.get("active_event_ids", []):
		gs.active_event_ids.append(str(eid))
	gs.pending_event_choices = []
	for pc in d.get("pending_event_choices", []):
		gs.pending_event_choices.append({
			"event_id": str(pc.get("event_id", "")),
			"player_id": int(pc.get("player_id", -1)),
			"trigger_id": str(pc.get("trigger_id", "")),
			# Pre-rolled concrete branch effects baked at fire time (§9): each
			# {id, text, effects:[...]}. Carried verbatim — effect amounts are coerced
			# to int at apply time in Events._apply_effect, so the JSON float roundtrip
			# is harmless here.
			"resolved_choices": pc.get("resolved_choices", []).duplicate(true)
		})
	# Multi-turn quests in progress (§4): coerce the numeric envelope fields back to int,
	# and coerce every key AND value inside `snapshot` back to int — JSON.parse makes the
	# int settlement-id keys strings and the int values floats, so a post-load aim/
	# constraint diff (e.g. "this city already held the structure") would silently miss
	# without coercion (the JSON float/string-key gotcha; would break the determinism
	# gate). The STATE_RELIGION_KEY sentinel snapshot value is a string and survives the
	# roundtrip; only positive settlement-id entries hold int values.
	gs.active_quests = []
	for q in d.get("active_quests", []):
		var snap_in: Dictionary = q.get("snapshot", {})
		var snap_out: Dictionary = {}
		for k in snap_in:
			var v = snap_in[k]
			snap_out[int(k)] = (str(v) if typeof(v) == TYPE_STRING else int(v))
		gs.active_quests.append({
			"quest_id": str(q.get("quest_id", "")),
			"player_id": int(q.get("player_id", -1)),
			"start_turn": int(q.get("start_turn", 0)),
			"progress": int(q.get("progress", 0)),
			"snapshot": snap_out
		})
	gs.active_quest_ids = []
	for qid in d.get("active_quest_ids", []):
		gs.active_quest_ids.append(str(qid))
	gs._next_unit_id = int(d.get("_next_unit_id", 1))
	gs._next_settlement_id = int(d.get("_next_settlement_id", 1))
	gs._next_alliance_id = int(d.get("_next_alliance_id", 1))
	gs._next_player_id = int(d.get("_next_player_id", 1))
	gs._next_trade_id = int(d.get("_next_trade_id", 1))
	return gs
