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

# ── Item 3: ZoC & 8-direction movement (§1.2, §5.2) ────────────────────────────

func test_pathfinding_uses_diagonals() -> void:
	var gs = _make_gs()
	var u = _unit(gs, "warrior", 1, 5, 5)
	var path = Pathfinding.find_path(gs.map, 5, 5, 7, 7, u, gs.db, gs.units, 1)
	assert_eq(path.size(), 2, "Diagonal movement reaches (7,7) in two steps, not four")

func test_zone_of_control_halts_movement() -> void:
	var gs = _make_gs()
	var f = _facade(gs)
	# A two-wide land corridor on rows 5-6; everything else impassable mountain.
	for tile in gs.map.all_tiles():
		if tile.y != 5 and tile.y != 6:
			tile.terrain_id = "mountain"
	var u = _unit(gs, "warrior", 1, 3, 5)
	u.movement_total = 1000; u.movement_left = 1000  # plenty to reach (12,5)
	_unit(gs, "warrior", -2, 8, 6)  # wild unit beside the corridor at (8,6)
	f._cmd_move_stack({"player_id": 1, "from_x": 3, "from_y": 5, "to_x": 12, "to_y": 5})
	assert_eq(u.x, 7, "Unit halts on the tile adjacent to the hostile unit")
	assert_eq(u.movement_left, 0, "Zone of control spends remaining movement")

# ── Item 4: Air units (§5.2) ───────────────────────────────────────────────────

func test_air_strike_hits_without_advancing() -> void:
	var gs = _make_gs()
	var f = _facade(gs)
	gs.players[1].alliance_id = 2  # ensure at-war target
	gs.alliances[0].at_war_with = [2]; gs.alliances[1].at_war_with = [1]
	var fighter = _unit(gs, "fighter", 1, 5, 5)
	var target = _unit(gs, "warrior", 2, 8, 5)  # within air_range 4
	target.base_strength = 1; target.health = 1
	f._cmd_mission({"type": IDs.CommandType.MISSION_BOMBARD, "player_id": 1,
		"unit_id": fighter.id, "target_x": 8, "target_y": 5})
	assert_eq(fighter.x, 5, "Bomber does not advance onto the target tile")
	assert_eq(fighter.y, 5, "Bomber stays at its base position")

func test_air_strike_out_of_range_rejected() -> void:
	var gs = _make_gs()
	var f = _facade(gs)
	gs.alliances[0].at_war_with = [2]; gs.alliances[1].at_war_with = [1]
	var fighter = _unit(gs, "fighter", 1, 5, 5)
	var target = _unit(gs, "warrior", 2, 15, 5)  # distance 10 > air_range 4
	assert_false(f._cmd_mission({"type": IDs.CommandType.MISSION_BOMBARD, "player_id": 1,
		"unit_id": fighter.id, "target_x": 15, "target_y": 5}),
		"A target beyond air range cannot be struck")

func test_airlift_limited_by_range() -> void:
	var gs = _make_gs()
	var f = _facade(gs)
	var fighter = _unit(gs, "fighter", 1, 5, 5)
	assert_false(f._cmd_mission({"type": IDs.CommandType.MISSION_AIRLIFT, "player_id": 1,
		"unit_id": fighter.id, "target_x": 19, "target_y": 19}),
		"Air units cannot airlift beyond their range")
	assert_true(f._cmd_mission({"type": IDs.CommandType.MISSION_AIRLIFT, "player_id": 1,
		"unit_id": fighter.id, "target_x": 7, "target_y": 6}),
		"Within range the airlift succeeds")

# ── Item 5: Subordination / tributaries (§7) ───────────────────────────────────

func test_become_tributary_records_relationship() -> void:
	var gs = _make_gs()
	var f = _facade(gs)
	gs.alliances[0].at_war_with = [2]; gs.alliances[1].at_war_with = [1]
	# Player 2's alliance (2) submits to alliance 1.
	assert_true(f._cmd_set_subordination({"player_id": 2, "overlord_alliance_id": 1}),
		"Subordination command succeeds")
	assert_eq(gs.alliances[1].is_subordinate_to, 1, "Subordinate records its overlord")
	assert_true(2 in gs.alliances[0].tributaries, "Overlord records the tributary")
	assert_false(gs.alliances[0].is_at_war_with(2), "War between them ends on submission")

func test_tributary_joins_overlord_wars() -> void:
	var gs = _make_gs()
	var f = _facade(gs)
	gs.alliances[0].at_war_with = [9]  # overlord at war with alliance 9
	f._cmd_set_subordination({"player_id": 2, "overlord_alliance_id": 1})
	assert_true(gs.alliances[1].is_at_war_with(9), "Tributary inherits the overlord's wars")

func test_tribute_transfers_treasury() -> void:
	var gs = _make_gs()
	var f = _facade(gs)
	gs.get_player(2).treasury = 100
	gs.get_player(1).treasury = 0
	f._cmd_set_subordination({"player_id": 2, "overlord_alliance_id": 1})
	TurnEngine._collect_tribute(gs)
	var pct: int = gs.db.get_constant("tribute_pct", 10)
	assert_eq(gs.get_player(2).treasury, 100 - 10, "Tributary pays tribute")
	assert_eq(gs.get_player(1).treasury, 10, "Overlord receives the tribute")

# ── Item 6: Upkeep scaling + insolvency (§6.1) ─────────────────────────────────

func test_distant_settlement_costs_more_upkeep() -> void:
	var gs = _make_gs()
	var p = gs.get_player(1)
	# Capital at (1,1); a far settlement costs distance-scaled upkeep.
	_settlement(gs, 1, 1, 1, 1)
	p.treasury = 1000
	TurnEngine._update_treasury(gs, p)
	var near_treasury: int = p.treasury
	var gs2 = _make_gs()
	var p2 = gs2.get_player(1)
	_settlement(gs2, 1, 1, 1, 1)
	_settlement(gs2, 1, 18, 18, 1)  # far from capital
	p2.treasury = 1000
	TurnEngine._update_treasury(gs2, p2)
	assert_lt(p2.treasury, near_treasury, "A distant second settlement raises upkeep")

func test_insolvency_disbands_units() -> void:
	var gs = _make_gs()
	var p = gs.get_player(1)
	p.treasury = 0
	p.insolvent_turns = 5  # already past the grace period
	for i in range(10):
		_unit(gs, "warrior", 1, i, 0)
	var before: int = gs.units.size()
	TurnEngine._update_treasury(gs, p)
	assert_true(gs.units.size() < before, "Insolvency disbands units to cover upkeep")
	assert_true(p.treasury >= 0, "Treasury is non-negative after insolvency handling")

func test_insolvency_sells_structure_before_disbanding() -> void:
	var gs = _make_gs()
	var p = gs.get_player(1)
	p.treasury = 0
	p.insolvent_turns = 5  # already past the grace period
	var s = _settlement(gs, 1, 5, 5, 1)
	s.structures = ["granary"]
	_unit(gs, "warrior", 1, 6, 6)
	for i in range(20):
		_unit(gs, "warrior", 1, i, 1)
	TurnEngine._update_treasury(gs, p)
	assert_true(s.structures.empty(), "A structure is sold during insolvency")

# ── Item 7: Slider policy constraints (§6.2) ───────────────────────────────────

func test_sliders_unconstrained_without_policy() -> void:
	var gs = _make_gs()
	var f = _facade(gs)
	gs.current_player_id = 1
	assert_true(f.apply_command(Commands.set_sliders(1, 37, 33, 20, 10)),
		"Without a governing policy any 100-sum split is allowed")

func test_policy_increment_enforced() -> void:
	var gs = _make_gs()
	var f = _facade(gs)
	gs.current_player_id = 1
	gs.get_player(1).policies = {"government": "republic"}  # increment 10
	assert_false(f.apply_command(Commands.set_sliders(1, 35, 35, 20, 10)),
		"Off-increment sliders are rejected")
	assert_true(f.apply_command(Commands.set_sliders(1, 40, 30, 20, 10)),
		"On-increment sliders are accepted")

func test_policy_min_research_enforced() -> void:
	var gs = _make_gs()
	var f = _facade(gs)
	gs.current_player_id = 1
	gs.get_player(1).policies = {"government": "republic"}  # min_research 10
	assert_false(f.apply_command(Commands.set_sliders(1, 100, 0, 0, 0)),
		"Research below the policy minimum is rejected")

func test_policy_max_research_cap_enforced() -> void:
	var gs = _make_gs()
	var f = _facade(gs)
	gs.current_player_id = 1
	gs.get_player(1).policies = {"civic": "communism"}  # max_research 50
	assert_false(f.apply_command(Commands.set_sliders(1, 10, 90, 0, 0)),
		"Research above the policy cap is rejected")
	assert_true(f.apply_command(Commands.set_sliders(1, 50, 50, 0, 0)),
		"Research at the cap is accepted")
