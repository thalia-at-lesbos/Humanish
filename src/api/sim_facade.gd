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

var _gs: GameState
var _hooks: Hooks
var _db: DataDB

# ── Lifecycle ─────────────────────────────────────────────────────────────────

func setup(db: DataDB, seed_val: int, world_size_id: String, pace_id: String,
		difficulty_id: String, player_configs: Array,
		enabled_win_conditions: Array) -> void:
	_db = db
	_hooks = Hooks.new()

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

	# Create players and alliances
	var difficulty: Dictionary = db.get_difficulty(difficulty_id)
	for cfg in player_configs:
		var p := Player.new()
		p.id = _gs.next_player_id()
		p.name = str(cfg.get("name", "Player " + str(p.id)))
		p.leader_id = str(cfg.get("leader_id", ""))
		p.traits = cfg.get("traits", []).duplicate()
		p.free_early_wins = int(difficulty.get("free_early_wins", 0))
		p.treasury = int(cfg.get("starting_gold", 100))

		# Each player starts in their own alliance
		var a := Alliance.new()
		a.id = _gs.next_alliance_id()
		a.add_member(p.id)
		p.alliance_id = a.id
		_gs.alliances.append(a)
		_gs.players.append(p)

	if not _gs.players.empty():
		_gs.current_player_id = _gs.players[0].id

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
	return false

# ── Command handlers ──────────────────────────────────────────────────────────

func _cmd_end_turn(player_id: int) -> bool:
	var player: Player = _gs.get_player(player_id)
	if player == null:
		return false

	TurnEngine.player_step(_gs, player_id, _hooks)

	# Check if all players have ended their turn
	var next_idx: int = _get_next_player_index(player_id)
	if next_idx == 0 or next_idx < 0:
		# World step
		TurnEngine.world_step(_gs, _hooks)
		emit_signal("turn_advanced", _gs.turn_number)
		if _gs.winning_alliance_id >= 0:
			emit_signal("game_won", _gs.winning_alliance_id)

	var next_id: int = _gs.current_player_id
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

	# Move one step at a time consuming movement
	for step in path:
		var sx: int = int(step[0]); var sy: int = int(step[1])
		var step_cost: int = Pathfinding._move_cost(
			_gs.map.get_tile(sx, sy), _db,
			_db.get_unit(lead.unit_type_id).get("domain", "land"))

		for u in moving_units:
			if u.movement_left < Fixed.MOVE_PRECISION and u.movement_left > 0:
				# Guarantee at least one tile per turn
				step_cost = u.movement_left
			u.movement_left = max(0, u.movement_left - step_cost)
			u.x = sx; u.y = sy
			u.has_moved = true
			u.stationary_turns = 0
			u.entrenchment = 0

		# Check for combat upon entry
		var enemy: Unit = Stack.get_defender(
			_gs.units, sx, sy, player_id, _gs)
		if enemy != null:
			var result: Dictionary = Combat.resolve(lead, enemy, _gs, _gs.rng)
			_apply_combat_result(lead, enemy, result)
			emit_signal("combat_resolved", result)
			if not result["attacker_survived"]:
				break

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

	emit_signal("settlement_founded", s.id)
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
	return true

func _cmd_set_production(cmd: Dictionary) -> bool:
	var s: Settlement = _gs.get_settlement(int(cmd["settlement_id"]))
	if s == null or s.owner_player_id != int(cmd["player_id"]):
		return false
	s.production_queue = cmd.get("queue", []).duplicate(true)
	return true

func _cmd_set_research(cmd: Dictionary) -> bool:
	var p: Player = _gs.get_player(int(cmd["player_id"]))
	if p == null:
		return false
	var tech_id: String = str(cmd.get("tech_id", ""))
	if not Research.can_research(tech_id, p, _db):
		return false
	p.current_research_id = tech_id
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

	# Spillover to stacked units
	if result["spillover_damage"] > 0:
		for u in Stack.at(_gs.units, defender.x, defender.y, defender.owner_player_id):
			if u.id != defender.id:
				u.health = max(0, u.health - int(result["spillover_damage"]))
				if u.health <= 0:
					Stack.remove_unit(_gs.units, u.id)

func _get_next_player_index(current_player_id: int) -> int:
	for i in range(_gs.players.size()):
		if _gs.players[i].id == current_player_id:
			return (i + 1) % _gs.players.size()
	return 0
