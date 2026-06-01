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

# ── Lifecycle ─────────────────────────────────────────────────────────────────

func setup(db: DataDB, seed_val: int, world_size_id: String, pace_id: String,
		difficulty_id: String, player_configs: Array,
		enabled_win_conditions: Array) -> void:
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
	# Populate the blank grid with a varied sample map. Uses gs.rng so the result
	# is deterministic for the seed and is captured by save/load (tiles serialize).
	MapGen.generate(_gs.map, db, _gs.rng)

	# Create players and alliances
	var difficulty: Dictionary = db.get_difficulty(difficulty_id)
	var starting_techs: Array = db.constants.get("starting_techs", [])
	var default_research: String = str(db.constants.get("default_research", ""))
	for cfg in player_configs:
		var p := Player.new()
		p.id = _gs.next_player_id()
		p.name = str(cfg.get("name", "Player " + str(p.id)))
		p.leader_id = str(cfg.get("leader_id", ""))
		p.traits = cfg.get("traits", []).duplicate()
		p.free_early_wins = int(difficulty.get("free_early_wins", 0))
		p.treasury = int(cfg.get("starting_gold", 100))

		# Seed the player's known techs and pick a default research target so the
		# tech tree (data/technologies.json) is usable from turn one.
		p.technologies = starting_techs.duplicate()
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
	_place_all_starting_units(player_configs)

func _place_all_starting_units(player_configs: Array) -> void:
	var starts: Array = MapGen.find_start_positions(_gs.map, _db, _gs.players.size())
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
		IDs.CommandType.UNIT_PROMOTE:
			return _cmd_unit_command(cmd)
		IDs.CommandType.MISSION_MOVE_TO, IDs.CommandType.MISSION_BUILD_ROAD, \
		IDs.CommandType.MISSION_SKIP_TURN, IDs.CommandType.MISSION_PILLAGE, \
		IDs.CommandType.MISSION_BOMBARD, IDs.CommandType.MISSION_AIRLIFT:
			return _cmd_mission(cmd)
		IDs.CommandType.DO_CONTROL:
			return _cmd_do_control(cmd)
	return false

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

	var moving_units: Array = Stack.at(_gs.units, fx, fy, player_id)
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
			if p.treasury < remaining:
				return false
			p.treasury -= remaining
			s.production_store = cost
		"population":
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
	u.build_turns_left = int(imp.get("build_turns", 5))
	u.has_moved = true
	u.movement_left = 0
	return true

# ── Helpers ───────────────────────────────────────────────────────────────────

func _apply_combat_result(attacker: Unit, defender: Unit,
		result: Dictionary) -> void:
	attacker.health = int(result["attacker_health_after"])
	defender.health = int(result["defender_health_after"])

	if result["attacker_withdrew"]:
		# Move attacker back (handled by move stack; health already set)
		pass

	attacker.experience += int(result["attacker_xp_gain"])
	defender.experience += int(result["defender_xp_gain"])

	if not result["attacker_survived"]:
		Stack.remove_unit(_gs.units, attacker.id)
	if not result["defender_survived"]:
		Stack.remove_unit(_gs.units, defender.id)
		# Attacker may advance
		if result["attacker_survived"]:
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
			var target: Unit = Stack.get_defender(_gs.units, tx, ty, player_id, _gs)
			if target == null:
				return false
			var result: Dictionary = Combat.resolve(u, target, _gs, _gs.rng)
			_apply_combat_result(u, target, result)
			emit_signal("combat_resolved", result)
			u.has_moved = true
		IDs.CommandType.MISSION_AIRLIFT:
			var tx2: int = int(cmd.get("target_x", u.x))
			var ty2: int = int(cmd.get("target_y", u.y))
			u.x = tx2; u.y = ty2
			u.has_moved = true
			u.movement_left = 0
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
		IDs.ControlType.OPEN_SAVE_LOAD:
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

func clear_selection() -> void:
	_selection.clear()
	_dirty.set_dirty(IDs.DirtyRegion.WORLD)
	_dirty.set_dirty(IDs.DirtyRegion.HUD_GROUPS)

func cycle_idle_units(workers_only: bool = false) -> void:
	var idle: Array = []
	for u in _gs.units:
		if u.owner_player_id != _gs.current_player_id:
			continue
		if u.has_moved or u.is_fortified:
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
