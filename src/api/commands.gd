class_name Commands

# Serializable player intents. All input (mouse/keyboard/touch) is eventually
# reduced to one of these before being passed to SimFacade.apply_command().

# Create a command Dictionary with the given type and parameters.
static func end_turn(player_id: int) -> Dictionary:
	return {"type": IDs.CommandType.END_TURN, "player_id": player_id}

static func move_stack(player_id: int, from_x: int, from_y: int,
		to_x: int, to_y: int) -> Dictionary:
	return {
		"type": IDs.CommandType.MOVE_STACK,
		"player_id": player_id,
		"from_x": from_x, "from_y": from_y,
		"to_x": to_x, "to_y": to_y
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
