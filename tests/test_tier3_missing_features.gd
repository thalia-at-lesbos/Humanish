extends "res://addons/gut/test.gd"

# Tier 3 breadth/depth items from docs/missing-engine-features.md.
# Each item is implemented and committed separately; tests are grouped per item.

func _make_db():
	var db = load("res://src/core/data_db.gd").new()
	db.load_all()
	return db

func _make_gs():
	var db = _make_db()
	var gs = load("res://src/sim/game_state.gd").new()
	gs.db = db
	gs.rng = load("res://src/core/rng.gd").new()
	gs.rng.init(42)
	gs.map = load("res://src/world/world_map.gd").new()
	gs.map.init(20, 20, false, false)
	for tile in gs.map.all_tiles():
		tile.terrain_id = "grassland"
	var p1 = load("res://src/sim/player.gd").new()
	p1.id = 1; p1.alliance_id = 1
	var p2 = load("res://src/sim/player.gd").new()
	p2.id = 2; p2.alliance_id = 2
	gs.players.append(p1); gs.players.append(p2)
	var a1 = load("res://src/sim/alliance.gd").new(); a1.id = 1; a1.add_member(1)
	var a2 = load("res://src/sim/alliance.gd").new(); a2.id = 2; a2.add_member(2)
	gs.alliances.append(a1); gs.alliances.append(a2)
	return gs

func _facade(gs):
	var f = load("res://src/api/sim_facade.gd").new()
	f._gs = gs
	f._db = gs.db
	f._dirty = load("res://src/api/dirty_flags.gd").new()
	return f

func _hooks():
	return load("res://src/sim/hooks.gd").new()

func _unit(gs, type_id, player_id, x, y):
	var u = load("res://src/sim/unit.gd").new()
	u.id = gs.next_unit_id()
	u.unit_type_id = type_id
	u.owner_player_id = player_id
	u.x = x; u.y = y
	var ud = gs.db.get_unit(type_id)
	u.base_strength = int(ud.get("base_strength", 5))
	u.health = 100
	u.movement_total = int(ud.get("movement", 200)); u.movement_left = u.movement_total
	gs.units.append(u)
	return u

func _settlement(gs, player_id, x, y, pop = 5):
	var s = load("res://src/sim/settlement.gd").new()
	s.id = gs.next_settlement_id(); s.owner_player_id = player_id
	s.x = x; s.y = y; s.population = pop
	gs.settlements.append(s)
	return s

# ── Item 1: Assemblies / diplomatic victory (§3.7, §10) ────────────────────────

func test_assembly_tallies_votes_by_population() -> void:
	var gs = _make_gs()
	_settlement(gs, 1, 3, 3, 7)
	_settlement(gs, 2, 9, 9, 3)
	TurnEngine._resolve_assembly(gs)
	assert_eq(int(gs.diplomatic_votes.get(1, 0)), 7, "Alliance 1 polls its population")
	assert_eq(int(gs.diplomatic_votes.get(2, 0)), 3, "Alliance 2 polls its population")

func test_assembly_enables_diplomatic_victory() -> void:
	var gs = _make_gs()
	gs.enabled_win_conditions = ["diplomatic"]
	_settlement(gs, 1, 3, 3, 7)   # 70% of 10 votes
	_settlement(gs, 2, 9, 9, 3)
	TurnEngine.world_step(gs, _hooks())
	assert_eq(gs.winning_alliance_id, 1,
		"A population supermajority wins the assembly vote")

func test_no_diplomatic_win_when_split() -> void:
	var gs = _make_gs()
	gs.enabled_win_conditions = ["diplomatic"]
	_settlement(gs, 1, 3, 3, 5)
	_settlement(gs, 2, 9, 9, 5)
	TurnEngine.world_step(gs, _hooks())
	assert_eq(gs.winning_alliance_id, -1, "An even split elects no one")

# ── Item 2: Events + exploration rewards (§9) ──────────────────────────────────

func test_events_table_loads() -> void:
	var db = _make_db()
	assert_true(db.events.has("ancient_windfall"), "events.json loads into DataDB")
	assert_true(db.get_errors().empty(), "DataDB still loads cleanly with events table")

func test_scripted_event_fires_once_after_min_turn() -> void:
	var gs = _make_gs()
	var p = gs.get_player(1)
	p.treasury = 0
	gs.turn_number = 10  # >= min_turn 8
	var fired = Events.process_player_events(p, gs, gs.rng)
	assert_eq(fired.size(), 1, "Event fires when its min_turn is reached")
	assert_eq(p.treasury, 50, "Event treasury effect applied")
	Events.process_player_events(p, gs, gs.rng)
	assert_eq(p.treasury, 50, "A once-fired event does not repeat")

func test_scripted_event_held_before_min_turn() -> void:
	var gs = _make_gs()
	var p = gs.get_player(1)
	gs.turn_number = 2  # < min_turn 8
	var fired = Events.process_player_events(p, gs, gs.rng)
	assert_true(fired.empty(), "Event does not fire before its min_turn")

func test_entering_discovery_site_yields_reward() -> void:
	var gs = _make_gs()
	var f = _facade(gs)
	gs.map.get_tile(6, 5).has_discovery = true
	var u = _unit(gs, "warrior", 1, 5, 5)
	f._cmd_move_stack({"player_id": 1, "from_x": 5, "from_y": 5, "to_x": 6, "to_y": 5})
	assert_false(gs.map.get_tile(6, 5).has_discovery, "Discovery site is consumed on entry")
