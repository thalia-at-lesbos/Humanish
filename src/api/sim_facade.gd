# Humanish — a turn-based 4X strategy game.
# Copyright (C) 2026 thalia-at-lesbos
# SPDX-License-Identifier: GPL-3.0-or-later
#
# This program is free software: you can redistribute it and/or modify it
# under the terms of the GNU General Public License as published by the Free
# Software Foundation, either version 3 of the License, or (at your option)
# any later version. See the LICENSE file for the full text and warranty
# disclaimer.

class_name SimFacade
extends Reference

# Public surface of the simulation engine.
# The only way to mutate state is apply_command().
# Events are emitted as signals so UI can observe without polling.

signal event_emitted(event_dict)
signal turn_advanced(turn_number)
signal game_won(alliance_id)
signal unit_created(unit_id)
signal settlement_founded(settlement_id)
signal city_conquered(settlement_id, captor_player_id)   # kept (in revolt) — §4.8
signal city_razed(settlement_id, by_player_id)           # destroyed — §4.8
signal city_flipped(settlement_id, from_player_id, to_player_id)  # cultural — §4.9
signal technology_completed(player_id, tech_id)
signal era_advanced(player_id, from_era, to_era)         # §1
signal combat_resolved(result_dict)
signal player_turn_started(player_id)
signal screen_requested(screen_id)
signal assembly_event(event_dict)   # §7.2 session opened / resolution resolved
signal nuclear_detonated(result_dict)  # §5.7 nuke strike resolved (area effect)

var _gs: GameState
var _hooks: Hooks
var _db: DataDB

# UI state (not part of simulation; not serialized)
var _dirty: DirtyFlags
var _selection: SelectionState
var _interface_mode: int = 0    # IDs.InterfaceMode.SELECTION
var _popup_queue: Array = []
var _notifications: Array = []

# Remote-multiplayer client seam (not part of simulation; not serialized).
# When a NetClient installs a submit handler, this facade is a remote client:
# ending the turn no longer runs the local pipeline — instead the handler ships
# the player's post-move snapshot to the authoritative server, and the facade is
# parked in a "waiting" state until the server pushes the next turn's state.
# In server / single-player mode these stay null/false and nothing changes.
var _remote_submit_cb = null     # FuncRef() → bool, set via set_remote_submit_handler()
var _remote_waiting: bool = false

# ── Lifecycle ─────────────────────────────────────────────────────────────────

func setup(db: DataDB, seed_val: int, world_size_id: String, pace_id: String,
		difficulty_id: String, player_configs: Array,
		enabled_win_conditions: Array, map_type_id: String = "continents",
		aggressive_wild: bool = false,
		permanent_alliances: bool = false) -> void:
	_db = db
	_hooks = Hooks.new()
	_dirty = load("res://src/api/dirty_flags.gd").new()
	_selection = load("res://src/api/selection_state.gd").new()
	_interface_mode = IDs.InterfaceMode.SELECTION
	_popup_queue = []
	_notifications = []

	_gs = GameState.new()
	_gs.db = db
	_gs.rng = RNG.new()
	_gs.rng.init(seed_val)
	_gs.pace_id = pace_id
	_gs.difficulty_id = difficulty_id
	_gs.enabled_win_conditions = enabled_win_conditions.duplicate()
	_gs.wild_aggressive = aggressive_wild
	_gs.permanent_alliances = permanent_alliances

	var ws: Dictionary = db.get_world_size(world_size_id)
	_gs.max_turns = int(db.get_pace(pace_id).get("max_turns", 500))

	# The map-type spec may override the world-size wrap flags (e.g. "archipelago"
	# sets wrap_x=false so island maps have a hard east/west edge).
	var mt: Dictionary = db.get_map_type(map_type_id)
	var map_wrap_x: bool = bool(mt.get("wrap_x", ws.get("wrap_x", true)))
	var map_wrap_y: bool = bool(mt.get("wrap_y", ws.get("wrap_y", false)))

	_gs.map = WorldMap.new()
	_gs.map.init(
		int(ws.get("width", 80)),
		int(ws.get("height", 48)),
		map_wrap_x,
		map_wrap_y
	)
	# Populate the blank grid with the chosen map script. Uses gs.rng so the result
	# is deterministic for the seed and is captured by save/load (tiles serialize).
	MapGen.generate(_gs.map, db, _gs.rng, map_type_id)

	# Create players and alliances
	var difficulty: Dictionary = db.get_difficulty(difficulty_id)
	var default_techs: Array = db.constants.get("starting_techs", [])
	var default_research: String = str(db.constants.get("default_research", ""))
	for cfg in player_configs:
		var p := Player.new()
		p.id = _gs.next_player_id()
		p.name = str(cfg.get("name", "Player " + str(p.id)))
		p.leader_id = str(cfg.get("leader_id", ""))
		p.traits = cfg.get("traits", []).duplicate()
		p.free_early_wins = int(difficulty.get("free_early_wins", 0))
		p.treasury = int(cfg.get("starting_gold", 100))
		p.is_ai = bool(cfg.get("is_ai", false))

		# Seed the player's known techs and pick a default research target so the
		# tech tree (data/technologies.json) is usable from turn one. A player's
		# society supplies its own starting techs (cfg["starting_techs"]); society-
		# less players (default/headless games) fall back to the global default.
		p.technologies = cfg.get("starting_techs", default_techs).duplicate()
		if default_research != "" and Research.can_research(default_research, p, db):
			p.current_research_id = default_research
		# Seed the era cache from the starting techs (no notification at game start —
		# gs is omitted so nothing is queued).
		Eras.refresh(p, db)

		# Each player starts in their own alliance
		var a := Alliance.new()
		a.id = _gs.next_alliance_id()
		a.add_member(p.id)
		p.alliance_id = a.id
		_gs.alliances.append(a)
		_gs.players.append(p)

	if not _gs.players.empty():
		_gs.current_player_id = _gs.players[0].id

	# Place each player's opening units (data-driven via cfg["starting_units"]).
	# Players with no starting units (e.g. headless test configs) get none, so
	# the engine stays generic and society→unit mapping lives in the caller.
	_place_all_starting_units(player_configs, map_type_id)

# Initialize only the non-serialized scaffolding (db, hooks, UI state) so a save
# can be loaded into a fresh facade without running setup(). load_save() then
# supplies the GameState. Used by the start menu's "Load Game" path.
func init_for_load(db: DataDB) -> void:
	_db = db
	_hooks = Hooks.new()
	_dirty = load("res://src/api/dirty_flags.gd").new()
	_selection = load("res://src/api/selection_state.gd").new()
	_interface_mode = IDs.InterfaceMode.SELECTION
	_popup_queue = []
	_notifications = []

func _place_all_starting_units(player_configs: Array, map_type_id: String = "") -> void:
	var starts: Array = MapGen.find_start_positions(_gs.map, _db, _gs.players.size(), map_type_id)
	for i in range(_gs.players.size()):
		if i >= player_configs.size() or i >= starts.size():
			break
		var su: Array = player_configs[i].get("starting_units", [])
		if su.empty():
			continue
		_spawn_starting_units(_gs.players[i].id, int(starts[i][0]), int(starts[i][1]), su)

# Spawn a list of unit type ids for a player, fanned out across the start tile
# and its passable land neighbours so they do not all hide on one square.
func _spawn_starting_units(player_id: int, sx: int, sy: int, unit_types: Array) -> void:
	var tiles: Array = [[sx, sy]]
	for nb in _gs.map.neighbours8(sx, sy):
		var ter: Dictionary = _db.get_terrain(nb.terrain_id)
		if ter.get("domain", "land") == "land" and not ter.get("impassable", false):
			tiles.append([nb.x, nb.y])

	for k in range(unit_types.size()):
		var slot: Array = tiles[k % tiles.size()]
		_spawn_unit(str(unit_types[k]), player_id, int(slot[0]), int(slot[1]))

# Create a single unit of the given type for a player at (x, y), pulling stats
# from data/units.json. Returns the new unit id (-1 if the type is unknown).
func _spawn_unit(unit_type_id: String, player_id: int, x: int, y: int) -> int:
	var udata: Dictionary = _db.get_unit(unit_type_id)
	if udata.empty():
		return -1
	var u := Unit.new()
	u.id = _gs.next_unit_id()
	u.unit_type_id = unit_type_id
	u.owner_player_id = player_id
	u.x = x; u.y = y
	u.base_strength = int(udata.get("base_strength", 0))
	u.movement_total = int(udata.get("movement", 200))
	u.movement_left = u.movement_total
	_gs.units.append(u)
	emit_signal("unit_created", u.id)
	return u.id

# Load from a save string.
func load_save(json_str: String) -> bool:
	var gs := SaveLoad.load_from_string(json_str, _db)
	if gs == null:
		return false
	_gs = gs
	return true

func save() -> String:
	return SaveLoad.save_to_string(_gs)

func state_hash() -> int:
	return SaveLoad.state_hash(_gs)

# ── Query ─────────────────────────────────────────────────────────────────────

func get_state() -> GameState:
	return _gs

func get_hooks() -> Hooks:
	return _hooks

# A player's current era as {index, id, name} (§1), for HUD/AI/presentation. The
# index is read live (highest era over researched techs), so it is always current
# even if the cached Player.era lags by a notification.
func get_player_era(player_id: int) -> Dictionary:
	var p: Player = _gs.get_player(player_id)
	var idx: int = Eras.player_era(p, _db)
	return {"index": idx, "id": Eras.era_id(idx, _db), "name": Eras.era_name(idx, _db)}

# ── Diplomatic assembly (§7.2) ────────────────────────────────────────────────

# The full assembly record ({} when no founding wonder exists). Read-only.
func get_assembly_state() -> Dictionary:
	return _gs.assembly

# The proposal a player still owes a vote on, as {resolution_id, name, text}, or {}
# when there is no open session, the player is not a member, or they have voted.
func get_pending_vote(player_id: int) -> Dictionary:
	var p: Player = _gs.get_player(player_id)
	if p == null or not Assembly.has_open_session(_gs) or Assembly.has_voted(_gs, player_id):
		return {}
	if not Assembly.is_member(_gs, p, str(_gs.assembly.get("kind", ""))):
		return {}
	var pending: Dictionary = Assembly.pending_proposal(_gs)
	return {
		"resolution_id": str(pending.get("resolution_id", "")),
		"name": str(pending.get("name", "")),
		"text": str(pending.get("text", ""))
	}

# Convenience wrapper used by screens/AI: cast a vote through the command path.
func cast_assembly_vote(player_id: int, choice: String) -> bool:
	return apply_command(Commands.cast_vote(player_id, choice))

# ── Commands ──────────────────────────────────────────────────────────────────

# Apply a command. Returns true if accepted.
func apply_command(cmd: Dictionary) -> bool:
	var ctype: int = int(cmd.get("type", -1))
	var player_id: int = int(cmd.get("player_id", -1))

	# Remote client: an end-turn is not run locally — it is handed to the server
	# as a full-state submission (see set_remote_submit_handler). All other
	# commands fall through and mutate the local facade normally, exactly as in a
	# solo game, because the client owns the current turn until it submits. Once
	# parked (waiting on the server) a repeat end-turn is dropped, never run
	# through the local pipeline — only the server advances the authoritative game.
	if _remote_submit_cb != null and _is_end_turn_command(ctype, cmd):
		if _remote_waiting:
			return false
		return _remote_submit()

	# Validate it's this player's turn
	if player_id != _gs.current_player_id:
		return false

	match ctype:
		IDs.CommandType.END_TURN:
			return _cmd_end_turn(player_id)
		IDs.CommandType.MOVE_STACK:
			return _cmd_move_stack(cmd)
		IDs.CommandType.FOUND_SETTLEMENT:
			return _cmd_found_settlement(cmd)
		IDs.CommandType.SET_SLIDERS:
			return _cmd_set_sliders(cmd)
		IDs.CommandType.SET_PRODUCTION:
			return _cmd_set_production(cmd)
		IDs.CommandType.SET_RESEARCH:
			return _cmd_set_research(cmd)
		IDs.CommandType.SET_POLICY:
			return _cmd_set_policy(cmd)
		IDs.CommandType.SET_STATE_RELIGION:
			return _cmd_set_state_religion(cmd)
		IDs.CommandType.DECLARE_WAR:
			return _cmd_declare_war(cmd)
		IDs.CommandType.MAKE_PEACE:
			return _cmd_make_peace(cmd)
		IDs.CommandType.RUSH_PRODUCTION:
			return _cmd_rush_production(cmd)
		IDs.CommandType.BUILD_IMPROVEMENT:
			return _cmd_build_improvement(cmd)
		IDs.CommandType.UNIT_WAKE, IDs.CommandType.UNIT_SLEEP, \
		IDs.CommandType.UNIT_FORTIFY, IDs.CommandType.UNIT_CANCEL_ORDERS, \
		IDs.CommandType.UNIT_DISBAND, IDs.CommandType.UNIT_UPGRADE, \
		IDs.CommandType.UNIT_PROMOTE, IDs.CommandType.UNIT_GIFT:
			return _cmd_unit_command(cmd)
		IDs.CommandType.MISSION_MOVE_TO, IDs.CommandType.MISSION_BUILD_ROAD, \
		IDs.CommandType.MISSION_SKIP_TURN, IDs.CommandType.MISSION_PILLAGE, \
		IDs.CommandType.MISSION_BOMBARD, IDs.CommandType.MISSION_AIRLIFT, \
		IDs.CommandType.MISSION_SENTRY, IDs.CommandType.MISSION_HEAL, \
		IDs.CommandType.MISSION_MOVE_TO_UNIT, IDs.CommandType.MISSION_RECON, \
		IDs.CommandType.MISSION_AIR_PATROL, IDs.CommandType.MISSION_SEA_PATROL, \
		IDs.CommandType.MISSION_CLEAN_FALLOUT, \
		IDs.CommandType.MISSION_SLEEP_UNTIL_HEALED, \
		IDs.CommandType.MISSION_FORTIFY_UNTIL_HEALED, \
		IDs.CommandType.MISSION_EXPLORE:
			return _cmd_mission(cmd)
		IDs.CommandType.NUCLEAR_STRIKE:
			return _cmd_nuclear_strike(cmd)
		IDs.CommandType.DRAFT:
			return _cmd_draft(cmd)
		IDs.CommandType.SPREAD_BELIEF:
			return _cmd_spread_belief(cmd)
		IDs.CommandType.DO_CONTROL:
			return _cmd_do_control(cmd)
		IDs.CommandType.PROPOSE_TRADE:
			return _cmd_propose_trade(cmd)
		IDs.CommandType.ACCEPT_TRADE:
			return _cmd_accept_trade(cmd)
		IDs.CommandType.REJECT_TRADE:
			return _cmd_reject_trade(cmd)
		IDs.CommandType.ASSIGN_SPECIALIST:
			return _cmd_assign_specialist(cmd)
		IDs.CommandType.SET_TILE_WORKED:
			return _cmd_set_tile_worked(cmd)
		IDs.CommandType.SET_CITIZEN_AUTOMATION:
			return _cmd_set_citizen_automation(cmd)
		IDs.CommandType.DISBAND_CITY:
			return _cmd_disband_city(cmd)
		IDs.CommandType.DEQUEUE_PRODUCTION:
			return _cmd_dequeue_production(cmd)
		IDs.CommandType.ESPIONAGE_MISSION:
			return _cmd_espionage_mission(cmd)
		IDs.CommandType.LOAD_UNIT:
			return _cmd_load_unit(cmd)
		IDs.CommandType.UNLOAD_UNIT:
			return _cmd_unload_unit(cmd)
		IDs.CommandType.SET_SUBORDINATION:
			return _cmd_set_subordination(cmd)
		IDs.CommandType.GP_ACTION:
			return _cmd_gp_action(cmd)
		IDs.CommandType.CAST_VOTE:
			return _cmd_cast_vote(cmd)
		IDs.CommandType.PROPOSE_PERMANENT_ALLIANCE:
			return _cmd_propose_permanent_alliance(cmd)
	return false

# ── Remote-multiplayer client seam ────────────────────────────────────────────

# Install (or clear, with null) the handler a NetClient uses to ship the player's
# post-move snapshot to the server at end-of-turn. Setting a non-null handler
# marks this facade as a remote client. Pure presentation/transport wiring — the
# sim never sees it; it is not serialized.
func set_remote_submit_handler(cb) -> void:
	_remote_submit_cb = cb
	if cb == null:
		_remote_waiting = false

func is_remote_client() -> bool:
	return _remote_submit_cb != null

# Park / unpark the local turn. While waiting, the End Turn button reads as
# "Waiting…" and another end-turn cannot be submitted. The NetClient clears this
# when the server pushes the next state this player owns.
func set_remote_waiting(flag: bool) -> void:
	_remote_waiting = flag
	_dirty.set_dirty(IDs.DirtyRegion.HUD_GROUPS)

func is_remote_waiting() -> bool:
	return _remote_waiting

# True for any command that ends the turn — the direct END_TURN command or the
# END_TURN / FORCE_END_TURN control routed through DO_CONTROL (the hotkey path).
func _is_end_turn_command(ctype: int, cmd: Dictionary) -> bool:
	if ctype == IDs.CommandType.END_TURN:
		return true
	if ctype == IDs.CommandType.DO_CONTROL:
		var ct: int = int(cmd.get("ctrl_type", -1))
		return ct == IDs.ControlType.END_TURN or ct == IDs.ControlType.FORCE_END_TURN
	return false

# Hand the current snapshot to the server and park the turn. Returns the
# handler's result (false if no handler is installed — should not happen, since
# the apply_command guard checks first).
func _remote_submit() -> bool:
	if _remote_submit_cb == null:
		return false
	_remote_waiting = true
	_dirty.set_dirty(IDs.DirtyRegion.HUD_GROUPS)
	return bool(_remote_submit_cb.call_func())

# ── Command handlers ──────────────────────────────────────────────────────────

func _cmd_end_turn(player_id: int) -> bool:
	var player: Player = _gs.get_player(player_id)
	if player == null:
		return false

	# Advance all exploring scouts for this player before the turn pipeline runs.
	_run_explore_missions(player_id)

	TurnEngine.player_step(_gs, player_id, _hooks)
	_drain_flips()
	_drain_era_advances()
	_drain_tech_completions()
	_drain_great_people()
	_drain_productions()
	_drain_growth_events()

	# Trigger world step when the last player ends their turn (next wraps to index 0)
	var next_idx: int = _get_next_player_index(player_id)
	if next_idx == 0 or next_idx < 0:
		TurnEngine.world_step(_gs, _hooks)
		_drain_wild_events()
		_drain_assembly_events()
		_drain_great_people()
		_add_notification("Turn " + str(_gs.turn_number) + " begins.", "info")
		emit_signal("turn_advanced", _gs.turn_number)
		if _gs.winning_alliance_id >= 0:
			emit_signal("game_won", _gs.winning_alliance_id)

	# Advance to next active player
	if not _gs.players.empty() and next_idx >= 0 and next_idx < _gs.players.size():
		_gs.current_player_id = _gs.players[next_idx].id
		# Resume any standing go-to orders before the turn opens, so multi-turn
		# journeys advance automatically (their movement was refreshed when this
		# player last ended a turn).
		_resume_goto(_gs.current_player_id)
		emit_signal("player_turn_started", _gs.current_player_id)
		# Raise the assembly ballot for a human who still owes a vote (§7.2).
		_maybe_raise_vote_popup(_gs.current_player_id)

	_dirty.mark_all()
	return true

func _cmd_move_stack(cmd: Dictionary) -> bool:
	var player_id: int = int(cmd["player_id"])
	var fx: int = int(cmd["from_x"]); var fy: int = int(cmd["from_y"])
	var tx: int = int(cmd["to_x"]);   var ty: int = int(cmd["to_y"])

	var moving_units: Array = _stack_movers(fx, fy, player_id, cmd.get("unit_ids", []))
	if moving_units.empty():
		return false

	var lead: Unit = moving_units[0]
	var path: Array = Pathfinding.find_path(
		_gs.map, fx, fy, tx, ty, lead, _db, _gs.units, player_id)

	if path.empty() and not (fx == tx and fy == ty):
		return false

	# Move one step at a time, consuming each unit's movement allowance (which is
	# set per unit class from data/units.json). The stack stops once its slowest
	# member is out of points; a unit with any points left may always enter one
	# more tile, so movement is bounded but never zero.
	for step in path:
		var min_left: int = lead.movement_left
		for u in moving_units:
			if u.movement_left < min_left:
				min_left = u.movement_left
		if min_left <= 0:
			break

		var sx: int = int(step[0]); var sy: int = int(step[1])

		# If the next tile holds an enemy, attack INTO it rather than moving on
		# first. Combat is resolved here; the attacker only advances onto the
		# tile if it wins (handled in _apply_combat_result). Attacking ends the
		# stack's movement for the turn.
		var enemy_city: Settlement = _enemy_settlement_at(sx, sy, player_id)
		var enemy: Unit = Stack.get_defender(
			_gs.units, sx, sy, player_id, _gs)
		if enemy != null:
			# A defender on a city tile must be beaten before the city can be
			# assaulted, and killing it does NOT walk the attacker into the city
			# (the city is taken by the assault below, not by clearing defenders).
			var result: Dictionary = Combat.resolve(lead, enemy, _gs, _gs.rng)
			_apply_combat_result(lead, enemy, result, enemy_city == null)
			emit_signal("combat_resolved", result)
			_add_combat_notification(lead, enemy, result)
			for u in moving_units:
				u.movement_left = 0
				u.has_moved = true
				u.is_fortified = false
				u.is_sleep_until_healed = false
				u.is_fortify_until_healed = false
			lead.has_attacked = true
			break

		# An undefended enemy city tile is assaulted (§4.8): the attack lowers the
		# city's siege HP, and the city falls (razed or captured) at 0. The stack
		# advances onto the tile only once the city has fallen.
		if enemy_city != null:
			var outcome: String = _assault_city(lead, enemy_city, player_id)
			for u in moving_units:
				u.movement_left = 0
				u.has_moved = true
			lead.has_attacked = true
			if outcome != "held":
				for u in moving_units:
					u.x = sx; u.y = sy
					u.stationary_turns = 0
					u.entrenchment = 0
			break

		var step_cost: int = Pathfinding._move_cost(
			_gs.map.get_tile(sx, sy), _db,
			_db.get_unit(lead.unit_type_id).get("domain", "land"))

		for u in moving_units:
			u.movement_left = max(0, u.movement_left - step_cost)
			u.x = sx; u.y = sy
			u.has_moved = true
			u.stationary_turns = 0
			u.entrenchment = 0
			# Issue 5: moving cancels Fortify and any heal-stance (unit is now active).
			u.is_fortified = false
			u.is_sleep_until_healed = false
			u.is_fortify_until_healed = false
			# Carried units ride along with their transport (§5.2).
			for cid in u.cargo:
				var carried: Unit = _gs.get_unit(cid)
				if carried != null:
					carried.x = sx; carried.y = sy

		# Exploration: the first unit to enter a discovery site claims its
		# reward, then the site is consumed (§9).
		var entered: Tile = _gs.map.get_tile(sx, sy)
		if entered != null and entered.has_discovery:
			entered.has_discovery = false
			var reward: Dictionary = Events.exploration_reward(lead, _gs, _gs.rng)
			_add_notification("Discovery: " + str(reward.get("type", "")), "major")
			emit_signal("event_emitted", reward)

		# Zone of control: entering a tile adjacent to a hostile unit ends the
		# stack's movement for the turn (§5.2).
		if _adjacent_hostile(sx, sy, player_id):
			for u in moving_units:
				u.movement_left = 0
			break

	# Persist (or clear) a go-to goal so a move that could not finish this turn keeps
	# travelling toward its target on later turns (§3.3 go-to mission). The goal is
	# dropped on arrival, and dropped after combat so a go-to never auto-re-attacks.
	for u in moving_units:
		if u.x == tx and u.y == ty:
			u.goto_x = -1; u.goto_y = -1
		elif lead.has_attacked:
			u.goto_x = -1; u.goto_y = -1
		else:
			u.goto_x = tx; u.goto_y = ty

	_dirty.set_dirty(IDs.DirtyRegion.WORLD)
	_dirty.set_dirty(IDs.DirtyRegion.HUD_GROUPS)
	return true

# Resume every go-to order for `player_id`: each unit still carrying a destination
# travels toward it with this turn's movement. Called at the start of the player's
# turn (movement already refreshed), so a multi-turn journey advances one turn's
# worth automatically. An order that can no longer be pathed is abandoned.
func _resume_goto(player_id: int) -> void:
	# Snapshot ids first — a resumed move may remove a unit (combat) or others.
	var ids: Array = []
	for u in _gs.units:
		if u.owner_player_id == player_id and u.goto_x >= 0:
			ids.append(u.id)
	for uid in ids:
		var u: Unit = _gs.get_unit(uid)
		if u == null or u.goto_x < 0:
			continue
		if u.x == u.goto_x and u.y == u.goto_y:
			u.goto_x = -1; u.goto_y = -1
			continue
		if u.movement_left <= 0:
			continue
		var mc: Dictionary = {
			"type": IDs.CommandType.MOVE_STACK,
			"player_id": player_id,
			"from_x": u.x, "from_y": u.y,
			"to_x": u.goto_x, "to_y": u.goto_y,
			"unit_ids": [u.id]
		}
		if not _cmd_move_stack(mc):
			u.goto_x = -1; u.goto_y = -1   # unreachable now: give up the order

# The units that actually move for a MOVE_STACK at (fx, fy): owned, on the tile,
# and not riding a transport. When unit_ids is non-empty the result is filtered
# to that subset, so a single member can be peeled off a larger stack; the order
# of all_here is preserved so the lead (and thus the path) stays stable.
func _stack_movers(fx: int, fy: int, player_id: int, unit_ids) -> Array:
	var wanted: Array = unit_ids if unit_ids != null else []
	var out: Array = []
	for mu in Stack.at(_gs.units, fx, fy, player_id):
		if mu.transported_by >= 0:
			continue
		if not wanted.empty() and not (mu.id in wanted):
			continue
		out.append(mu)
	return out

# ── City conquest (§4.8) ──────────────────────────────────────────────────────

# An enemy settlement on a tile the attacker is hostile to: a barbarian/wild city
# (owner -2) or another player's city the attacker is at war with. null otherwise
# — own cities, and foreign cities at peace, are not assaulted.
func _enemy_settlement_at(x: int, y: int, attacker_pid: int) -> Settlement:
	var s: Settlement = _gs.get_settlement_at(x, y)
	if s == null or s.owner_player_id == attacker_pid:
		return null
	if s.owner_player_id == -2 or _gs.are_at_war(attacker_pid, s.owner_player_id):
		return s
	return null

# One assault by `lead` on an undefended enemy `city`: lowers its siege HP by the
# attacker's effective strength. Returns "held" while HP remains, else the fall
# outcome ("razed"/"captured").
func _assault_city(lead: Unit, city: Settlement, attacker_pid: int) -> String:
	var maxh: int = TurnEngine.city_max_health(city, _db)
	if city.health < 0 or city.health > maxh:
		city.health = maxh
	var tile: Tile = _gs.map.get_tile(city.x, city.y)
	var ter: Dictionary = _db.get_terrain(tile.terrain_id)
	var feat: Dictionary = _db.get_feature(tile.feature_id) if tile.feature_id != "" else {}
	var dmg: int = lead.effective_strength(_db, true, ter, feat, "", true)
	if dmg < 1:
		dmg = 1
	city.health -= dmg
	_dirty.set_dirty(IDs.DirtyRegion.WORLD)
	if city.health > 0:
		return "held"
	return _city_falls(city, attacker_pid)

# A city whose siege HP reached 0 falls. Barbarians always raze; a size-1 city
# that was never larger is auto-razed; otherwise the captor keeps it (in revolt).
func _city_falls(city: Settlement, captor_pid: int) -> String:
	if captor_pid == -2 or (city.population <= 1 and city.peak_population <= 1):
		_raze_city(city, captor_pid)
		return "razed"
	_capture_city(city, captor_pid)
	return "captured"

# Transfer a fallen city to its captor. It revolts for revolt_base_turns + half
# its size (producing nothing meanwhile, §4.8); its HP is restored, its queue and
# specialists are cleared, and the loser's Palace is stripped so they re-seed a
# new capital next turn (§6.1).
func _capture_city(city: Settlement, captor_pid: int) -> void:
	city.owner_player_id = captor_pid
	city.structures.erase("palace")
	city.production_queue = []
	city.production_store = 0
	city.specialists = {}
	city.worked_tiles = []
	city.locked_tiles = []
	city.revolt_turns = _db.get_constant("revolt_base_turns", 3) + city.population / 2
	city.health = TurnEngine.city_max_health(city, _db)
	city.in_disorder = true
	_add_notification(city.name + " captured!", "major")
	emit_signal("city_conquered", city.id, captor_pid)
	_dirty.set_dirty(IDs.DirtyRegion.WORLD)
	_dirty.set_dirty(IDs.DirtyRegion.DATA_PANES)
	_dirty.set_dirty(IDs.DirtyRegion.HUD_GROUPS)

# Destroy a city entirely (conquest raze, auto-raze, or a voluntary disband).
func _raze_city(city: Settlement, by_pid: int) -> void:
	var sid: int = city.id
	_gs.settlements.erase(city)
	if _selection != null and _selection.head_city() == sid:
		_selection.clear()
	_add_notification(city.name + " was razed.", "major")
	emit_signal("city_razed", sid, by_pid)
	_dirty.set_dirty(IDs.DirtyRegion.WORLD)
	_dirty.set_dirty(IDs.DirtyRegion.DATA_PANES)
	_dirty.set_dirty(IDs.DirtyRegion.HUD_GROUPS)

# Voluntarily disband (raze) one of the player's own cities at any time (§4.8).
# The capital (identified by holding the Palace structure) cannot be disbanded.
func _cmd_disband_city(cmd: Dictionary) -> bool:
	var s: Settlement = _gs.get_settlement(int(cmd.get("settlement_id", -1)))
	var pid: int = int(cmd["player_id"])
	if s == null or s.owner_player_id != pid:
		return false
	if s.has_structure("palace"):
		return false
	_raze_city(s, pid)
	return true

func _cmd_found_settlement(cmd: Dictionary) -> bool:
	var player_id: int = int(cmd["player_id"])
	var unit_id: int = int(cmd["unit_id"])
	var sname: String = str(cmd.get("name", ""))

	var u: Unit = _gs.get_unit(unit_id)
	if u == null or u.owner_player_id != player_id:
		return false
	var udata: Dictionary = _db.get_unit(u.unit_type_id)
	if not udata.get("can_found", false):
		return false

	# Check minimum distance from other settlements
	var min_dist: int = _db.get_constant("min_settlement_distance", 3)
	for existing in _gs.settlements:
		if _gs.map.distance(u.x, u.y, existing.x, existing.y) < min_dist:
			return false

	# A player's first city is their capital (the earliest-founded settlement;
	# see TurnEngine._find_capital). Decide this before appending the new one.
	var is_first_city: bool = true
	for existing in _gs.settlements:
		if existing.owner_player_id == player_id:
			is_first_city = false
			break

	# Found the settlement
	var s := Settlement.new()
	s.id = _gs.next_settlement_id()
	s.name = sname if sname != "" else "City " + str(s.id)
	s.owner_player_id = player_id
	s.x = u.x; s.y = u.y
	s.population = 1
	s.peak_population = 1
	# Seed the capital with the Palace by default. Data-driven: only added when
	# the structures table actually defines a "palace" entry.
	if is_first_city and not _db.get_structure("palace").empty():
		s.structures.append("palace")
	_gs.settlements.append(s)

	# Initial cultural claim
	Influence.found_claim(_gs.map, u.x, u.y, player_id, 2, 20)

	# Remove the settler unit
	Stack.remove_unit(_gs.units, unit_id)

	_add_notification(s.name + " founded.", "major")
	emit_signal("settlement_founded", s.id)
	_dirty.set_dirty(IDs.DirtyRegion.WORLD)
	_dirty.set_dirty(IDs.DirtyRegion.DATA_PANES)
	# The founding settler is gone; refresh the selection/action panel.
	_dirty.set_dirty(IDs.DirtyRegion.HUD_GROUPS)
	return true

func _cmd_set_sliders(cmd: Dictionary) -> bool:
	var p: Player = _gs.get_player(int(cmd["player_id"]))
	if p == null:
		return false
	var f: int = int(cmd.get("finance", 0))
	var r: int = int(cmd.get("research", 0))
	var c: int = int(cmd.get("culture", 0))
	var i: int = int(cmd.get("intel", 0))
	if f + r + c + i != 100:
		return false
	if f < 0 or r < 0 or c < 0 or i < 0:
		return false
	# Governing policies constrain the sliders (§6.2): an allowed increment and a
	# minimum research share.
	var increment: int = 0
	var min_research: int = 0
	for cat in p.policies:
		var pol: Dictionary = _db.policies.get("policies", {}).get(p.policies[cat], {})
		increment = max(increment, int(pol.get("slider_increment", 0)))
		min_research = max(min_research, int(pol.get("slider_min_research", 0)))
	if increment > 0 and (f % increment != 0 or r % increment != 0 \
			or c % increment != 0 or i % increment != 0):
		return false
	if r < min_research:
		return false
	p.slider_finance = f; p.slider_research = r
	p.slider_culture = c; p.slider_intel = i
	_dirty.set_dirty(IDs.DirtyRegion.HUD_GROUPS)
	return true

func _cmd_set_production(cmd: Dictionary) -> bool:
	var s: Settlement = _gs.get_settlement(int(cmd["settlement_id"]))
	if s == null or s.owner_player_id != int(cmd["player_id"]):
		return false
	s.production_queue = cmd.get("queue", []).duplicate(true)
	_dirty.set_dirty(IDs.DirtyRegion.DATA_PANES)
	return true

# Remove one item from a city's production queue by zero-based index (§11).
func _cmd_dequeue_production(cmd: Dictionary) -> bool:
	var s: Settlement = _gs.get_settlement(int(cmd.get("settlement_id", -1)))
	if s == null or s.owner_player_id != int(cmd["player_id"]):
		return false
	var idx: int = int(cmd.get("index", -1))
	if idx < 0 or idx >= s.production_queue.size():
		return false
	s.production_queue.remove(idx)
	_dirty.set_dirty(IDs.DirtyRegion.DATA_PANES)
	return true

func _cmd_set_research(cmd: Dictionary) -> bool:
	var p: Player = _gs.get_player(int(cmd["player_id"]))
	if p == null:
		return false
	var tech_id: String = str(cmd.get("tech_id", ""))
	if not Research.can_research(tech_id, p, _db):
		return false
	p.current_research_id = tech_id
	_dirty.set_dirty(IDs.DirtyRegion.HUD_GROUPS)
	return true

func _cmd_set_policy(cmd: Dictionary) -> bool:
	var p: Player = _gs.get_player(int(cmd["player_id"]))
	if p == null:
		return false
	var cat: String = str(cmd.get("category", ""))
	var pol_id: String = str(cmd.get("policy_id", ""))
	var pol: Dictionary = _db.policies.get("policies", {}).get(pol_id, {})
	if pol.empty():
		return false
	var tech_req = pol.get("tech_required", null)
	if tech_req != null and tech_req != "" and not p.has_tech(tech_req):
		return false
	var prev: String = str(p.policies.get(cat, ""))
	if prev == pol_id:
		return false  # no change
	# Anarchy on a real switch only: replacing an established civic costs the
	# policy's transition turns, but the first government chosen in a category (from
	# none) is free, as is any switch for a Spiritual leader (§8).
	var transition: int = int(pol.get("transition_turns", 0))
	if transition > 0 and prev != "" and not ("spiritual" in p.traits):
		p.transition_turns = transition
	p.policies[cat] = pol_id
	_add_notification(p.name + " adopted " + str(pol.get("name", pol_id)) + ".", "major")
	_dirty.set_dirty(IDs.DirtyRegion.FULL_SCREENS)
	_dirty.set_dirty(IDs.DirtyRegion.HUD_GROUPS)
	return true

# Adopt or switch the player's empire-wide state religion (§8). "" means "no state
# religion" (always a legal choice). A non-empty religion must be a founded belief
# that is present in at least one of the player's settlements. Switching away from
# an existing state religion triggers anarchy (no commerce while it lasts) — but the
# first adoption (from none) is free, as is any switch for a Spiritual leader.
func _cmd_set_state_religion(cmd: Dictionary) -> bool:
	var p: Player = _gs.get_player(int(cmd["player_id"]))
	if p == null:
		return false
	var belief_id: String = str(cmd.get("belief_id", ""))
	if belief_id == p.state_religion:
		return false  # no change
	if belief_id != "":
		if not _gs.founded_beliefs.has(belief_id):
			return false
		var present: bool = false
		for s in _gs.settlements:
			if s.owner_player_id == p.id and s.belief_id == belief_id:
				present = true
				break
		if not present:
			return false
	# Anarchy on a real switch (not the first adoption), unless the leader is Spiritual.
	if p.state_religion != "" and not ("spiritual" in p.traits):
		p.transition_turns = _db.get_constant("state_religion_anarchy_turns", 1)
	p.state_religion = belief_id
	if belief_id == "":
		_add_notification(p.name + " abandoned their state religion.", "major")
	else:
		var belief_name: String = str(_db.beliefs.get(belief_id, {}).get("name", belief_id))
		_add_notification(p.name + " declared " + belief_name + " as state religion.", "major")
	_dirty.set_dirty(IDs.DirtyRegion.FULL_SCREENS)
	_dirty.set_dirty(IDs.DirtyRegion.HUD_GROUPS)
	return true

func _cmd_declare_war(cmd: Dictionary) -> bool:
	var p: Player = _gs.get_player(int(cmd["player_id"]))
	if p == null:
		return false
	var target_aid: int = int(cmd["target_alliance_id"])
	var alliance: Alliance = _gs.get_player_alliance(p.id)
	if alliance == null or alliance.id == target_aid:
		return false
	if not alliance.at_war_with in [target_aid]:
		alliance.at_war_with.append(target_aid)
	# Ensure contact
	if not alliance.has_contact_with(target_aid):
		alliance.contacts.append(target_aid)
	_add_notification(p.name + " declared war on " + _alliance_label(target_aid) + "!", "major")
	return true

func _cmd_make_peace(cmd: Dictionary) -> bool:
	var p: Player = _gs.get_player(int(cmd["player_id"]))
	if p == null:
		return false
	var target_aid: int = int(cmd["target_alliance_id"])
	var alliance: Alliance = _gs.get_player_alliance(p.id)
	if alliance == null:
		return false
	alliance.at_war_with.erase(target_aid)
	_add_notification(p.name + " made peace with " + _alliance_label(target_aid) + ".", "major")
	return true

# Propose a permanent alliance with another alliance (§optional rule). Requires
# the permanent_alliances rule to be active and both sides to not already be at
# war or already permanently allied. The alliance is immediate and mutual — it is
# a voluntary act by the acting player, not a negotiation awaiting acceptance.
func _cmd_propose_permanent_alliance(cmd: Dictionary) -> bool:
	if not _gs.permanent_alliances:
		return false
	var p: Player = _gs.get_player(int(cmd["player_id"]))
	if p == null:
		return false
	var target_aid: int = int(cmd["target_alliance_id"])
	var mine: Alliance = _gs.get_player_alliance(p.id)
	var other: Alliance = _gs.get_alliance(target_aid)
	if mine == null or other == null or mine.id == target_aid:
		return false
	# Cannot form a permanent alliance while at war.
	if mine.is_at_war_with(target_aid):
		return false
	# Already permanently allied: no duplicate.
	if target_aid in mine.permanent_allies:
		return false
	# Record the alliance on both sides (mutual and permanent).
	if not (target_aid in mine.permanent_allies):
		mine.permanent_allies.append(target_aid)
	if not (mine.id in other.permanent_allies):
		other.permanent_allies.append(mine.id)
	# Ensure both sides have contact (declaring/forming alliance implies contact).
	if not mine.has_contact_with(target_aid):
		mine.contacts.append(target_aid)
	if not other.has_contact_with(mine.id):
		other.contacts.append(mine.id)
	_add_notification(p.name + " formed a permanent alliance with "
		+ _alliance_label(target_aid) + "!", "major")
	_dirty.set_dirty(IDs.DirtyRegion.FULL_SCREENS)
	return true

func _cmd_rush_production(cmd: Dictionary) -> bool:
	var p: Player = _gs.get_player(int(cmd["player_id"]))
	if p == null:
		return false
	var s: Settlement = _gs.get_settlement(int(cmd["settlement_id"]))
	if s == null or s.owner_player_id != p.id:
		return false
	if s.production_queue.empty():
		return false
	var method: String = str(cmd.get("method", "treasury"))
	var item: Dictionary = s.production_queue[0]
	var pace: Dictionary = _db.get_pace(_gs.pace_id)
	var cost: int = TurnEngine._item_cost(item, _db, p, pace)
	var remaining: int = max(0, cost - s.production_store)
	match method:
		"treasury":
			# Rushing with gold requires a civic that allows it (Universal Suffrage, §8).
			if not PolicyEffects.has_flag(p, _db, "can_rush_with_gold"):
				return false
			if p.treasury < remaining:
				return false
			p.treasury -= remaining
			s.production_store = cost
		"population":
			# Sacrificing population requires a civic that allows it (Slavery, §8).
			if not PolicyEffects.has_flag(p, _db, "rush_by_pop"):
				return false
			if s.population <= 1:
				return false
			s.population -= 1
			s.food_store = 0
			s.production_store = cost
	s.rush_anger_turns = 5
	return true

func _cmd_build_improvement(cmd: Dictionary) -> bool:
	var p: Player = _gs.get_player(int(cmd["player_id"]))
	if p == null:
		return false
	var u: Unit = _gs.get_unit(int(cmd["unit_id"]))
	if u == null or u.owner_player_id != p.id:
		return false
	var udata: Dictionary = _db.get_unit(u.unit_type_id)
	if not udata.get("can_build", false):
		return false
	var imp_id: String = str(cmd.get("improvement_id", ""))
	var imp: Dictionary = _db.get_improvement(imp_id)
	if imp.empty():
		return false
	# Upgrade-only improvements (e.g. hamlet/village/town) are placed by the
	# cottage growth system, never by direct command.
	if bool(imp.get("upgrade_only", false)):
		return false
	# Validate the tile's landform against the improvement's allowed list.
	var tile: Tile = _gs.map.get_tile(u.x, u.y)
	if tile == null:
		return false
	var ter: Dictionary = _db.get_terrain(tile.terrain_id)
	var landform: String = str(ter.get("landform", "flat"))
	var allowed: Array = imp.get("allowed_landforms", [])
	if not allowed.empty() and not (landform in allowed):
		return false
	# Validate the tech requirement.
	var tech_req = imp.get("tech_required", null)
	if tech_req != null and str(tech_req) != "" and not p.has_tech(str(tech_req)):
		return false
	# Validate river requirement (watermill etc.).
	if bool(imp.get("requires_river", false)):
		var has_river: bool = tile.river_n or tile.river_w
		if not has_river:
			var s_tile: Tile = _gs.map.get_tile(u.x, u.y + 1)
			if s_tile != null and s_tile.river_n:
				has_river = true
		if not has_river:
			var e_tile: Tile = _gs.map.get_tile(u.x + 1, u.y)
			if e_tile != null and e_tile.river_w:
				has_river = true
		if not has_river:
			return false
	# Validate feature requirement (lumbermill needs forest, etc.).
	var req_feat: String = str(imp.get("requires_feature", ""))
	if req_feat != "" and tile.feature_id != req_feat:
		return false
	u.building_improvement = imp_id
	# Serfdom speeds improvement construction (§8): fewer build turns.
	var bt: int = int(imp.get("build_turns", 5))
	var worker_speed: int = PolicyEffects.sum_int(p, _db, "worker_speed_bonus")
	if worker_speed > 0:
		bt = (bt * 100) / (100 + worker_speed)
		if bt < 1:
			bt = 1
	u.build_turns_left = bt
	u.has_moved = true
	u.movement_left = 0
	return true

# ── Trades (§7) ───────────────────────────────────────────────────────────────

func _cmd_propose_trade(cmd: Dictionary) -> bool:
	var p: Player = _gs.get_player(int(cmd["player_id"]))
	if p == null:
		return false
	var from_alliance: Alliance = _gs.get_player_alliance(p.id)
	var target_aid: int = int(cmd.get("target_alliance_id", -1))
	var to_alliance: Alliance = _gs.get_alliance(target_aid)
	if from_alliance == null or to_alliance == null or from_alliance.id == target_aid:
		return false
	# A standing assembly trade embargo (§7.2) bars commerce with the sanctioned
	# alliance, on either side of the deal.
	var embargo: int = int(_gs.assembly.get("standing", {}).get("trade_embargo", -1))
	if embargo >= 0 and (target_aid == embargo or from_alliance.id == embargo):
		_add_notification("Trade barred by assembly embargo.", "info")
		return false
	var duration: int = int(cmd.get("duration", -1))
	if duration <= 0:
		duration = _db.get_constant("trade_default_duration", 20)
	from_alliance.pending_trades.append({
		"id": _gs.next_trade_id(),
		"proposer_player_id": p.id,
		"from_alliance": from_alliance.id,
		"to_alliance": target_aid,
		"give": cmd.get("give", {}).duplicate(true),
		"receive": cmd.get("receive", {}).duplicate(true),
		"peace": bool(cmd.get("peace", false)),
		"expires_turn": _gs.turn_number + duration
	})
	if not from_alliance.has_contact_with(target_aid):
		from_alliance.contacts.append(target_aid)
	_dirty.set_dirty(IDs.DirtyRegion.DATA_PANES)
	return true

func _cmd_accept_trade(cmd: Dictionary) -> bool:
	var p: Player = _gs.get_player(int(cmd["player_id"]))
	if p == null:
		return false
	var trade_id: int = int(cmd.get("trade_id", -1))
	for alliance in _gs.alliances:
		for i in range(alliance.pending_trades.size()):
			var t: Dictionary = alliance.pending_trades[i]
			if int(t.get("id", -1)) == trade_id and int(t.get("to_alliance", -1)) == p.alliance_id:
				_execute_trade(t, p)
				alliance.pending_trades.remove(i)
				_dirty.set_dirty(IDs.DirtyRegion.DATA_PANES)
				return true
	return false

func _cmd_reject_trade(cmd: Dictionary) -> bool:
	var p: Player = _gs.get_player(int(cmd["player_id"]))
	if p == null:
		return false
	var trade_id: int = int(cmd.get("trade_id", -1))
	for alliance in _gs.alliances:
		for i in range(alliance.pending_trades.size()):
			var t: Dictionary = alliance.pending_trades[i]
			if int(t.get("id", -1)) == trade_id and int(t.get("to_alliance", -1)) == p.alliance_id:
				alliance.pending_trades.remove(i)
				return true
	return false

# Move gold/techs between the proposer and accepter and apply any peace clause.
func _execute_trade(t: Dictionary, accepter: Player) -> void:
	var proposer: Player = _gs.get_player(int(t.get("proposer_player_id", -1)))
	var give: Dictionary = t.get("give", {})       # proposer -> accepter
	var receive: Dictionary = t.get("receive", {}) # accepter -> proposer
	if proposer != null:
		var gg: int = int(give.get("gold", 0))
		var rg: int = int(receive.get("gold", 0))
		proposer.treasury -= gg; accepter.treasury += gg
		accepter.treasury -= rg; proposer.treasury += rg
		for tech in give.get("techs", []):
			if not accepter.has_tech(tech):
				accepter.technologies.append(tech)
		for tech in receive.get("techs", []):
			if not proposer.has_tech(tech):
				proposer.technologies.append(tech)
		var parts: Array = []
		if gg > 0: parts.append(str(gg) + " gold to " + accepter.name)
		if rg > 0: parts.append(str(rg) + " gold to " + proposer.name)
		var give_techs: Array = give.get("techs", [])
		var recv_techs: Array = receive.get("techs", [])
		if not give_techs.empty(): parts.append("tech to " + accepter.name)
		if not recv_techs.empty(): parts.append("tech to " + proposer.name)
		if not parts.empty():
			_add_notification(proposer.name + " and " + accepter.name + " traded: " + ", ".join(parts) + ".", "info")
	if bool(t.get("peace", false)):
		var a_from: Alliance = _gs.get_alliance(int(t.get("from_alliance", -1)))
		var a_to: Alliance = _gs.get_alliance(int(t.get("to_alliance", -1)))
		if a_from != null and a_to != null:
			a_from.at_war_with.erase(a_to.id)
			a_to.at_war_with.erase(a_from.id)
			_add_notification(_alliance_label(a_from.id) + " and " + _alliance_label(a_to.id)
				+ " agreed to peace.", "major")

# ── Subordination (§7) ────────────────────────────────────────────────────────

# The acting player's alliance becomes a tributary of the overlord alliance:
# their war ends, the subordinate joins the overlord's wars, and tribute is paid
# each world step.
func _cmd_set_subordination(cmd: Dictionary) -> bool:
	var p: Player = _gs.get_player(int(cmd["player_id"]))
	if p == null:
		return false
	var mine: Alliance = _gs.get_player_alliance(p.id)
	var overlord_id: int = int(cmd.get("overlord_alliance_id", -1))
	var overlord: Alliance = _gs.get_alliance(overlord_id)
	if mine == null or overlord == null or mine.id == overlord_id:
		return false
	mine.is_subordinate_to = overlord_id
	if not (mine.id in overlord.tributaries):
		overlord.tributaries.append(mine.id)
	mine.at_war_with.erase(overlord_id)
	overlord.at_war_with.erase(mine.id)
	for enemy_aid in overlord.at_war_with:
		if not (enemy_aid in mine.at_war_with):
			mine.at_war_with.append(enemy_aid)
	_add_notification(p.name + " became a tributary of " + _alliance_label(overlord_id) + ".", "major")
	_dirty.set_dirty(IDs.DirtyRegion.FULL_SCREENS)
	return true

# ── Specialists (§6.5) ────────────────────────────────────────────────────────

func _cmd_assign_specialist(cmd: Dictionary) -> bool:
	var p: Player = _gs.get_player(int(cmd["player_id"]))
	if p == null:
		return false
	var s: Settlement = _gs.get_settlement(int(cmd.get("settlement_id", -1)))
	if s == null or s.owner_player_id != p.id:
		return false
	var stype: String = str(cmd.get("specialist_type", ""))
	var count: int = int(cmd.get("count", 0))
	if stype == "" or count < 0:
		return false
	# Total specialists may not exceed the settlement's population.
	var others: int = 0
	for k in s.specialists:
		if k != stype:
			others += int(s.specialists[k])
	if others + count > s.population:
		return false
	if count == 0:
		s.specialists.erase(stype)
	else:
		s.specialists[stype] = count
	_dirty.set_dirty(IDs.DirtyRegion.DATA_PANES)
	return true

# Lock or unlock a tile as worked by a city (§11 city screen). A locked tile is
# always worked (capacity permitting); unlocking removes the lock. After the
# change the player's worked tiles are recomputed immediately so the city screen
# reflects it at once (output stays turn-cached and refreshes next turn).
func _cmd_set_tile_worked(cmd: Dictionary) -> bool:
	var p: Player = _gs.get_player(int(cmd["player_id"]))
	if p == null:
		return false
	var s: Settlement = _gs.get_settlement(int(cmd.get("settlement_id", -1)))
	if s == null or s.owner_player_id != p.id:
		return false
	var tx: int = int(cmd.get("x", -999))
	var ty: int = int(cmd.get("y", -999))
	if not _gs.map.is_valid(tx, ty):
		return false
	# The tile must be within the city's worked radius and ownable by the player.
	var in_range: bool = false
	for tile in _gs.map.tiles_in_range(s.x, s.y, s.culture_ring):
		if tile.x == tx and tile.y == ty:
			if tile.owner_player_id == p.id or tile.owner_player_id == -1:
				in_range = true
			break
	if not in_range:
		return false
	var worked: bool = bool(cmd.get("worked", true))
	var idx: int = -1
	for i in range(s.locked_tiles.size()):
		if int(s.locked_tiles[i][0]) == tx and int(s.locked_tiles[i][1]) == ty:
			idx = i
			break
	if worked and idx < 0:
		s.locked_tiles.append([tx, ty])
	elif not worked and idx >= 0:
		s.locked_tiles.remove(idx)
	TurnEngine._auto_assign_workers(_gs, p)
	_dirty.set_dirty(IDs.DirtyRegion.DATA_PANES)
	return true

# Toggle a city's automatic citizen management (§11 city screen). When off, only
# the player's locked tiles are worked; when on, unlocked worker slots auto-fill.
func _cmd_set_citizen_automation(cmd: Dictionary) -> bool:
	var p: Player = _gs.get_player(int(cmd["player_id"]))
	if p == null:
		return false
	var s: Settlement = _gs.get_settlement(int(cmd.get("settlement_id", -1)))
	if s == null or s.owner_player_id != p.id:
		return false
	s.manage_citizens_auto = bool(cmd.get("auto", true))
	TurnEngine._auto_assign_workers(_gs, p)
	_dirty.set_dirty(IDs.DirtyRegion.DATA_PANES)
	return true

# ── Great Person actions (§14) ────────────────────────────────────────────────

# Direct a Great Person unit to perform one of its data-defined actions. Extra
# command keys (settlement_id, target_alliance_id, tech_id, org_id) are passed
# through as params; the GreatPeople module validates the action against the
# unit's own "actions" list.
func _cmd_gp_action(cmd: Dictionary) -> bool:
	var player_id: int = int(cmd["player_id"])
	var u: Unit = _gs.get_unit(int(cmd.get("unit_id", -1)))
	if u == null or u.owner_player_id != player_id:
		return false
	var action: String = str(cmd.get("action", ""))
	var params: Dictionary = {}
	for k in cmd:
		if k != "type" and k != "player_id" and k != "unit_id" and k != "action":
			params[k] = cmd[k]
	var p_gp: Player = _gs.get_player(player_id)
	var was_in_golden_age: bool = p_gp != null and GreatPeople.is_in_golden_age(p_gp)
	if not GreatPeople.perform_action(_gs, u, action, params):
		return false
	if p_gp != null:
		var udata_gp: Dictionary = _db.get_unit(u.unit_type_id)
		var gp_name: String = str(udata_gp.get("name", u.unit_type_id))
		match action:
			"start_golden_age":
				if GreatPeople.is_in_golden_age(p_gp) and not was_in_golden_age:
					_add_notification(p_gp.name + " has entered a Golden Age!", "major")
				else:
					_add_notification(gp_name + " contributed to the next Golden Age.", "info")
			"trade_mission":
				_add_notification(gp_name + " completed a trade mission.", "info")
			"found_religion":
				_add_notification(gp_name + " founded a new religion.", "major")
			"discover_technology":
				_add_notification(gp_name + " discovered a technology.", "major")
	_dirty.mark_all()
	return true

# ── Espionage (§7) ────────────────────────────────────────────────────────────

func _cmd_espionage_mission(cmd: Dictionary) -> bool:
	var p: Player = _gs.get_player(int(cmd["player_id"]))
	if p == null:
		return false
	var target_aid: int = int(cmd.get("target_alliance_id", -1))
	var target_alliance: Alliance = _gs.get_alliance(target_aid)
	if target_alliance == null or target_aid == p.alliance_id:
		return false
	var have: int = int(p.intel_points.get(target_aid, 0))
	var cost: int = _espionage_mission_cost(p, target_alliance, have)
	if have < cost:
		return false
	p.intel_points[target_aid] = have - cost
	# A defender's espionage_defense structures raise the interception chance;
	# interception spends the points but fails the mission (§7, §15.5).
	if _gs.rng.rand_bool_percent(_espionage_interception_chance(target_alliance)):
		_add_notification("Espionage mission intercepted.", "info")
		return true
	match str(cmd.get("mission", "")):
		"steal_tech":
			_espionage_steal_tech(p, target_alliance)
		"sabotage":
			_espionage_sabotage(target_alliance)
		"incite_unrest":
			_espionage_incite_unrest(target_alliance)
	return true

# Public query: EP cost for the current player to run any mission against
# target_alliance_id. Returns 0 when state is unavailable or the target is
# invalid, so callers can safely use the result to gate UI buttons.
func get_espionage_mission_cost(target_alliance_id: int) -> int:
	if _gs == null:
		return 0
	var p: Player = _gs.get_player(_gs.current_player_id)
	if p == null:
		return 0
	var target: Alliance = _gs.get_alliance(target_alliance_id)
	if target == null:
		return 0
	var have: int = int(p.intel_points.get(target_alliance_id, 0))
	return _espionage_mission_cost(p, target, have)

# Public query: interception percentage for missions against target_alliance_id.
func get_espionage_interception_chance(target_alliance_id: int) -> int:
	if _gs == null:
		return 0
	var target: Alliance = _gs.get_alliance(target_alliance_id)
	if target == null:
		return 0
	return _espionage_interception_chance(target)

# §15.5 mission cost (provisional): base × (1 + EP-advantage/100). The advantage
# is how much more espionage the target holds against the attacker than the
# attacker holds against the target — a well-defended rival costs more to hit.
# When the attacker is ahead the advantage is zero (cost floors at base).
func _espionage_mission_cost(attacker: Player, target: Alliance, attacker_ep: int) -> int:
	var base: int = _db.get_constant("intel_mission_cost", 100)
	var defender_ep: int = 0
	for pid in target.member_player_ids:
		var member: Player = _gs.get_player(pid)
		if member != null:
			defender_ep += int(member.intel_points.get(attacker.alliance_id, 0))
	if defender_ep <= attacker_ep:
		return base
	var advantage: int = (defender_ep - attacker_ep) * 100 / (attacker_ep if attacker_ep > 0 else 1)
	var cap: int = _db.get_constant("intel_cost_advantage_max", 200)
	if advantage > cap:
		advantage = cap
	return base + base * advantage / 100

# Interception chance against missions targeting this alliance: the base chance
# plus the strongest espionage_defense structure across the target's cities,
# capped (§15.5, provisional).
func _espionage_interception_chance(target: Alliance) -> int:
	var defense: int = 0
	for s in _gs.settlements:
		var owner: Player = _gs.get_player(s.owner_player_id)
		if owner == null or owner.alliance_id != target.id:
			continue
		for struct_id in s.structures:
			var d: int = int(_db.get_structure(struct_id).get("effects", {}).get("espionage_defense", 0))
			if d > defense:
				defense = d
	var chance: int = _db.get_constant("intel_interception_chance", 25) + defense
	var cap: int = _db.get_constant("intel_interception_max", 90)
	return cap if chance > cap else chance

func _espionage_steal_tech(thief: Player, target: Alliance) -> void:
	for pid in target.member_player_ids:
		var victim: Player = _gs.get_player(pid)
		if victim == null:
			continue
		for tech in victim.technologies:
			if not thief.has_tech(tech):
				thief.technologies.append(tech)
				_add_notification("Stole technology: " + str(tech), "major")
				return

func _espionage_sabotage(target: Alliance) -> void:
	for s in _gs.settlements:
		var owner: Player = _gs.get_player(s.owner_player_id)
		if owner != null and owner.alliance_id == target.id:
			s.production_store = s.production_store / 2
			_add_notification("Sabotaged production in " + s.name, "major")
			return

# Incite unrest: tip the target alliance's most populous city into disorder so
# it produces nothing until its owner restores order (§7, provisional).
func _espionage_incite_unrest(target: Alliance) -> void:
	var worst: Settlement = null
	for s in _gs.settlements:
		var owner: Player = _gs.get_player(s.owner_player_id)
		if owner == null or owner.alliance_id != target.id:
			continue
		if worst == null or s.population > worst.population \
				or (s.population == worst.population and s.id < worst.id):
			worst = s
	if worst != null:
		worst.in_disorder = true
		worst.discontented = worst.population
		_add_notification("Incited unrest in " + worst.name, "major")

# ── Transport / embarkation (§5.2) ────────────────────────────────────────────

func _cmd_load_unit(cmd: Dictionary) -> bool:
	var p: Player = _gs.get_player(int(cmd["player_id"]))
	if p == null:
		return false
	var u: Unit = _gs.get_unit(int(cmd.get("unit_id", -1)))
	var t: Unit = _gs.get_unit(int(cmd.get("transport_id", -1)))
	if u == null or t == null or u.owner_player_id != p.id or t.owner_player_id != p.id:
		return false
	if _db.get_unit(u.unit_type_id).get("domain", "land") != "land":
		return false
	var cap: int = int(_db.get_unit(t.unit_type_id).get("transport_capacity", 0))
	if cap <= 0 or t.cargo.size() >= cap:
		return false
	if _gs.map.distance(u.x, u.y, t.x, t.y) > 1:
		return false
	u.x = t.x; u.y = t.y
	u.transported_by = t.id
	u.movement_left = 0; u.has_moved = true
	if not (u.id in t.cargo):
		t.cargo.append(u.id)
	_dirty.set_dirty(IDs.DirtyRegion.WORLD)
	return true

func _cmd_unload_unit(cmd: Dictionary) -> bool:
	var p: Player = _gs.get_player(int(cmd["player_id"]))
	if p == null:
		return false
	var u: Unit = _gs.get_unit(int(cmd.get("unit_id", -1)))
	if u == null or u.owner_player_id != p.id or u.transported_by < 0:
		return false
	var tx: int = int(cmd.get("target_x", u.x))
	var ty: int = int(cmd.get("target_y", u.y))
	if _gs.map.distance(u.x, u.y, tx, ty) > 1:
		return false
	var tile: Tile = _gs.map.get_tile(tx, ty)
	if tile == null or _db.get_terrain(tile.terrain_id).get("domain", "land") != "land":
		return false
	var t: Unit = _gs.get_unit(u.transported_by)
	if t != null:
		t.cargo.erase(u.id)
	u.transported_by = -1
	u.x = tx; u.y = ty
	u.movement_left = 0; u.has_moved = true
	_dirty.set_dirty(IDs.DirtyRegion.WORLD)
	return true

# ── Helpers ───────────────────────────────────────────────────────────────────

# Apply a resolved unit-vs-unit combat to state. Thin wrapper over the shared
# pure CombatApply sim module (also used by WildAI); callers emit combat_resolved.
func _apply_combat_result(attacker: Unit, defender: Unit,
		result: Dictionary, advance: bool = true) -> void:
	CombatApply.apply_unit_result(_gs, attacker, defender, result, advance)

# An enemy fighter near the target may intercept an inbound air strike. Returns
# true if the strike is aborted (the bomber was engaged), resolving the air-to-air
# combat as a side effect (§5.2).
func _resolve_interception(bomber: Unit, tx: int, ty: int, player_id: int) -> bool:
	var reach: int = _db.get_constant("interception_range", 2)
	var interceptor: Unit = null
	var best_d: int = 999
	for u in _gs.units:
		if u.owner_player_id == player_id:
			continue
		if _db.get_unit(u.unit_type_id).get("domain", "") != "air":
			continue
		if u.owner_player_id != -2 and not _gs.are_at_war(player_id, u.owner_player_id):
			continue
		var d: int = _gs.map.distance(tx, ty, u.x, u.y)
		if d <= reach and d < best_d:
			interceptor = u; best_d = d
	if interceptor == null:
		return false
	if not _gs.rng.rand_bool_percent(_db.get_constant("interception_chance", 50)):
		return false
	# The interceptor engages the bomber (no advance for either side).
	var ir: Dictionary = Combat.resolve(interceptor, bomber, _gs, _gs.rng)
	_apply_combat_result(interceptor, bomber, ir, false)
	emit_signal("combat_resolved", ir)
	_add_combat_notification(interceptor, bomber, ir)
	return true

# Spread a religion to a city with a missionary unit (§8). The missionary must be
# the player's, carry the `spread_religion` tag, and sit on the target city's tile.
# It spreads the player's religion (state religion, else a belief the player
# founded or whose faith its cities hold) to a city that has none, respecting
# Theocracy's non-state-spread block. The missionary is consumed on success.
func _cmd_spread_belief(cmd: Dictionary) -> bool:
	var p: Player = _gs.get_player(int(cmd["player_id"]))
	if p == null:
		return false
	var u: Unit = _gs.get_unit(int(cmd.get("unit_id", -1)))
	if u == null or u.owner_player_id != p.id:
		return false
	if not ("spread_religion" in _db.get_unit(u.unit_type_id).get("tags", [])):
		return false
	var s: Settlement = _gs.get_settlement(int(cmd.get("settlement_id", -1)))
	if s == null or s.x != u.x or s.y != u.y:
		return false
	if s.belief_id != "":
		return false  # single-belief model: only converts a faithless city
	var belief_id: String = _belief_to_spread(p)
	if belief_id == "":
		return false
	if Beliefs._spread_blocked(_gs, _db, s, belief_id):
		return false
	s.belief_id = belief_id
	Stack.remove_unit(_gs.units, u.id)
	if _selection != null:
		_selection.selected_unit_ids.erase(u.id)
	var belief_name: String = str(_db.beliefs.get(belief_id, {}).get("name", belief_id))
	_add_notification(belief_name + " spread to " + s.name + ".", "info")
	_dirty.set_dirty(IDs.DirtyRegion.WORLD)
	_dirty.set_dirty(IDs.DirtyRegion.DATA_PANES)
	return true

# The religion a player's missionary carries: the state religion if adopted, else
# a belief the player founded, else one its cities already follow. "" if none.
func _belief_to_spread(p: Player) -> String:
	if p.state_religion != "":
		return p.state_religion
	for bid in _gs.founded_beliefs:
		if int(_gs.founded_beliefs[bid]) == p.id:
			return bid
	for s in _gs.settlements:
		if s.owner_player_id == p.id and s.belief_id != "":
			return s.belief_id
	return ""

# Conscript a military unit from a city (§6.4). Requires the can_draft civic
# (Nationhood); spends population and stirs unhappiness; the drafted unit is the
# most advanced draftable unit the player has the technology for.
func _cmd_draft(cmd: Dictionary) -> bool:
	var p: Player = _gs.get_player(int(cmd["player_id"]))
	if p == null:
		return false
	if not PolicyEffects.has_flag(p, _db, "can_draft"):
		return false
	var s: Settlement = _gs.get_settlement(int(cmd.get("settlement_id", -1)))
	if s == null or s.owner_player_id != p.id:
		return false
	if s.in_disorder:
		return false
	var min_pop: int = _db.get_constant("draft_min_population", 2)
	if s.population < min_pop:
		return false
	var unit_id: String = _draftable_unit(p)
	if unit_id == "":
		return false
	# Spend population and stir conscription unhappiness (reuses the rush-anger
	# channel that feeds contentment).
	var pop_cost: int = _db.get_constant("draft_population_cost", 1)
	s.population -= pop_cost
	if s.population < 1:
		s.population = 1
	s.food_store = 0
	var anger: int = _db.get_constant("draft_anger_turns", 5)
	if s.rush_anger_turns < anger:
		s.rush_anger_turns = anger
	# Raise the unit at the city. Drafted units come only with civic XP (no
	# building XP), reflecting their reduced training.
	var u := Unit.new()
	u.id = _gs.next_unit_id()
	u.unit_type_id = unit_id
	u.owner_player_id = p.id
	u.x = s.x; u.y = s.y
	var udata: Dictionary = _db.get_unit(unit_id)
	u.base_strength = int(udata.get("base_strength", 5))
	u.movement_total = int(udata.get("movement", 200))
	u.movement_left = u.movement_total
	u.experience = PolicyEffects.sum_int(p, _db, "new_unit_xp")
	_gs.units.append(u)
	emit_signal("unit_created", u.id)
	_dirty.set_dirty(IDs.DirtyRegion.WORLD)
	_dirty.set_dirty(IDs.DirtyRegion.HUD_GROUPS)
	return true

# The most advanced draftable unit (data `draftable`) whose tech the player holds,
# ranked by base strength. "" when none is available.
func _draftable_unit(p: Player) -> String:
	var best_id: String = ""
	var best_str: int = -1
	for uid in _db.units:
		var ud: Dictionary = _db.units[uid]
		if not ud.get("draftable", false):
			continue
		var tech: String = str(ud.get("tech_required", ""))
		if tech != "" and not p.has_tech(tech):
			continue
		var st: int = int(ud.get("base_strength", 0))
		if st > best_str:
			best_str = st
			best_id = uid
	return best_id

# Launch a one-use nuclear weapon at a target tile (§5.7). The missile is consumed
# whether or not it is intercepted. Forbidden while a Non-Proliferation resolution
# (`no_nuclear`) is in force.
func _cmd_nuclear_strike(cmd: Dictionary) -> bool:
	var player_id: int = int(cmd["player_id"])
	var u: Unit = _gs.get_unit(int(cmd.get("unit_id", -1)))
	if u == null or u.owner_player_id != player_id:
		return false
	if not Nuclear.is_nuke(_db, u):
		return false
	if not Nuclear.nukes_enabled(_gs):
		return false
	# Non-Proliferation in force: launching is forbidden (§5.7 / §7.2).
	if bool(_gs.assembly.get("standing", {}).get("no_nuclear", false)):
		return false
	var tx: int = int(cmd.get("target_x", -1))
	var ty: int = int(cmd.get("target_y", -1))
	if not _gs.map.is_valid(tx, ty):
		return false
	# Range: a `global_range` weapon (ICBM) reaches any tile; otherwise air_range.
	var udata: Dictionary = _db.get_unit(u.unit_type_id)
	if not ("global_range" in udata.get("tags", [])):
		var reach: int = int(udata.get("air_range", 12))
		if _gs.map.distance(u.x, u.y, tx, ty) > reach:
			return false

	# The unit is spent on launch; remove it first so it is never caught in its own
	# blast (we still hold the reference for owner/type lookups in detonate).
	Stack.remove_unit(_gs.units, u.id)
	if _selection != null:
		_selection.selected_unit_ids.erase(u.id)

	# Interception aborts the strike with no effect on the target.
	if Nuclear.try_intercept(_gs, u, tx, ty, _gs.rng):
		var p_nuke: Player = _gs.get_player(player_id)
		var who_nuke: String = p_nuke.name if p_nuke != null else "A nuclear weapon"
		_add_notification(who_nuke + "'s nuclear strike was intercepted!", "major")
		emit_signal("event_emitted", {
			"type": "nuclear_intercepted",
			"player_id": player_id, "target_x": tx, "target_y": ty
		})
		_dirty.set_dirty(IDs.DirtyRegion.WORLD)
		_dirty.set_dirty(IDs.DirtyRegion.HUD_GROUPS)
		return true

	var result: Dictionary = Nuclear.detonate(_gs, u, tx, ty, _gs.rng)

	# A strike is an act of war: declare war on every victim's alliance (§5.7).
	var attacker_alliance: Alliance = _gs.get_player_alliance(player_id)
	if attacker_alliance != null:
		for aid in result["victim_alliance_ids"]:
			if aid == attacker_alliance.id:
				continue
			if not attacker_alliance.is_at_war_with(aid):
				attacker_alliance.at_war_with.append(aid)
			if not attacker_alliance.has_contact_with(aid):
				attacker_alliance.contacts.append(aid)

	var p_nuke2: Player = _gs.get_player(player_id)
	var who_nuke2: String = p_nuke2.name if p_nuke2 != null else "A nuclear weapon"
	_add_notification(who_nuke2 + " detonated a nuclear weapon at (" + str(tx) + "," + str(ty) + ")!", "major")
	emit_signal("nuclear_detonated", result)
	_dirty.set_dirty(IDs.DirtyRegion.WORLD)
	_dirty.set_dirty(IDs.DirtyRegion.HUD_GROUPS)
	_dirty.set_dirty(IDs.DirtyRegion.DATA_PANES)
	return true

# True if a hostile unit (wild, or an enemy at war) occupies a tile adjacent to
# (x, y). Used to apply zones of control (§5.2).
func _adjacent_hostile(x: int, y: int, player_id: int) -> bool:
	for nb in _gs.map.neighbours8(x, y):
		for u in _gs.units:
			if u.x != nb.x or u.y != nb.y or u.owner_player_id == player_id:
				continue
			if u.owner_player_id == -2 or _gs.are_at_war(player_id, u.owner_player_id):
				return true
	return false

func _get_next_player_index(current_player_id: int) -> int:
	for i in range(_gs.players.size()):
		if _gs.players[i].id == current_player_id:
			return (i + 1) % _gs.players.size()
	return 0

# ── New command handlers ───────────────────────────────────────────────────────

func _cmd_unit_command(cmd: Dictionary) -> bool:
	var player_id: int = int(cmd["player_id"])
	var unit_id: int = int(cmd.get("unit_id", -1))
	var u: Unit = _gs.get_unit(unit_id)
	if u == null or u.owner_player_id != player_id:
		return false

	var ctype: int = int(cmd.get("type", -1))
	match ctype:
		IDs.CommandType.UNIT_WAKE:
			u.is_fortified = false
			u.is_sentry = false
			u.is_patrolling = false
			u.is_healing = false
			u.is_sleeping = false
			u.is_sleep_until_healed = false
			u.is_fortify_until_healed = false
			u.is_exploring = false
			u.has_moved = false
			u.movement_left = u.movement_total
		IDs.CommandType.UNIT_SLEEP:
			# Sleep is a skip-until-woken order, distinct from fortify, so the UI can
			# show it as "Sleeping". It still ends the unit's turn.
			u.is_sleeping = true
			u.has_moved = true
			u.movement_left = 0
		IDs.CommandType.UNIT_FORTIFY:
			u.is_fortified = true
			u.has_moved = true
			u.movement_left = 0
		IDs.CommandType.UNIT_CANCEL_ORDERS:
			u.building_improvement = ""
			u.build_turns_left = 0
			u.is_sleeping = false
			u.is_sleep_until_healed = false
			u.is_fortify_until_healed = false
			u.is_exploring = false
			u.goto_x = -1
			u.goto_y = -1
			u.has_moved = false
			u.movement_left = u.movement_total
		IDs.CommandType.UNIT_DISBAND:
			Stack.remove_unit(_gs.units, unit_id)
		IDs.CommandType.UNIT_PROMOTE:
			var promo_id: String = str(cmd.get("promotion_id", ""))
			if promo_id == "" or promo_id in u.promotions:
				return false
			u.promotions.append(promo_id)
		IDs.CommandType.UNIT_UPGRADE:
			var udata: Dictionary = _db.get_unit(u.unit_type_id)
			var upgrades_to: String = str(udata.get("upgrades_to", ""))
			if upgrades_to == "":
				return false
			var new_udata: Dictionary = _db.get_unit(upgrades_to)
			if new_udata.empty():
				return false
			var cost: int = int(new_udata.get("cost", 0)) - int(udata.get("cost", 0))
			var p: Player = _gs.get_player(player_id)
			if p == null or p.treasury < cost:
				return false
			p.treasury -= cost
			u.unit_type_id = upgrades_to
			u.base_strength = int(new_udata.get("base_strength", u.base_strength))
		IDs.CommandType.UNIT_GIFT:
			var target_id: int = int(cmd.get("target_player_id", -1))
			var target: Player = _gs.get_player(target_id)
			if target == null or target_id == player_id:
				return false
			# Cargo travels with its transport; reassign it too.
			for cargo_id in u.cargo:
				var c: Unit = _gs.get_unit(cargo_id)
				if c != null:
					c.owner_player_id = target_id
			u.owner_player_id = target_id
			_selection.selected_unit_ids.erase(unit_id)
		_:
			return false

	_dirty.set_dirty(IDs.DirtyRegion.WORLD)
	_dirty.set_dirty(IDs.DirtyRegion.HUD_GROUPS)
	return true

func _cmd_mission(cmd: Dictionary) -> bool:
	var player_id: int = int(cmd["player_id"])
	var unit_id: int = int(cmd.get("unit_id", -1))
	var u: Unit = _gs.get_unit(unit_id)
	if u == null or u.owner_player_id != player_id:
		return false

	var ctype: int = int(cmd.get("type", -1))
	match ctype:
		IDs.CommandType.MISSION_SKIP_TURN:
			u.has_moved = true
			u.movement_left = 0
		IDs.CommandType.MISSION_MOVE_TO:
			# A per-unit move order: only this unit leaves the tile, so it can be
			# peeled off a stack (unlike MOVE_STACK with no unit_ids, which moves
			# the whole tile together). A manual move cancels the explore mission.
			u.is_exploring = false
			var mc: Dictionary = {
				"type": IDs.CommandType.MOVE_STACK,
				"player_id": player_id,
				"from_x": u.x, "from_y": u.y,
				"to_x": int(cmd.get("target_x", u.x)),
				"to_y": int(cmd.get("target_y", u.y)),
				"unit_ids": [unit_id]
			}
			return _cmd_move_stack(mc)
		IDs.CommandType.MISSION_BUILD_ROAD:
			if not _db.get_unit(u.unit_type_id).get("can_build", false):
				return false
			var road: Dictionary = _db.get_improvement("road")
			if road.empty():
				return false
			u.building_improvement = "road"
			u.build_turns_left = int(road.get("build_turns", 3))
			u.has_moved = true
			u.movement_left = 0
		IDs.CommandType.MISSION_PILLAGE:
			var tile: Tile = _gs.map.get_tile(u.x, u.y)
			if tile == null or tile.improvement_id == "":
				return false
			tile.improvement_id = ""
			u.has_moved = true
			u.movement_left = 0
		IDs.CommandType.MISSION_BOMBARD:
			var tx: int = int(cmd.get("target_x", -1))
			var ty: int = int(cmd.get("target_y", -1))
			var is_air: bool = _db.get_unit(u.unit_type_id).get("domain", "land") == "air"
			if is_air:
				# Air strikes reach within range; an interceptor may shoot the
				# bomber down before it strikes (§5.2).
				var reach: int = int(_db.get_unit(u.unit_type_id).get("air_range",
					_db.get_constant("air_strike_default_range", 4)))
				if _gs.map.distance(u.x, u.y, tx, ty) > reach:
					return false
				if _resolve_interception(u, tx, ty, player_id):
					u.has_moved = true; u.movement_left = 0
					return true  # intercepted: mission aborted
			var target: Unit = Stack.get_defender(_gs.units, tx, ty, player_id, _gs)
			if target == null:
				return false
			var result: Dictionary = Combat.resolve(u, target, _gs, _gs.rng)
			# Bombard / air strike never advances onto the target tile.
			_apply_combat_result(u, target, result, false)
			emit_signal("combat_resolved", result)
			_add_combat_notification(u, target, result)
			u.has_moved = true
		IDs.CommandType.MISSION_AIRLIFT:
			var tx2: int = int(cmd.get("target_x", u.x))
			var ty2: int = int(cmd.get("target_y", u.y))
			# Air units fly limited-range missions rather than teleporting (§5.2).
			if _db.get_unit(u.unit_type_id).get("domain", "land") == "air":
				var reach2: int = int(_db.get_unit(u.unit_type_id).get("air_range",
					_db.get_constant("air_strike_default_range", 4)))
				if _gs.map.distance(u.x, u.y, tx2, ty2) > reach2:
					return false
			u.x = tx2; u.y = ty2
			u.has_moved = true
			u.movement_left = 0
		IDs.CommandType.MISSION_SENTRY:
			# Hold position on watch; ends the turn but persists across turns
			# until woken (cycle-idle skips sentries — see cycle_idle_units).
			u.is_sentry = true
			u.has_moved = true
			u.movement_left = 0
		IDs.CommandType.MISSION_HEAL:
			# Hold position to recover; passive healing happens in turn upkeep.
			u.is_healing = true
			u.has_moved = true
			u.movement_left = 0
		IDs.CommandType.MISSION_AIR_PATROL, IDs.CommandType.MISSION_SEA_PATROL:
			# Patrol stance for air/naval units; holds the tile on standby.
			u.is_patrolling = true
			u.has_moved = true
			u.movement_left = 0
		IDs.CommandType.MISSION_CLEAN_FALLOUT:
			# A worker-type unit scrubs radioactive fallout off its tile (§5.7).
			if not _db.get_unit(u.unit_type_id).get("can_build", false):
				return false
			var ftile: Tile = _gs.map.get_tile(u.x, u.y)
			if ftile == null or ftile.feature_id != "fallout":
				return false
			ftile.feature_id = ""
			u.has_moved = true
			u.movement_left = 0
		IDs.CommandType.MISSION_SLEEP_UNTIL_HEALED:
			# Skip turns until full health, then wake idle (Issue 9). Available to
			# all units. The auto-wake is handled in TurnEngine.player_step.
			u.is_sleep_until_healed = true
			u.is_fortify_until_healed = false
			u.is_sleeping = false
			u.is_healing = false
			u.has_moved = true
			u.movement_left = 0
		IDs.CommandType.MISSION_FORTIFY_UNTIL_HEALED:
			# Fortify (gaining the defence bonus) until full health, then wake idle.
			# Only available to units that can normally fortify — civilians are
			# excluded (classification == "civilian" or base_strength == 0).
			var utype_fuh: Dictionary = _db.get_unit(u.unit_type_id)
			if str(utype_fuh.get("classification", "")) == "civilian":
				return false
			u.is_fortify_until_healed = true
			u.is_sleep_until_healed = false
			u.is_fortified = true
			u.is_healing = false
			u.is_sleeping = false
			u.has_moved = true
			u.movement_left = 0
		IDs.CommandType.MISSION_EXPLORE:
			# Explore mission: only recon/scout units (classification "recon" or
			# units with the "explore" tag) may use this. Sets is_exploring; the
			# actual move happens at the start of each turn via _run_explore_missions.
			var utype_exp: Dictionary = _db.get_unit(u.unit_type_id)
			var cls_exp: String = str(utype_exp.get("classification", ""))
			var has_explore_tag: bool = "explore" in utype_exp.get("tags", [])
			if cls_exp != "recon" and not has_explore_tag:
				return false
			u.is_exploring = true
			u.is_sentry = false
			u.is_sleeping = false
			u.is_healing = false
			u.is_patrolling = false
			# Don't consume movement; the auto-move this turn is handled immediately.
			_explore_step(u)
			if not u.is_exploring:
				# Woken by enemy spot during the first step — notify.
				_add_notification(
					_db.get_unit(u.unit_type_id).get("name", u.unit_type_id).capitalize()
						+ " spotted an enemy and stopped exploring.", "major")
		IDs.CommandType.MISSION_MOVE_TO_UNIT:
			var tu: Unit = _gs.get_unit(int(cmd.get("target_unit_id", -1)))
			if tu == null:
				return false
			var muc: Dictionary = {
				"type": IDs.CommandType.MOVE_STACK,
				"player_id": player_id,
				"from_x": u.x, "from_y": u.y,
				"to_x": tu.x, "to_y": tu.y
			}
			return _cmd_move_stack(muc)
		IDs.CommandType.MISSION_RECON:
			# Scout toward a target tile; reveal follows the move via fog update.
			var rc: Dictionary = {
				"type": IDs.CommandType.MOVE_STACK,
				"player_id": player_id,
				"from_x": u.x, "from_y": u.y,
				"to_x": int(cmd.get("target_x", u.x)),
				"to_y": int(cmd.get("target_y", u.y))
			}
			return _cmd_move_stack(rc)
		_:
			return false

	_dirty.set_dirty(IDs.DirtyRegion.WORLD)
	_dirty.set_dirty(IDs.DirtyRegion.HUD_GROUPS)
	return true

# ── Explore mission helpers ────────────────────────────────────────────────────

# Run one explore step for a single unit. Picks a random passable, non-enemy
# neighbour to move toward and takes one step. If an enemy unit is within the
# unit's sight range the mission ends and the player is alerted. When no valid
# step can be found (surrounded or at map edge), the mission also ends.
func _explore_step(u: Unit) -> void:
	if not u.is_exploring:
		return
	var player_id: int = u.owner_player_id
	var sight: int = _db.get_constant("unit_sight", 2)
	# Check for enemies within sight: if any are visible, wake the scout.
	for eu in _gs.units:
		if eu.owner_player_id == player_id:
			continue
		if eu.owner_player_id != -2 and not _gs.are_at_war(player_id, eu.owner_player_id):
			continue
		if _gs.map.distance(u.x, u.y, eu.x, eu.y) <= sight:
			u.is_exploring = false
			u.has_moved = true
			u.movement_left = 0
			_add_notification(
				str(_db.get_unit(u.unit_type_id).get("name", u.unit_type_id.capitalize()))
					+ " spotted an enemy — explore cancelled.", "major")
			return
	# Collect candidate tiles: passable non-enemy-occupied neighbours.
	var candidates: Array = []
	for nb in _gs.map.neighbours8(u.x, u.y):
		var ter: Dictionary = _db.get_terrain(nb.terrain_id)
		# Skip impassable terrain and enemy-occupied tiles.
		if ter.get("impassable", false):
			continue
		if _db.get_unit(u.unit_type_id).get("domain", "land") == "land" \
				and ter.get("domain", "land") != "land":
			continue
		# Never walk into an enemy: skip any tile that holds a hostile unit.
		var has_enemy: bool = false
		for eu2 in _gs.units:
			if eu2.x == nb.x and eu2.y == nb.y and eu2.owner_player_id != player_id:
				if eu2.owner_player_id == -2 or _gs.are_at_war(player_id, eu2.owner_player_id):
					has_enemy = true
					break
		if has_enemy:
			continue
		candidates.append(nb)
	if candidates.empty():
		u.is_exploring = false
		u.has_moved = true
		u.movement_left = 0
		_add_notification(
			str(_db.get_unit(u.unit_type_id).get("name", u.unit_type_id.capitalize()))
				+ " has nowhere to explore.", "info")
		return
	# Pick a random candidate and move there (draws from shared RNG).
	var idx: int = _gs.rng.randi_range(0, candidates.size() - 1)
	var target: Tile = candidates[idx]
	var mc: Dictionary = {
		"type": IDs.CommandType.MOVE_STACK,
		"player_id": player_id,
		"from_x": u.x, "from_y": u.y,
		"to_x": target.x, "to_y": target.y,
		"unit_ids": [u.id]
	}
	_cmd_move_stack(mc)

# Run explore steps for all exploring units owned by `player_id`. Called at
# the start of _cmd_end_turn so each exploring scout advances before the turn
# pipeline runs. Any scout woken by a sighted enemy has its notification added
# here too.
func _run_explore_missions(player_id: int) -> void:
	var ids: Array = []
	for u in _gs.units:
		if u.owner_player_id == player_id and u.is_exploring:
			ids.append(u.id)
	for uid in ids:
		var u: Unit = _gs.get_unit(uid)
		if u == null or not u.is_exploring:
			continue
		_explore_step(u)

func _cmd_do_control(cmd: Dictionary) -> bool:
	var ctrl_type: int = int(cmd.get("ctrl_type", -1))
	match ctrl_type:
		IDs.ControlType.NEXT_IDLE_UNIT:
			cycle_idle_units(false)
		IDs.ControlType.NEXT_IDLE_WORKER:
			cycle_idle_units(true)
		IDs.ControlType.NEXT_CITY:
			cycle_cities(true)
		IDs.ControlType.PREV_CITY:
			cycle_cities(false)
		IDs.ControlType.END_TURN, IDs.ControlType.FORCE_END_TURN:
			return _cmd_end_turn(int(cmd.get("player_id", _gs.current_player_id)))
		IDs.ControlType.OPEN_TECH, IDs.ControlType.OPEN_POLICY, \
		IDs.ControlType.OPEN_DIPLOMACY, IDs.ControlType.OPEN_FINANCE, \
		IDs.ControlType.OPEN_MILITARY, IDs.ControlType.OPEN_ESPIONAGE, \
		IDs.ControlType.OPEN_ENCYCLOPEDIA, IDs.ControlType.OPEN_CITY_SCREEN, \
		IDs.ControlType.OPEN_SAVE_LOAD, IDs.ControlType.QUICK_SAVE, \
		IDs.ControlType.QUICK_LOAD, IDs.ControlType.OPEN_MENU, \
		IDs.ControlType.TOGGLE_SCORE, IDs.ControlType.OPEN_RELIGION, \
		IDs.ControlType.OPEN_CORPORATION, IDs.ControlType.OPEN_TURN_LOG, \
		IDs.ControlType.OPEN_DOMESTIC_ADVISOR, \
		IDs.ControlType.OPEN_VICTORY_PROGRESS, IDs.ControlType.OPEN_OPTIONS, \
		IDs.ControlType.TOGGLE_MINIMAP, \
		IDs.ControlType.TOGGLE_FOG:
			emit_signal("screen_requested", ctrl_type)
	return true

# ── UI state queries ───────────────────────────────────────────────────────────

func get_dirty() -> DirtyFlags:
	return _dirty

func get_selection() -> SelectionState:
	return _selection

func select_unit(unit_id: int, do_clear: bool = true, toggle: bool = false) -> void:
	_selection.select_unit(unit_id, do_clear, toggle)
	_dirty.set_dirty(IDs.DirtyRegion.WORLD)
	_dirty.set_dirty(IDs.DirtyRegion.HUD_GROUPS)
	_dirty.set_dirty(IDs.DirtyRegion.DATA_PANES)

func select_city(city_id: int, raise_screen: bool = false) -> void:
	_selection.select_city(city_id, raise_screen)
	_dirty.set_dirty(IDs.DirtyRegion.WORLD)
	_dirty.set_dirty(IDs.DirtyRegion.HUD_GROUPS)
	_dirty.set_dirty(IDs.DirtyRegion.DATA_PANES)

# Select every unit the current player owns on a tile as one multi-unit
# selection (head = the first in spawn order). Lets the host issue an order to a
# whole stack at once. Returns the number of units selected.
func select_stack(tx: int, ty: int) -> int:
	_selection.clear()
	for u in _gs.units:
		if u.x == tx and u.y == ty and u.owner_player_id == _gs.current_player_id:
			_selection.select_unit(u.id, false, false)
	_dirty.set_dirty(IDs.DirtyRegion.WORLD)
	_dirty.set_dirty(IDs.DirtyRegion.HUD_GROUPS)
	_dirty.set_dirty(IDs.DirtyRegion.DATA_PANES)
	return _selection.selected_unit_ids.size()

func clear_selection() -> void:
	_selection.clear()
	_dirty.set_dirty(IDs.DirtyRegion.WORLD)
	_dirty.set_dirty(IDs.DirtyRegion.HUD_GROUPS)

# Can the given units (or the whole owned stack, when unit_ids is empty) reach
# (tx, ty) from (fx, fy)? True for a legal multi-turn route and for an adjacent
# enemy tile (entering it is an attack); false for impassable / wrong-domain
# tiles, so the host can treat an illegal click as "inspect" instead of a move.
func can_stack_move(fx: int, fy: int, tx: int, ty: int, unit_ids: Array = []) -> bool:
	if fx == tx and fy == ty:
		return false
	var movers: Array = _stack_movers(fx, fy, _gs.current_player_id, unit_ids)
	if movers.empty():
		return false
	var lead: Unit = movers[0]
	var path: Array = Pathfinding.find_path(
		_gs.map, fx, fy, tx, ty, lead, _db, _gs.units, _gs.current_player_id)
	return not path.empty()

# Mark an empty tile as the inspected subject: clears any unit/city selection and
# records the tile so the HUD can show a terrain readout (§UI bug: every tile is
# clickable; an unoccupied/illegal-target click shows terrain and drops the unit).
func inspect_tile(tx: int, ty: int) -> void:
	_selection.clear()
	_selection.inspected_tile = Vector2(tx, ty)
	_dirty.set_dirty(IDs.DirtyRegion.WORLD)
	_dirty.set_dirty(IDs.DirtyRegion.HUD_GROUPS)
	_dirty.set_dirty(IDs.DirtyRegion.DATA_PANES)

# Human-readable terrain readout for a tile (name, feature, resource, yields,
# movement cost, defence). The rules layer owns this text so it always matches
# the data tables (§9).
func tile_info_text(tx: int, ty: int) -> String:
	if _gs == null or _gs.map == null or not _gs.map.is_valid(tx, ty):
		return ""
	var tile: Tile = _gs.map.get_tile(tx, ty)
	if tile == null:
		return ""
	var ter: Dictionary = _db.get_terrain(tile.terrain_id)
	var lines: Array = []
	lines.append(str(ter.get("name", tile.terrain_id.capitalize())) \
		+ "  (" + str(tx) + ", " + str(ty) + ")")
	if tile.feature_id != "":
		lines.append("Feature: " + str(_db.get_feature(tile.feature_id).get("name", tile.feature_id.capitalize())))
	if tile.resource_id != "":
		lines.append("Resource: " + str(_db.get_resource(tile.resource_id).get("name", tile.resource_id.capitalize())))
	if tile.improvement_id != "":
		lines.append("Improvement: " + str(_db.get_improvement(tile.improvement_id).get("name", tile.improvement_id.capitalize())))
	var out: Dictionary = ter.get("base_output", {})
	lines.append("Yields: " + str(int(out.get("food", 0))) + "F " \
		+ str(int(out.get("production", 0))) + "P " \
		+ str(int(out.get("commerce", 0))) + "C")
	lines.append("Move cost: " + str(int(ter.get("movement_cost", 100)) / 100) \
		+ "   Defence: +" + str(int(ter.get("defence_bonus", 0))) + "%")

	# Foreign cities and units on this tile (read-only; player may not own them).
	for s in _gs.settlements:
		if s.x == tx and s.y == ty and s.owner_player_id != _gs.current_player_id:
			var owner: Player = _gs.get_player(s.owner_player_id)
			var owner_name: String = owner.name if owner != null else "?"
			lines.append(owner_name + "'s city: " + s.name + "  (pop " + str(s.population) + ")")
	for u in _gs.units:
		if u.x == tx and u.y == ty and u.owner_player_id != _gs.current_player_id:
			var udata: Dictionary = _db.get_unit(u.unit_type_id)
			var uname: String = udata.get("name", u.unit_type_id.capitalize())
			var unit_label: String
			if u.owner_player_id == -2:
				# Wild/barbarian forces: animals show as "Wild <type>", raiders as "Bandit <type>"
				var cls: String = str(udata.get("classification", ""))
				if cls == "animal":
					unit_label = "Wild " + uname
				else:
					unit_label = "Bandit " + uname
			else:
				var owner: Player = _gs.get_player(u.owner_player_id)
				var owner_name: String = owner.name if owner != null else "?"
				unit_label = owner_name + "'s " + uname
			lines.append(unit_label + "  (HP " + str(u.health) + ")")

	return PoolStringArray(lines).join("\n")

func cycle_idle_units(workers_only: bool = false) -> void:
	var idle: Array = []
	for u in _gs.units:
		if u.owner_player_id != _gs.current_player_id:
			continue
		if u.has_moved or u.is_fortified or u.is_sentry or u.is_patrolling \
				or u.is_healing or u.is_sleeping \
				or u.is_sleep_until_healed or u.is_fortify_until_healed \
				or u.is_exploring:
			continue
		if workers_only and not _db.get_unit(u.unit_type_id).get("can_build", false):
			continue
		idle.append(u.id)
	if idle.empty():
		return
	var head: int = _selection.head_unit()
	var start_idx: int = 0
	if head >= 0:
		var idx: int = idle.find(head)
		if idx >= 0:
			start_idx = (idx + 1) % idle.size()
	_selection.select_unit(idle[start_idx], true, false)
	_dirty.set_dirty(IDs.DirtyRegion.HUD_GROUPS)
	_dirty.set_dirty(IDs.DirtyRegion.DATA_PANES)

func cycle_cities(forward: bool = true) -> void:
	var owned: Array = []
	for s in _gs.settlements:
		if s.owner_player_id == _gs.current_player_id:
			owned.append(s.id)
	if owned.empty():
		return
	var head: int = _selection.head_city()
	var start_idx: int = 0
	if head >= 0:
		var idx: int = owned.find(head)
		if idx >= 0:
			var delta: int = 1 if forward else -1
			start_idx = (idx + delta + owned.size()) % owned.size()
	_selection.select_city(owned[start_idx], false)
	_dirty.set_dirty(IDs.DirtyRegion.HUD_GROUPS)
	_dirty.set_dirty(IDs.DirtyRegion.DATA_PANES)

# ── Interface mode (§5) ───────────────────────────────────────────────────────

func get_interface_mode() -> int:
	return _interface_mode

func can_enter_mode(mode: int) -> bool:
	if mode == IDs.InterfaceMode.SELECTION:
		return true
	return _selection.head_unit() >= 0

func enter_interface_mode(mode: int) -> void:
	_interface_mode = mode
	_dirty.set_dirty(IDs.DirtyRegion.WORLD)

func exit_interface_mode() -> void:
	_interface_mode = IDs.InterfaceMode.SELECTION
	_dirty.set_dirty(IDs.DirtyRegion.WORLD)

func get_mode_tile_validity(x: int, y: int) -> int:
	if _gs.map == null:
		return 0
	if not _gs.map.is_valid(x, y):
		return 0
	match _interface_mode:
		IDs.InterfaceMode.SELECTION:
			return 1
		IDs.InterfaceMode.GO_TO, IDs.InterfaceMode.GO_TO_ALL, IDs.InterfaceMode.ROUTE_TO:
			return 1   # detailed reachability uses pathfinding at move time
		_:
			return 1

# ── Popup queue (§6) ──────────────────────────────────────────────────────────

func push_popup(descriptor: Dictionary) -> void:
	_popup_queue.append(descriptor)

func get_pending_popup() -> Dictionary:
	if _popup_queue.empty():
		return {}
	return _popup_queue[0]

func resolve_popup(result: Dictionary) -> void:
	if _popup_queue.empty():
		return
	_popup_queue.pop_front()

# ── Capability queries (§3, §10) ─────────────────────────────────────────────

func can_do_control(ctrl_type: int) -> bool:
	match ctrl_type:
		IDs.ControlType.END_TURN, IDs.ControlType.FORCE_END_TURN:
			return _gs.current_player_id >= 0
		IDs.ControlType.CENTER_ON_SELECTION:
			return _selection.head_unit() >= 0 or _selection.head_city() >= 0
		IDs.ControlType.NEXT_UNIT, IDs.ControlType.PREV_UNIT, \
		IDs.ControlType.NEXT_IDLE_UNIT, IDs.ControlType.NEXT_IDLE_WORKER:
			for u in _gs.units:
				if u.owner_player_id == _gs.current_player_id:
					return true
			return false
		IDs.ControlType.NEXT_CITY, IDs.ControlType.PREV_CITY:
			for s in _gs.settlements:
				if s.owner_player_id == _gs.current_player_id:
					return true
			return false
	return true  # screen toggles, hotkeys, etc. are always allowed

func can_handle_action(action_id: int, target_x: int, target_y: int) -> bool:
	if _selection.head_unit() < 0 and _selection.head_city() < 0:
		return false
	if _interface_mode != IDs.InterfaceMode.SELECTION:
		return false
	return true

# ── Display-gating queries (§10) ──────────────────────────────────────────────

func get_end_turn_state() -> int:
	# 0 = ready, 1 = waiting on others, 2 = idle units prompt
	# A remote client that has submitted its turn is waiting on the server.
	if _remote_waiting:
		return 1
	if _gs.current_player_id < 0:
		return 1
	for u in _gs.units:
		if u.owner_player_id == _gs.current_player_id and not u.has_moved \
				and not u.is_fortified and not u.is_sleeping \
				and not u.is_sleep_until_healed and not u.is_fortify_until_healed \
				and not u.is_exploring:
			return 2
	return 0

func get_hud_visibility() -> Dictionary:
	return {
		"show_research": not _gs.players.empty(),
		"show_flag": not _gs.players.empty(),
		"show_minimap_center": _selection.head_unit() >= 0 or _selection.head_city() >= 0
	}

func get_tile_highlights() -> Dictionary:
	var highlights: Dictionary = {}
	var head_id: int = _selection.head_unit()
	if head_id < 0:
		return highlights
	var u: Unit = _gs.get_unit(head_id)
	if u == null:
		return highlights
	highlights[str(u.x) + "," + str(u.y)] = 0xFFFFFF
	return highlights

func get_flyout_menu(x: int, y: int) -> Array:
	var items: Array = []
	for u in _gs.units:
		if u.x == x and u.y == y and u.owner_player_id == _gs.current_player_id:
			# Settlers can found a city here.
			if _db.get_unit(u.unit_type_id).get("can_found", false):
				items.append({
					"action_id": IDs.UnitMission.FOUND_SETTLEMENT,
					"label": "Found City",
					"unit_id": u.id,
					"target_x": x, "target_y": y
				})
			if not u.has_moved:
				items.append({
					"action_id": IDs.UnitCmd.WAKE,
					"label": "Skip Turn",
					"target_x": x, "target_y": y
				})
			if not u.is_fortified:
				items.append({
					"action_id": IDs.UnitCmd.FORTIFY,
					"label": "Fortify",
					"target_x": x, "target_y": y
				})
			break
	for s in _gs.settlements:
		if s.x == x and s.y == y and s.owner_player_id == _gs.current_player_id:
			items.append({
				"action_id": IDs.ControlType.OPEN_CITY_SCREEN,
				"label": "Open City",
				"target_x": x, "target_y": y
			})
			break
	return items

# ── Widget dispatch (§4) ──────────────────────────────────────────────────────

func widget_help(widget: Dictionary) -> String:
	return TextGen.widget_help(widget, _gs, _db)

func widget_action(widget: Dictionary) -> bool:
	var wtype: int = int(widget.get("type", -1))
	match wtype:
		IDs.WidgetType.RESEARCH:
			var tech_id: String = str(widget.get("tech_id", ""))
			return apply_command(Commands.set_research(_gs.current_player_id, tech_id))
		IDs.WidgetType.RUSH_PRODUCTION:
			var city_id: int = int(widget.get("data1", -1))
			var method: String = str(widget.get("method", "treasury"))
			return apply_command(Commands.rush_production(_gs.current_player_id, city_id, method))
		IDs.WidgetType.CLOSE_SCREEN:
			emit_signal("screen_requested", -1)
			return true
	return false

func widget_alt_action(widget: Dictionary) -> bool:
	return false  # context-dependent; default no-op for Phase 6

func widget_is_link(widget: Dictionary) -> bool:
	var wtype: int = int(widget.get("type", -1))
	match wtype:
		IDs.WidgetType.ENCYCLOPEDIA, IDs.WidgetType.BACK, IDs.WidgetType.FORWARD:
			return true
	return false

# ── Notifications (§8) ────────────────────────────────────────────────────────

func get_notification_queue() -> Array:
	return _notifications

func _alliance_label(alliance_id: int) -> String:
	var a: Alliance = _gs.get_alliance(alliance_id)
	if a == null or a.member_player_ids.empty():
		return "another power"
	var p: Player = _gs.get_player(int(a.member_player_ids[0]))
	return p.name if p != null else "another power"

func _add_notification(text: String, category: String = "info") -> void:
	_notifications.append({"text": text, "category": category, "turn": _gs.turn_number})
	if _notifications.size() > 100:
		_notifications.pop_front()
	_dirty.set_dirty(IDs.DirtyRegion.DATA_PANES)

# Surface any cultural-flip records the §4.9 revolt phase produced this player
# step: one notification + a city_flipped signal each, then clear the queue.
func _drain_flips() -> void:
	if _gs.pending_flips.empty():
		return
	for f in _gs.pending_flips:
		var city: Settlement = _gs.get_settlement(int(f["settlement_id"]))
		var nm: String = city.name if city != null else "A city"
		_add_notification(nm + " has defected through cultural pressure!", "major")
		emit_signal("city_flipped", f["settlement_id"],
			f["from_player_id"], f["to_player_id"])
	_gs.pending_flips = []
	_dirty.set_dirty(IDs.DirtyRegion.WORLD)
	_dirty.set_dirty(IDs.DirtyRegion.DATA_PANES)
	_dirty.set_dirty(IDs.DirtyRegion.HUD_GROUPS)

# Surface any era advancements queued during the player step (§1): one notification
# + an era_advanced signal each, then clear the queue.
func _drain_era_advances() -> void:
	if _gs.pending_era_advances.empty():
		return
	for adv in _gs.pending_era_advances:
		var pid: int = int(adv["player_id"])
		var to_era: int = int(adv["to"])
		var p: Player = _gs.get_player(pid)
		var who: String = p.name if p != null else "A civilization"
		_add_notification(
			who + " has entered the " + Eras.era_name(to_era, _db) + " Era.", "major")
		emit_signal("era_advanced", pid, int(adv["from"]), to_era)
	_gs.pending_era_advances = []
	_dirty.set_dirty(IDs.DirtyRegion.HUD_GROUPS)
	_dirty.set_dirty(IDs.DirtyRegion.DATA_PANES)

# Surface any wild-forces combat/conquest records WildAI produced this world step
# (§9): each fight re-emits combat_resolved; each razed city clears a stale
# selection, notifies, and emits city_razed. Then clear the queue.
func _drain_wild_events() -> void:
	if _gs.pending_wild_events.empty():
		return
	for e in _gs.pending_wild_events:
		match e["kind"]:
			"combat":
				emit_signal("combat_resolved", e["result"])
				# Notify any player whose unit was killed by a wild attacker.
				var def_owner: int = int(e.get("defender_owner_id", -1))
				if def_owner >= 0 and not bool(e["result"].get("defender_survived", true)):
					var def_type: String = str(e.get("defender_type_id", ""))
					var def_name: String = str(_db.get_unit(def_type).get("name", def_type))
					var dx: int = int(e.get("defender_x", -1))
					var dy: int = int(e.get("defender_y", -1))
					var p_owner: Player = _gs.get_player(def_owner)
					var owner_label: String = (p_owner.name + "'s") if p_owner != null else "A"
					_add_notification(owner_label + " " + def_name + " was killed by wild forces at ("
						+ str(dx) + "," + str(dy) + ").", "major")
			"razed":
				var sid: int = int(e["settlement_id"])
				if _selection != null and _selection.head_city() == sid:
					_selection.clear()
				_add_notification(str(e["name"]) + " was razed by raiders.", "major")
				emit_signal("city_razed", sid, -2)
	_gs.pending_wild_events = []
	_dirty.set_dirty(IDs.DirtyRegion.WORLD)
	_dirty.set_dirty(IDs.DirtyRegion.DATA_PANES)
	_dirty.set_dirty(IDs.DirtyRegion.HUD_GROUPS)

# Surface any diplomatic-assembly records produced this world step (§7.2): a
# notification + an assembly_event signal for each opened session and resolved
# proposal. Then clear the queue.
func _drain_assembly_events() -> void:
	if _gs.pending_assembly_events.empty():
		return
	for e in _gs.pending_assembly_events:
		match str(e.get("kind", "")):
			"session_opened":
				_add_notification("The assembly convenes: " + str(e.get("name", "")) + ".", "major")
			"resolution_resolved":
				var verb: String = "passed" if bool(e.get("passed", false)) else "failed"
				_add_notification("Assembly motion " + verb + ": " + str(e.get("name", "")) + ".", "major")
		emit_signal("assembly_event", e)
	_gs.pending_assembly_events = []
	_dirty.set_dirty(IDs.DirtyRegion.DATA_PANES)
	_dirty.set_dirty(IDs.DirtyRegion.HUD_GROUPS)

# Surface technology-completion records queued during a player step: one
# notification + a technology_completed signal each, then clear the queue.
func _drain_tech_completions() -> void:
	if _gs.pending_tech_completions.empty():
		return
	for entry in _gs.pending_tech_completions:
		var pid: int = int(entry["player_id"])
		var tech_id: String = str(entry["tech_id"])
		var p: Player = _gs.get_player(pid)
		var who: String = p.name if p != null else "A civilization"
		var tech_name: String = str(_db.get_technology(tech_id).get("name", tech_id))
		_add_notification(who + " discovered " + tech_name + ".", "major")
		emit_signal("technology_completed", pid, tech_id)
	_gs.pending_tech_completions = []
	_dirty.set_dirty(IDs.DirtyRegion.DATA_PANES)
	_dirty.set_dirty(IDs.DirtyRegion.HUD_GROUPS)

# Surface great-person birth records queued during a player/world step: one
# notification each, then clear the queue.
func _drain_great_people() -> void:
	if _gs.pending_great_people.empty():
		return
	for entry in _gs.pending_great_people:
		var pid: int = int(entry["player_id"])
		var unit_type: String = str(entry["unit_type_id"])
		var p: Player = _gs.get_player(pid)
		var who: String = p.name if p != null else "A civilization"
		var gp_name: String = str(_db.get_unit(unit_type).get("name", unit_type))
		_add_notification(who + " produced a " + gp_name + "!", "major")
	_gs.pending_great_people = []
	_dirty.set_dirty(IDs.DirtyRegion.DATA_PANES)
	_dirty.set_dirty(IDs.DirtyRegion.HUD_GROUPS)

# Surface wonder/project-completion records queued during a player step: one
# notification each, then clear the queue.
func _drain_productions() -> void:
	if _gs.pending_productions.empty():
		return
	for entry in _gs.pending_productions:
		var pid: int = int(entry["player_id"])
		var p: Player = _gs.get_player(pid)
		var who: String = p.name if p != null else "A civilization"
		var city: String = str(entry.get("settlement_name", ""))
		var item_name: String = str(entry.get("item_name", ""))
		if str(entry.get("item_type", "")) == "project":
			_add_notification(who + " completed a project stage: " + item_name + ".", "major")
		else:
			_add_notification(who + " built " + item_name + " in " + city + "!", "major")
	_gs.pending_productions = []
	_dirty.set_dirty(IDs.DirtyRegion.DATA_PANES)
	_dirty.set_dirty(IDs.DirtyRegion.HUD_GROUPS)

# Surface city-growth records queued during a player step: one notification each,
# then clear the queue.
func _drain_growth_events() -> void:
	if _gs.pending_growth.empty():
		return
	for entry in _gs.pending_growth:
		var city: String = str(entry.get("settlement_name", ""))
		var pop: int = int(entry.get("population", 0))
		_add_notification(city + " grew to population " + str(pop) + "!", "major")
	_gs.pending_growth = []
	_dirty.set_dirty(IDs.DirtyRegion.DATA_PANES)
	_dirty.set_dirty(IDs.DirtyRegion.HUD_GROUPS)

# Compose a brief combat notification from the attacker and defender units.
# When the defender is the current player's unit and was killed, a distinct
# "Your X was killed" notification is added so losses are always visible.
func _add_combat_notification(attacker: Unit, defender: Unit, result: Dictionary) -> void:
	var atk_name: String = str(_db.get_unit(attacker.unit_type_id).get("name", attacker.unit_type_id))
	var def_name: String = str(_db.get_unit(defender.unit_type_id).get("name", defender.unit_type_id))
	var outcome: String
	if not bool(result.get("attacker_survived", true)):
		outcome = atk_name + " was destroyed attacking " + def_name + "."
		# Current player's unit killed while attacking
		if attacker.owner_player_id == _gs.current_player_id:
			_add_notification("Your " + atk_name + " was killed at ("
				+ str(defender.x) + "," + str(defender.y) + ").", "major")
			return
	elif not bool(result.get("defender_survived", true)):
		outcome = atk_name + " defeated " + def_name + "."
		# Current player's unit killed while defending
		if defender.owner_player_id == _gs.current_player_id:
			_add_notification("Your " + def_name + " was killed at ("
				+ str(defender.x) + "," + str(defender.y) + ").", "major")
			return
	else:
		outcome = atk_name + " attacked " + def_name + " — both survived."
	_add_notification(outcome, "info")

# Push a CHOOSE_ELECTION popup for a human player who is an eligible member of an
# open assembly session and has not yet voted (§7.2). AI players vote through
# PlayerAI.manage_assembly instead, so they never see a popup.
func _maybe_raise_vote_popup(player_id: int) -> void:
	var p: Player = _gs.get_player(player_id)
	if p == null or p.is_ai:
		return
	if not Assembly.has_open_session(_gs) or Assembly.has_voted(_gs, player_id):
		return
	var body: String = str(_gs.assembly.get("kind", ""))
	if not Assembly.is_member(_gs, p, body):
		return
	var pending: Dictionary = Assembly.pending_proposal(_gs)
	# Carry the candidate slate so the ballot can offer a runoff choice (a supreme-
	# leadership motion has 1–2 candidates; other proposals carry none / one).
	var candidates: Array = []
	for c in pending.get("candidates", []):
		var cp: Player = _gs.get_player(int(c))
		candidates.append({"id": int(c), "name": (cp.name if cp != null else "")})
	push_popup({
		"type": IDs.PopupType.CHOOSE_ELECTION,
		"player_id": player_id,
		"resolution_id": str(pending.get("resolution_id", "")),
		"name": str(pending.get("name", "")),
		"text": str(pending.get("text", "")),
		"candidates": candidates
	})

func _cmd_cast_vote(cmd: Dictionary) -> bool:
	var ok: bool = Assembly.cast_vote(_gs, int(cmd["player_id"]), str(cmd.get("choice", "")))
	if ok:
		_dirty.set_dirty(IDs.DirtyRegion.DATA_PANES)
		_dirty.set_dirty(IDs.DirtyRegion.HUD_GROUPS)
	return ok
