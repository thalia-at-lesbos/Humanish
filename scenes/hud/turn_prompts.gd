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
#   1. no research selected  → open the tech chooser (issue: ask what to research)
#   2. a city with an empty production queue → open its city screen (ask what to
#      produce), one idle city at a time.
# It chains via each chooser's `closed` signal: pick research, then get walked
# through each idle city. Each item is offered at most once per turn so cancelling
# never re-opens the same prompt in a loop.
#
# Like the rest of the scene layer this is a pure SimFacade *client* — it only
# reads get_state() and opens existing screens; it never mutates sim state itself.
# Wired only in solo/hotseat play (remote turns are server-driven).

var _facade
var _tech_chooser
var _city_screen

# Re-armed each new turn (keyed by turn+player) so a prompt is offered once.
var _turn_key: String = ""
var _research_offered: bool = false
var _cities_offered: Dictionary = {}   # settlement_id -> true
# True only while we are actively driving a prompt chain, so closing a screen the
# player opened themselves never kicks off the chain.
var _chaining: bool = false

func init(facade, tech_chooser, city_screen) -> void:
	_facade = facade
	_tech_chooser = tech_chooser
	_city_screen = city_screen
	if _facade != null:
		_facade.connect("player_turn_started", self, "_on_turn_started")
	if _tech_chooser != null:
		_tech_chooser.connect("closed", self, "_on_chooser_closed")
	if _city_screen != null:
		_city_screen.connect("closed", self, "_on_chooser_closed")

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
