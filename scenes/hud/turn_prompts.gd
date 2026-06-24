# Humanish — a turn-based 4X strategy game.
# Copyright (C) 2026 thalia-at-lesbos
# SPDX-License-Identifier: GPL-3.0-or-later
#
# This program is free software: you can redistribute it and/or modify it
# under the terms of the GNU General Public License as published by the Free
# Software Foundation, either version 3 of the License, or (at your option)
# any later version. See the LICENSE file for the full text and warranty
# disclaimer.

extends Node

# Start-of-turn "what now?" prompts for the local human player. When a turn opens
# it walks a short to-do list and pops the relevant chooser so nothing is silently
# wasted:
#   0. a mandatory random-event / quest-reward choice is owed → raise the event
#      choice popup (the decision blocks End Turn, so it comes first).
#   1. no research selected  → open the tech chooser (issue: ask what to research)
#   2. a city with an empty production queue → open its city screen (ask what to
#      produce), one idle city at a time.
# It chains via each chooser's `closed` signal: resolve any pending choice, pick
# research, then get walked through each idle city. The research/city items are
# offered at most once per turn so cancelling never re-opens the same prompt in a
# loop; the event step is unguarded and re-checked each pass, so it keeps surfacing
# while a choice remains owed (resolving one removes it from the pending queue).
#
# Like the rest of the scene layer this is a pure SimFacade *client* — it only
# reads get_state() and opens existing screens; it never mutates sim state itself.
# Wired only in solo/hotseat play (remote turns are server-driven).

var _facade
var _tech_chooser
var _city_screen
var _event_screen

# Re-armed each new turn (keyed by turn+player) so a prompt is offered once.
var _turn_key: String = ""
var _research_offered: bool = false
var _cities_offered: Dictionary = {}   # settlement_id -> true
# True only while we are actively driving a prompt chain, so closing a screen the
# player opened themselves never kicks off the chain.
var _chaining: bool = false

func init(facade, tech_chooser, city_screen, event_screen = null) -> void:
	_facade = facade
	_tech_chooser = tech_chooser
	_city_screen = city_screen
	_event_screen = event_screen
	if _facade != null:
		_facade.connect("player_turn_started", self, "_on_turn_started")
	if _tech_chooser != null:
		_tech_chooser.connect("closed", self, "_on_chooser_closed")
	if _city_screen != null:
		_city_screen.connect("closed", self, "_on_chooser_closed")
	if _event_screen != null:
		_event_screen.connect("closed", self, "_on_chooser_closed")

func _on_turn_started(player_id: int) -> void:
	if _facade == null:
		return
	var gs = _facade.get_state()
	if gs == null or gs.winning_alliance_id >= 0:
		return
	var p = gs.get_player(player_id)
	if p == null or p.is_ai or player_id != gs.current_player_id:
		return
	# Defer so the command that opened the turn finishes unwinding first (and any
	# pass-device overlay is in place) before we raise a chooser behind it.
	call_deferred("_begin", player_id)

func _begin(player_id: int) -> void:
	if _facade == null:
		return
	var gs = _facade.get_state()
	if gs == null or player_id != gs.current_player_id:
		return
	# Re-arm the once-per-turn guards for this (turn, player).
	var key: String = str(gs.turn_number) + ":" + str(player_id)
	if key != _turn_key:
		_turn_key = key
		_research_offered = false
		_cities_offered = {}
	_chaining = true
	_advance(player_id)

# Open the next thing that needs the player's attention, or end the chain.
func _advance(player_id: int) -> void:
	if _facade == null:
		return
	var gs = _facade.get_state()
	if gs == null or player_id != gs.current_player_id or gs.winning_alliance_id >= 0:
		_chaining = false
		return
	var p = gs.get_player(player_id)
	if p == null or p.is_ai:
		_chaining = false
		return
	# 0. A mandatory event / quest-reward choice owed by this player (§9, §4). Not
	# guarded per-turn: re-checked each pass so every queued choice is surfaced, and
	# it must be answered before End Turn is allowed.
	if _event_screen != null and _event_screen.has_method("show_event"):
		var descriptor: Dictionary = _build_event_descriptor(player_id)
		if not descriptor.empty():
			_event_screen.show_event(descriptor)
			return
	# 0.5 A freshly-armed quest's information popup (§4) — purely informational, so it
	# is acknowledged on show (removed from the queue) to appear exactly once.
	if _event_screen != null and _event_screen.has_method("show_info") \
			and _facade.has_method("get_pending_quest_info"):
		var info: Dictionary = _facade.get_pending_quest_info(player_id)
		if not info.empty():
			_facade.ack_quest_info(player_id, str(info.get("quest_id", "")))
			_event_screen.show_info(info)
			return
	# 1. Research.
	if not _research_offered and p.current_research_id == "" and _has_researchable(p):
		_research_offered = true
		if _tech_chooser != null and _tech_chooser.has_method("show_screen"):
			_tech_chooser.show_screen()
			return
	# 2. Idle cities (empty production queue), one at a time.
	var idle_id: int = _next_idle_city(gs, player_id)
	if idle_id >= 0:
		_cities_offered[idle_id] = true
		if _city_screen != null and _city_screen.has_method("show_city"):
			_city_screen.show_city(idle_id)
			return
	# Nothing left to ask.
	_chaining = false

func _on_chooser_closed() -> void:
	if not _chaining or _facade == null:
		return
	var gs = _facade.get_state()
	if gs == null:
		return
	_advance(gs.current_player_id)

# Build the popup descriptor for a player's first unresolved event choice, or {}
# when none is owed. The pending entry carries the pre-rolled branches; flavour
# name/text come baked in for a quest reward, else from the event definition.
func _build_event_descriptor(player_id: int) -> Dictionary:
	if _facade == null or not _facade.has_method("get_pending_event"):
		return {}
	var pe: Dictionary = _facade.get_pending_event(player_id)
	if pe.empty():
		return {}
	var choices: Array = []
	for ch in pe.get("resolved_choices", []):
		choices.append({"id": str(ch.get("id", "")), "text": str(ch.get("text", ""))})
	if choices.empty():
		return {}
	var eid: String = str(pe.get("event_id", ""))
	var nm: String = str(pe.get("name", ""))
	var txt: String = str(pe.get("text", ""))
	if nm == "" and _facade._db != null:
		var ev: Dictionary = _facade._db.get_event(eid)
		nm = str(ev.get("name", eid))
		txt = str(ev.get("text", ""))
	return {"event_id": eid, "name": nm, "text": txt, "choices": choices}

# First of the player's settlements with no production queued that has not already
# been offered this turn.
func _next_idle_city(gs, player_id: int) -> int:
	for s in gs.settlements:
		if s.owner_player_id != player_id:
			continue
		if not s.production_queue.empty():
			continue
		if s.produce_nothing:
			continue
		if _cities_offered.has(s.id):
			continue
		return s.id
	return -1

# True if the player has at least one technology they could research right now, so
# we never raise an empty tech chooser at the end of the tree.
func _has_researchable(p) -> bool:
	if _facade == null or _facade._db == null:
		return false
	for tech_id in _facade._db.technologies:
		if Research.can_research(tech_id, p, _facade._db):
			return true
	return false
