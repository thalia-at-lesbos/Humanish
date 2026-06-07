# Humanish — a turn-based 4X strategy game.
# Copyright (C) 2026 thalia-at-lesbos
# SPDX-License-Identifier: GPL-3.0-or-later
#
# This program is free software: you can redistribute it and/or modify it
# under the terms of the GNU General Public License as published by the Free
# Software Foundation, either version 3 of the License, or (at your option)
# any later version. See the LICENSE file for the full text and warranty
# disclaimer.

class_name Commands

# Serializable player intents. All input (mouse/keyboard/touch) is eventually
# reduced to one of these before being passed to SimFacade.apply_command().

# Create a command Dictionary with the given type and parameters.
static func end_turn(player_id: int) -> Dictionary:
	return {"type": IDs.CommandType.END_TURN, "player_id": player_id}

static func move_stack(player_id: int, from_x: int, from_y: int,
		to_x: int, to_y: int, unit_ids: Array = []) -> Dictionary:
	# unit_ids: when non-empty, move only those units off the tile (so a single
	# member can leave a stack); when empty, the whole owned stack moves together.
	return {
		"type": IDs.CommandType.MOVE_STACK,
		"player_id": player_id,
		"from_x": from_x, "from_y": from_y,
		"to_x": to_x, "to_y": to_y,
		"unit_ids": unit_ids
	}

static func found_settlement(player_id: int, unit_id: int,
		name: String = "") -> Dictionary:
	return {
		"type": IDs.CommandType.FOUND_SETTLEMENT,
		"player_id": player_id,
		"unit_id": unit_id,
		"name": name
	}

static func set_sliders(player_id: int, finance: int, research: int,
		culture: int, intel: int) -> Dictionary:
	return {
		"type": IDs.CommandType.SET_SLIDERS,
		"player_id": player_id,
		"finance": finance, "research": research,
		"culture": culture, "intel": intel
	}

static func set_production(player_id: int, settlement_id: int,
		queue: Array) -> Dictionary:
	return {
		"type": IDs.CommandType.SET_PRODUCTION,
		"player_id": player_id,
		"settlement_id": settlement_id,
		"queue": queue.duplicate(true)
	}

static func set_research(player_id: int, tech_id: String) -> Dictionary:
	return {
		"type": IDs.CommandType.SET_RESEARCH,
		"player_id": player_id,
		"tech_id": tech_id
	}

static func set_policy(player_id: int, category: String,
		policy_id: String) -> Dictionary:
	return {
		"type": IDs.CommandType.SET_POLICY,
		"player_id": player_id,
		"category": category,
		"policy_id": policy_id
	}

static func set_state_religion(player_id: int, belief_id: String) -> Dictionary:
	return {
		"type": IDs.CommandType.SET_STATE_RELIGION,
		"player_id": player_id,
		"belief_id": belief_id
	}

static func declare_war(player_id: int,
		target_alliance_id: int) -> Dictionary:
	return {
		"type": IDs.CommandType.DECLARE_WAR,
		"player_id": player_id,
		"target_alliance_id": target_alliance_id
	}

static func make_peace(player_id: int, target_alliance_id: int) -> Dictionary:
	return {
		"type": IDs.CommandType.MAKE_PEACE,
		"player_id": player_id,
		"target_alliance_id": target_alliance_id
	}

static func rush_production(player_id: int, settlement_id: int,
		method: String) -> Dictionary:
	# method: "treasury" or "population"
	return {
		"type": IDs.CommandType.RUSH_PRODUCTION,
		"player_id": player_id,
		"settlement_id": settlement_id,
		"method": method
	}

static func build_improvement(player_id: int, unit_id: int,
		improvement_id: String) -> Dictionary:
	return {
		"type": IDs.CommandType.BUILD_IMPROVEMENT,
		"player_id": player_id,
		"unit_id": unit_id,
		"improvement_id": improvement_id
	}

# ── Unit commands (§3.2) ──────────────────────────────────────────────────────

static func unit_wake(player_id: int, unit_id: int) -> Dictionary:
	return {"type": IDs.CommandType.UNIT_WAKE, "player_id": player_id, "unit_id": unit_id}

static func unit_sleep(player_id: int, unit_id: int) -> Dictionary:
	return {"type": IDs.CommandType.UNIT_SLEEP, "player_id": player_id, "unit_id": unit_id}

static func unit_fortify(player_id: int, unit_id: int) -> Dictionary:
	return {"type": IDs.CommandType.UNIT_FORTIFY, "player_id": player_id, "unit_id": unit_id}

static func unit_cancel_orders(player_id: int, unit_id: int) -> Dictionary:
	return {"type": IDs.CommandType.UNIT_CANCEL_ORDERS, "player_id": player_id, "unit_id": unit_id}

static func unit_disband(player_id: int, unit_id: int) -> Dictionary:
	return {"type": IDs.CommandType.UNIT_DISBAND, "player_id": player_id, "unit_id": unit_id}

static func unit_upgrade(player_id: int, unit_id: int) -> Dictionary:
	return {"type": IDs.CommandType.UNIT_UPGRADE, "player_id": player_id, "unit_id": unit_id}

static func unit_promote(player_id: int, unit_id: int, promotion_id: String) -> Dictionary:
	return {
		"type": IDs.CommandType.UNIT_PROMOTE,
		"player_id": player_id,
		"unit_id": unit_id,
		"promotion_id": promotion_id
	}

static func unit_gift(player_id: int, unit_id: int, target_player_id: int) -> Dictionary:
	return {
		"type": IDs.CommandType.UNIT_GIFT,
		"player_id": player_id,
		"unit_id": unit_id,
		"target_player_id": target_player_id
	}

# ── Unit missions (§3.3) ──────────────────────────────────────────────────────

static func mission_move_to(player_id: int, unit_id: int,
		target_x: int, target_y: int) -> Dictionary:
	return {
		"type": IDs.CommandType.MISSION_MOVE_TO,
		"player_id": player_id,
		"unit_id": unit_id,
		"target_x": target_x, "target_y": target_y
	}

static func mission_build_road(player_id: int, unit_id: int) -> Dictionary:
	return {"type": IDs.CommandType.MISSION_BUILD_ROAD, "player_id": player_id, "unit_id": unit_id}

static func mission_skip_turn(player_id: int, unit_id: int) -> Dictionary:
	return {"type": IDs.CommandType.MISSION_SKIP_TURN, "player_id": player_id, "unit_id": unit_id}

static func mission_pillage(player_id: int, unit_id: int) -> Dictionary:
	return {"type": IDs.CommandType.MISSION_PILLAGE, "player_id": player_id, "unit_id": unit_id}

static func mission_bombard(player_id: int, unit_id: int,
		target_x: int, target_y: int) -> Dictionary:
	return {
		"type": IDs.CommandType.MISSION_BOMBARD,
		"player_id": player_id,
		"unit_id": unit_id,
		"target_x": target_x, "target_y": target_y
	}

static func mission_airlift(player_id: int, unit_id: int,
		target_x: int, target_y: int) -> Dictionary:
	return {
		"type": IDs.CommandType.MISSION_AIRLIFT,
		"player_id": player_id,
		"unit_id": unit_id,
		"target_x": target_x, "target_y": target_y
	}

static func mission_sentry(player_id: int, unit_id: int) -> Dictionary:
	return {"type": IDs.CommandType.MISSION_SENTRY, "player_id": player_id, "unit_id": unit_id}

static func mission_heal(player_id: int, unit_id: int) -> Dictionary:
	return {"type": IDs.CommandType.MISSION_HEAL, "player_id": player_id, "unit_id": unit_id}

static func mission_move_to_unit(player_id: int, unit_id: int,
		target_unit_id: int) -> Dictionary:
	return {
		"type": IDs.CommandType.MISSION_MOVE_TO_UNIT,
		"player_id": player_id,
		"unit_id": unit_id,
		"target_unit_id": target_unit_id
	}

static func mission_recon(player_id: int, unit_id: int,
		target_x: int, target_y: int) -> Dictionary:
	return {
		"type": IDs.CommandType.MISSION_RECON,
		"player_id": player_id,
		"unit_id": unit_id,
		"target_x": target_x, "target_y": target_y
	}

static func mission_air_patrol(player_id: int, unit_id: int) -> Dictionary:
	return {"type": IDs.CommandType.MISSION_AIR_PATROL, "player_id": player_id, "unit_id": unit_id}

static func mission_sea_patrol(player_id: int, unit_id: int) -> Dictionary:
	return {"type": IDs.CommandType.MISSION_SEA_PATROL, "player_id": player_id, "unit_id": unit_id}

# Order a worker-type unit to scrub radioactive fallout off its current tile (§5.7).
static func mission_clean_fallout(player_id: int, unit_id: int) -> Dictionary:
	return {"type": IDs.CommandType.MISSION_CLEAN_FALLOUT, "player_id": player_id, "unit_id": unit_id}

# ── Draft / conscription (§6.4) ───────────────────────────────────────────────

# Conscript a military unit from a city's population (requires the can_draft civic).
static func draft(player_id: int, settlement_id: int) -> Dictionary:
	return {
		"type": IDs.CommandType.DRAFT,
		"player_id": player_id,
		"settlement_id": settlement_id
	}

# ── Nuclear strike (§5.7) ─────────────────────────────────────────────────────

# Launch a one-use nuclear weapon at a target tile; the missile is consumed.
static func nuclear_strike(player_id: int, unit_id: int,
		target_x: int, target_y: int) -> Dictionary:
	return {
		"type": IDs.CommandType.NUCLEAR_STRIKE,
		"player_id": player_id,
		"unit_id": unit_id,
		"target_x": target_x, "target_y": target_y
	}

# ── Trades (§7) ───────────────────────────────────────────────────────────────

# `give`/`receive` are Dictionaries like {"gold": int, "techs": [String]}; `peace`
# clears any war between the two alliances when the deal is accepted.
static func propose_trade(player_id: int, target_alliance_id: int,
		give: Dictionary, receive: Dictionary, peace: bool = false,
		duration: int = -1) -> Dictionary:
	return {
		"type": IDs.CommandType.PROPOSE_TRADE,
		"player_id": player_id,
		"target_alliance_id": target_alliance_id,
		"give": give.duplicate(true),
		"receive": receive.duplicate(true),
		"peace": peace,
		"duration": duration
	}

static func accept_trade(player_id: int, trade_id: int) -> Dictionary:
	return {"type": IDs.CommandType.ACCEPT_TRADE, "player_id": player_id, "trade_id": trade_id}

static func reject_trade(player_id: int, trade_id: int) -> Dictionary:
	return {"type": IDs.CommandType.REJECT_TRADE, "player_id": player_id, "trade_id": trade_id}

# ── Specialists, espionage, transport (§5.2, §6.5, §7) ────────────────────────

static func assign_specialist(player_id: int, settlement_id: int,
		specialist_type: String, count: int) -> Dictionary:
	return {
		"type": IDs.CommandType.ASSIGN_SPECIALIST,
		"player_id": player_id,
		"settlement_id": settlement_id,
		"specialist_type": specialist_type,
		"count": count
	}

static func set_tile_worked(player_id: int, settlement_id: int,
		x: int, y: int, worked: bool) -> Dictionary:
	return {
		"type": IDs.CommandType.SET_TILE_WORKED,
		"player_id": player_id,
		"settlement_id": settlement_id,
		"x": x, "y": y, "worked": worked
	}

static func set_citizen_automation(player_id: int, settlement_id: int,
		auto: bool) -> Dictionary:
	return {
		"type": IDs.CommandType.SET_CITIZEN_AUTOMATION,
		"player_id": player_id,
		"settlement_id": settlement_id,
		"auto": auto
	}

static func disband_city(player_id: int, settlement_id: int) -> Dictionary:
	# Voluntarily raze one of your own cities (§4.8).
	return {
		"type": IDs.CommandType.DISBAND_CITY,
		"player_id": player_id,
		"settlement_id": settlement_id
	}

static func espionage_mission(player_id: int, target_alliance_id: int,
		mission: String) -> Dictionary:
	# mission: "steal_tech", "sabotage", or "incite_unrest"
	return {
		"type": IDs.CommandType.ESPIONAGE_MISSION,
		"player_id": player_id,
		"target_alliance_id": target_alliance_id,
		"mission": mission
	}

# Cast a vote on the open diplomatic-assembly proposal (§7.2). choice is one of
# "yea", "nay", or "abstain".
static func cast_vote(player_id: int, choice: String) -> Dictionary:
	return {
		"type": IDs.CommandType.CAST_VOTE,
		"player_id": player_id,
		"choice": choice
	}

static func set_subordination(player_id: int, overlord_alliance_id: int) -> Dictionary:
	return {
		"type": IDs.CommandType.SET_SUBORDINATION,
		"player_id": player_id,
		"overlord_alliance_id": overlord_alliance_id
	}

static func load_unit(player_id: int, unit_id: int, transport_id: int) -> Dictionary:
	return {
		"type": IDs.CommandType.LOAD_UNIT,
		"player_id": player_id,
		"unit_id": unit_id,
		"transport_id": transport_id
	}

static func unload_unit(player_id: int, unit_id: int,
		target_x: int, target_y: int) -> Dictionary:
	return {
		"type": IDs.CommandType.UNLOAD_UNIT,
		"player_id": player_id,
		"unit_id": unit_id,
		"target_x": target_x, "target_y": target_y
	}

# ── Great Person actions (§14) ────────────────────────────────────────────────

# `action` is one of the strings in the unit's data "actions" list (e.g.
# "join_city", "start_golden_age", "discover_technology"). `params` carries
# optional targeting: settlement_id, target_alliance_id, tech_id, org_id.
static func gp_action(player_id: int, unit_id: int, action: String,
		params: Dictionary = {}) -> Dictionary:
	var cmd: Dictionary = {
		"type": IDs.CommandType.GP_ACTION,
		"player_id": player_id,
		"unit_id": unit_id,
		"action": action
	}
	for key in params:
		cmd[key] = params[key]
	return cmd

# ── Controls (§3.1) ───────────────────────────────────────────────────────────

static func do_control(player_id: int, ctrl_type: int,
		data: Dictionary = {}) -> Dictionary:
	var cmd: Dictionary = {
		"type": IDs.CommandType.DO_CONTROL,
		"player_id": player_id,
		"ctrl_type": ctrl_type
	}
	for key in data:
		cmd[key] = data[key]
	return cmd
