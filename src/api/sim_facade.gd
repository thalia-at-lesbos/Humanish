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
signal technology_completed(player_id, tech_id)
signal combat_resolved(result_dict)
signal player_turn_started(player_id)
signal screen_requested(screen_id)

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
		enabled_win_conditions: Array, map_type_id: String = "continents") -> void:
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

	var ws: Dictionary = db.get_world_size(world_size_id)
	_gs.max_turns = int(db.get_pace(pace_id).get("max_turns", 500))

	_gs.map = WorldMap.new()
	_gs.map.init(
		int(ws.get("width", 80)),
		int(ws.get("height", 48)),
		bool(ws.get("wrap_x", true)),
		bool(ws.get("wrap_y", false))
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
		IDs.CommandType.MISSION_AIR_PATROL, IDs.CommandType.MISSION_SEA_PATROL:
			return _cmd_mission(cmd)
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

	TurnEngine.player_step(_gs, player_id, _hooks)

	# Trigger world step when the last player ends their turn (next wraps to index 0)
	var next_idx: int = _get_next_player_index(player_id)
	if next_idx == 0 or next_idx < 0:
		TurnEngine.world_step(_gs, _hooks)
		_add_notification("Turn " + str(_gs.turn_number) + " begins.", "info")
		emit_signal("turn_advanced", _gs.turn_number)
		if _gs.winning_alliance_id >= 0:
			emit_signal("game_won", _gs.winning_alliance_id)

	# Advance to next active player
	if not _gs.players.empty() and next_idx >= 0 and next_idx < _gs.players.size():
		_gs.current_player_id = _gs.players[next_idx].id
		emit_signal("player_turn_started", _gs.current_player_id)

	_dirty.mark_all()
	return true

func _cmd_move_stack(cmd: Dictionary) -> bool:
	var player_id: int = int(cmd["player_id"])
	var fx: int = int(cmd["from_x"]); var fy: int = int(cmd["from_y"])
	var tx: int = int(cmd["to_x"]);   var ty: int = int(cmd["to_y"])

	var all_here: Array = Stack.at(_gs.units, fx, fy, player_id)
	# Carried units are not independent stack members; they ride with their
	# transport via the cargo-follow logic below (§5.2).
	var moving_units: Array = []
	for mu in all_here:
		if mu.transported_by < 0:
			moving_units.append(mu)
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
		var enemy: Unit = Stack.get_defender(
			_gs.units, sx, sy, player_id, _gs)
		if enemy != null:
			var result: Dictionary = Combat.resolve(lead, enemy, _gs, _gs.rng)
			_apply_combat_result(lead, enemy, result)
			emit_signal("combat_resolved", result)
			for u in moving_units:
				u.movement_left = 0
				u.has_moved = true
			lead.has_attacked = true
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

	_dirty.set_dirty(IDs.DirtyRegion.WORLD)
	_dirty.set_dirty(IDs.DirtyRegion.HUD_GROUPS)
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

	# Found the settlement
	var s := Settlement.new()
	s.id = _gs.next_settlement_id()
	s.name = sname if sname != "" else "City " + str(s.id)
	s.owner_player_id = player_id
	s.x = u.x; s.y = u.y
	s.population = 1
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
	var transition: int = int(pol.get("transition_turns", 0))
	p.policies[cat] = pol_id
	if transition > 0:
		p.transition_turns = transition
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
	if bool(t.get("peace", false)):
		var a_from: Alliance = _gs.get_alliance(int(t.get("from_alliance", -1)))
		var a_to: Alliance = _gs.get_alliance(int(t.get("to_alliance", -1)))
		if a_from != null and a_to != null:
			a_from.at_war_with.erase(a_to.id)
			a_to.at_war_with.erase(a_from.id)

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
	if not GreatPeople.perform_action(_gs, u, action, params):
		return false
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
	var cost: int = _db.get_constant("intel_mission_cost", 100)
	var have: int = int(p.intel_points.get(target_aid, 0))
	if have < cost:
		return false
	p.intel_points[target_aid] = have - cost
	# Interception spends the points but fails the mission.
	if _gs.rng.rand_bool_percent(_db.get_constant("intel_interception_chance", 25)):
		_add_notification("Espionage mission intercepted.", "info")
		return true
	match str(cmd.get("mission", "")):
		"steal_tech":
			_espionage_steal_tech(p, target_alliance)
		"sabotage":
			_espionage_sabotage(target_alliance)
	return true

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

func _apply_combat_result(attacker: Unit, defender: Unit,
		result: Dictionary, advance: bool = true) -> void:
	attacker.health = int(result["attacker_health_after"])
	defender.health = int(result["defender_health_after"])

	if result["attacker_withdrew"]:
		# Move attacker back (handled by move stack; health already set)
		pass

	attacker.experience += int(result["attacker_xp_gain"])
	defender.experience += int(result["defender_xp_gain"])

	# Auto-promote survivors that crossed an experience threshold (§5.5).
	if result["attacker_survived"]:
		_award_promotions(attacker)
	if result["defender_survived"]:
		_award_promotions(defender)

	# War-fatigue: the losing side's alliance accrues fatigue (§4.5, §7).
	if not result["defender_survived"] and result["attacker_survived"]:
		_accrue_war_fatigue(defender, attacker)
	elif not result["attacker_survived"] and result["defender_survived"]:
		_accrue_war_fatigue(attacker, defender)

	if not result["attacker_survived"]:
		Stack.remove_unit(_gs.units, attacker.id)
	if not result["defender_survived"]:
		Stack.remove_unit(_gs.units, defender.id)
		# Attacker may advance (bombard/air strikes pass advance = false)
		if result["attacker_survived"] and advance:
			attacker.x = defender.x
			attacker.y = defender.y

	# Spillover to stacked units (siege attackers)
	if result["spillover_damage"] > 0:
		for u in Stack.at(_gs.units, defender.x, defender.y, defender.owner_player_id):
			if u.id != defender.id:
				u.health = max(0, u.health - int(result["spillover_damage"]))
				if u.health <= 0:
					Stack.remove_unit(_gs.units, u.id)

	# Flanking: fast attackers damage part of the defeated defender's stack (§5.4).
	if result["flanking_damage"] > 0:
		for u in Stack.at(_gs.units, defender.x, defender.y, defender.owner_player_id):
			if u.id != defender.id:
				u.health = max(0, u.health - int(result["flanking_damage"]))
				if u.health <= 0:
					Stack.remove_unit(_gs.units, u.id)

	# Great General accrues from combat victories (§14.2): the surviving victor's
	# owner gains points and may produce a Great General in the field.
	if result["attacker_survived"] != result["defender_survived"]:
		if result["attacker_survived"]:
			GreatPeople.award_combat_points(_gs,
				_gs.get_player(attacker.owner_player_id),
				attacker.x, attacker.y, int(result["attacker_xp_gain"]))
		else:
			GreatPeople.award_combat_points(_gs,
				_gs.get_player(defender.owner_player_id),
				defender.x, defender.y, int(result["defender_xp_gain"]))

# Grant promotions for each experience level newly reached (§5.5). Levels are the
# data-defined experience_thresholds; each new level awards one eligible promotion.
func _award_promotions(u: Unit) -> void:
	var thresholds: Array = _db.constants.get("experience_thresholds", [])
	while u.experience_level + 1 < thresholds.size() \
			and u.experience >= int(thresholds[u.experience_level + 1]):
		u.experience_level += 1
		var promo: String = _pick_promotion(u)
		if promo == "":
			break  # nothing eligible left; stop awarding
		u.promotions.append(promo)

# First promotion (in data order) whose prereqs are met, that applies to this
# unit's class/domain, and that it does not already hold. "" if none qualifies.
func _pick_promotion(u: Unit) -> String:
	var udata: Dictionary = _db.get_unit(u.unit_type_id)
	var cls: String = str(udata.get("classification", ""))
	var dom: String = str(udata.get("domain", "land"))
	for pid in _db.promotions:
		if pid in u.promotions:
			continue
		var promo: Dictionary = _db.promotions[pid]
		var applies: String = str(promo.get("applies_to", "all"))
		if applies != "all" and applies != cls and applies != dom:
			continue
		var ok: bool = true
		for pr in promo.get("prereqs", []):
			if not (pr in u.promotions):
				ok = false
				break
		if ok:
			return pid
	return ""

# The defeated unit's alliance accumulates war-fatigue against the victor's
# alliance. Wild forces (no player/alliance) are skipped.
func _accrue_war_fatigue(loser: Unit, winner: Unit) -> void:
	var lp: Player = _gs.get_player(loser.owner_player_id)
	var wp: Player = _gs.get_player(winner.owner_player_id)
	if lp == null or wp == null:
		return
	var la: Alliance = _gs.get_alliance(lp.alliance_id)
	if la == null:
		return
	# War Weariness does not increase for a player enjoying a Golden Age (§14.4).
	if GreatPeople.is_in_golden_age(lp):
		return
	var amt: int = _db.get_constant("war_fatigue_per_loss", 5)
	la.war_fatigue[wp.alliance_id] = int(la.war_fatigue.get(wp.alliance_id, 0)) + amt

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
			u.has_moved = false
			u.movement_left = u.movement_total
		IDs.CommandType.UNIT_SLEEP:
			u.is_fortified = true
			u.has_moved = true
			u.movement_left = 0
		IDs.CommandType.UNIT_FORTIFY:
			u.is_fortified = true
			u.has_moved = true
			u.movement_left = 0
		IDs.CommandType.UNIT_CANCEL_ORDERS:
			u.building_improvement = ""
			u.build_turns_left = 0
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
			var mc: Dictionary = {
				"type": IDs.CommandType.MOVE_STACK,
				"player_id": player_id,
				"from_x": u.x, "from_y": u.y,
				"to_x": int(cmd.get("target_x", u.x)),
				"to_y": int(cmd.get("target_y", u.y))
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
		IDs.ControlType.OPEN_VICTORY_PROGRESS, IDs.ControlType.OPEN_OPTIONS:
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

func cycle_idle_units(workers_only: bool = false) -> void:
	var idle: Array = []
	for u in _gs.units:
		if u.owner_player_id != _gs.current_player_id:
			continue
		if u.has_moved or u.is_fortified or u.is_sentry or u.is_patrolling or u.is_healing:
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
		if u.owner_player_id == _gs.current_player_id and not u.has_moved and not u.is_fortified:
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

func _add_notification(text: String, category: String = "info") -> void:
	_notifications.append({"text": text, "category": category, "turn": _gs.turn_number})
	if _notifications.size() > 100:
		_notifications.pop_front()
	_dirty.set_dirty(IDs.DirtyRegion.DATA_PANES)
