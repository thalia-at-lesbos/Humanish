# Humanish — a turn-based 4X strategy game.
# Copyright (C) 2026 thalia-at-lesbos
# SPDX-License-Identifier: GPL-3.0-or-later
#
# This program is free software: you can redistribute it and/or modify it
# under the terms of the GNU General Public License as published by the Free
# Software Foundation, either version 3 of the License, or (at your option)
# any later version. See the LICENSE file for the full text and warranty
# disclaimer.

class_name Alliance
extends Reference

var id: int = 0
var member_player_ids: Array = []  # Array of player IDs

# War: set of alliance IDs we are at war with
var at_war_with: Array = []

# Contacts: set of alliance IDs we have met
var contacts: Array = []

# Subordination
var is_subordinate_to: int = -1  # alliance_id, -1 = independent
var tributaries: Array = []      # alliance IDs that are our tributaries

# Shared research: additional research points accumulated by alliance members
var shared_research_store: int = 0

# War fatigue per war (alliance_id -> int anger points accumulated)
var war_fatigue: Dictionary = {}

# Forced wars (§15.8): set of alliance IDs whose war against us was not our
# choice (they declared on us, we were dragged in as a vassal, or we were
# nuked into it). War weariness from such a war accrues at the reference
# forced-war modifier (−50%). Cleared when the war ends.
var forced_wars: Array = []

# Permanent alliances: set of alliance IDs with which a permanent alliance
# has been formed (when the gs.permanent_alliances rule is active).
var permanent_allies: Array = []

# Active trade offers from this alliance: Array of trade Dictionaries
var pending_trades: Array = []

func is_at_war_with(other_alliance_id: int) -> bool:
	return other_alliance_id in at_war_with

func has_contact_with(other_alliance_id: int) -> bool:
	return other_alliance_id in contacts

func add_member(player_id: int) -> void:
	if not player_id in member_player_ids:
		member_player_ids.append(player_id)

func serialize() -> Dictionary:
	return {
		"id": id,
		"member_player_ids": member_player_ids.duplicate(),
		"at_war_with": at_war_with.duplicate(),
		"contacts": contacts.duplicate(),
		"is_subordinate_to": is_subordinate_to,
		"tributaries": tributaries.duplicate(),
		"shared_research_store": shared_research_store,
		"war_fatigue": war_fatigue.duplicate(),
		"forced_wars": forced_wars.duplicate(),
		"pending_trades": pending_trades.duplicate(true),
		"permanent_allies": permanent_allies.duplicate()
	}

static func deserialize(d: Dictionary):
	var a = load("res://src/sim/alliance.gd").new()
	a.id = int(d["id"])
	# Every array below holds player/alliance IDs (ints). JSON.parse yields floats
	# for them, and a float key (2.0) is a *different* Dictionary key from the int
	# key (2) it is later compared against — which silently breaks membership tests
	# and intel/permanent-ally lookups after a load. Coerce them back to int.
	a.member_player_ids = _to_int_array(d.get("member_player_ids", []))
	a.at_war_with = _to_int_array(d.get("at_war_with", []))
	a.contacts = _to_int_array(d.get("contacts", []))
	a.is_subordinate_to = int(d.get("is_subordinate_to", -1))
	a.tributaries = _to_int_array(d.get("tributaries", []))
	a.shared_research_store = int(d.get("shared_research_store", 0))
	# war_fatigue is alliance_id(int) -> int; JSON keys come back as strings.
	a.war_fatigue = {}
	var wf: Dictionary = d.get("war_fatigue", {})
	for k in wf:
		a.war_fatigue[int(k)] = int(wf[k])
	a.forced_wars = _to_int_array(d.get("forced_wars", []))
	a.pending_trades = d.get("pending_trades", []).duplicate(true)
	a.permanent_allies = _to_int_array(d.get("permanent_allies", []))
	return a

static func _to_int_array(src: Array) -> Array:
	var out: Array = []
	for v in src:
		out.append(int(v))
	return out
