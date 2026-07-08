# Humanish — a turn-based 4X strategy game.
# Copyright (C) 2026 thalia-at-lesbos
# SPDX-License-Identifier: GPL-3.0-or-later
#
# This program is free software: you can redistribute it and/or modify it
# under the terms of the GNU General Public License as published by the Free
# Software Foundation, either version 3 of the License, or (at your option)
# any later version. See the LICENSE file for the full text and warranty
# disclaimer.

class_name UnitPrereqs

# Compound unit prerequisites (game-rules §15.12) — the one canonical reader of a
# unit's `tech_required` / `resource_required` fields, shared by the sim gates
# (draft, upgrade), the AI build chooser, and the UI offer lists so a unit is
# never buildable in one place and unbuildable in another.
#
# `tech_required` accepts three forms:
#   null / ""            — no tech needed
#   "guilds"             — single tech (legacy form)
#   ["guilds", "horseback_riding"] — list, ALL required (AND)
#
# `resource_required` accepts three forms:
#   null / ""            — no resource needed
#   "iron"               — single resource (legacy form; required)
#   { "all": [...], "any": [...] } — every `all` entry required, plus at least
#     one of the `any` list (either key may be absent or empty)
#
# Pure static, no state, integer/string data only. The *availability* side —
# which resources a player has connected — is computed by
# EconOrgs.accessible_resources(game_state, player_id); callers pass that
# set (Dictionary-as-set) into resource_ok so loops over many unit types
# compute it once.

# Normalized list of required tech ids (empty when the unit needs none).
static func tech_list(req) -> Array:
	if req == null:
		return []
	if req is Array:
		var out: Array = []
		for t in req:
			if str(t) != "":
				out.append(str(t))
		return out
	if str(req) == "":
		return []
	return [str(req)]

# True when `player` has researched every required tech (list form = AND).
# A null player (wild forces / headless spawn tables) only passes tech-free units.
static func tech_ok(req, player) -> bool:
	var techs: Array = tech_list(req)
	if techs.empty():
		return true
	if player == null:
		return false
	for t in techs:
		if not player.has_tech(t):
			return false
	return true

# Normalize `resource_required` to { "all": [...], "any": [...] }.
static func resource_spec(req) -> Dictionary:
	var spec: Dictionary = {"all": [], "any": []}
	if req == null:
		return spec
	if req is Dictionary:
		for r in req.get("all", []):
			if str(r) != "":
				spec["all"].append(str(r))
		for r in req.get("any", []):
			if str(r) != "":
				spec["any"].append(str(r))
		return spec
	if str(req) != "":
		spec["all"].append(str(req))
	return spec

# Every resource id the requirement references (for validation / display).
static func resource_ids(req) -> Array:
	var spec: Dictionary = resource_spec(req)
	var out: Array = []
	for r in spec["all"]:
		out.append(r)
	for r in spec["any"]:
		if not (r in out):
			out.append(r)
	return out

# True when the accessible-resource set `have` (Dictionary-as-set of resource ids,
# from EconOrgs.accessible_resources) satisfies the requirement: every `all`
# entry present, plus at least one `any` entry when the `any` list is non-empty.
static func resource_ok(req, have: Dictionary) -> bool:
	var spec: Dictionary = resource_spec(req)
	for r in spec["all"]:
		if not have.has(r):
			return false
	var alternatives: Array = spec["any"]
	if alternatives.empty():
		return true
	for r in alternatives:
		if have.has(r):
			return true
	return false
