extends "res://addons/gut/test.gd"

# Phase 4: Player economy & research tests.

func _make_gs():
	var db = load("res://src/core/data_db.gd").new()
	db.load_all()
	var gs = load("res://src/sim/game_state.gd").new()
	gs.db = db
	gs.rng = load("res://src/core/rng.gd").new()
	gs.rng.init(1)
	gs.map = load("res://src/world/world_map.gd").new()
	gs.map.init(10, 10, false, false)
	for tile in gs.map.all_tiles():
		tile.terrain_id = "grassland"
	gs.pace_id = "normal"
	gs.difficulty_id = "prince"
	var p = load("res://src/sim/player.gd").new()
	p.id = 1; p.alliance_id = 1; p.treasury = 100
	p.slider_finance = 50; p.slider_research = 30
	p.slider_culture = 10; p.slider_intel = 10
	gs.players.append(p)
	var a = load("res://src/sim/alliance.gd").new()
	a.id = 1; a.add_member(1)
	gs.alliances.append(a)
	return gs

# ── Treasury & upkeep ──────────────────────────────────────────────────────────

func test_treasury_increases_from_commerce() -> void:
	var gs = _make_gs()
	var p = gs.get_player(1)
	var s = load("res://src/sim/settlement.gd").new()
	s.id = gs.next_settlement_id(); s.owner_player_id = 1
	s.x = 5; s.y = 5; s.population = 1
	s.output_commerce = 10
	gs.settlements.append(s)
	var before: int = p.treasury
	TurnEngine._update_treasury(gs, p)
	assert_true(p.treasury >= before,
		"Treasury should not decrease when commerce > upkeep")

func test_unit_upkeep_reduces_treasury() -> void:
	var gs = _make_gs()
	var p = gs.get_player(1)
	p.treasury = 100
	var u = load("res://src/sim/unit.gd").new()
	u.id = gs.next_unit_id(); u.unit_type_id = "warrior"
	u.owner_player_id = 1; u.x = 5; u.y = 5
	gs.units.append(u)
	TurnEngine._update_treasury(gs, p)
	assert_lt(p.treasury, 100, "Warrior upkeep reduces treasury")

func test_insolvency_clamps_treasury_to_zero() -> void:
	var gs = _make_gs()
	var p = gs.get_player(1)
	p.treasury = 0
	for i in range(10):
		var u = load("res://src/sim/unit.gd").new()
		u.id = gs.next_unit_id(); u.unit_type_id = "warrior"
		u.owner_player_id = 1; u.x = i; u.y = 0
		gs.units.append(u)
	TurnEngine._update_treasury(gs, p)
	assert_true(p.treasury >= 0, "Treasury never goes negative (clamped)")

# ── Research ───────────────────────────────────────────────────────────────────

func test_can_research_tech_no_prereqs() -> void:
	var gs = _make_gs()
	var p = gs.get_player(1)
	assert_true(Research.can_research("mining", p, gs.db),
		"Mining has no prereqs, should be researchable")

func test_cannot_research_already_known() -> void:
	var gs = _make_gs()
	var p = gs.get_player(1)
	p.technologies.append("mining")
	assert_false(Research.can_research("mining", p, gs.db),
		"Cannot research a tech already known")

func test_cannot_research_missing_prereq() -> void:
	var gs = _make_gs()
	var p = gs.get_player(1)
	assert_false(Research.can_research("iron_working", p, gs.db),
		"Cannot research iron_working without mining prereq")

func test_can_research_with_prereq() -> void:
	var gs = _make_gs()
	var p = gs.get_player(1)
	p.technologies.append("mining")
	assert_true(Research.can_research("iron_working", p, gs.db),
		"Can research iron_working when mining is known")

func test_research_accumulates_and_completes() -> void:
	var gs = _make_gs()
	var p = gs.get_player(1)
	p.current_research_id = "mining"
	var s = load("res://src/sim/settlement.gd").new()
	s.id = gs.next_settlement_id(); s.owner_player_id = 1
	s.x = 5; s.y = 5; s.population = 1
	s.output_commerce = 100  # 30% research = 30/turn
	gs.settlements.append(s)
	var completed: bool = false
	for _i in range(5):
		TurnEngine._apply_research(gs, p)
		if p.current_research_id == "":
			completed = true
			break
	assert_true(completed, "Mining should complete within 5 turns")
	assert_true(p.has_tech("mining"), "Player should have mining after research")

func test_research_prereq_discount_applies() -> void:
	var gs = _make_gs()
	var p = gs.get_player(1)
	p.technologies.append("mining")
	var cost_with: int = Research._effective_cost("iron_working", p, gs.db, {}, "normal")
	var p2 = load("res://src/sim/player.gd").new()
	p2.id = 99; p2.technologies = []
	var cost_without: int = Research._effective_cost("iron_working", p2, gs.db, {}, "normal")
	assert_true(cost_with <= cost_without,
		"Having prereq should reduce or equal research cost")

# ── Policies ──────────────────────────────────────────────────────────────────

func test_policy_set_and_switch() -> void:
	var p = load("res://src/sim/player.gd").new()
	p.id = 1
	p.policies["government"] = "despotism"
	assert_eq(p.policies["government"], "despotism", "Policy is set correctly")
	p.policies["government"] = "monarchy"
	assert_eq(p.policies["government"], "monarchy", "Policy switches correctly")

func test_policy_transition_ticks_down() -> void:
	var gs = _make_gs()
	var p = gs.get_player(1)
	p.transition_turns = 3
	TurnEngine._tick_states(gs, p)
	assert_eq(p.transition_turns, 2, "Transition turns tick down by 1 per turn")
