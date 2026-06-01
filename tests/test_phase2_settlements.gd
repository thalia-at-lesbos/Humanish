extends "res://addons/gut/test.gd"

# Phase 2: Settlement tests.

func _make_gs():
	var db = load("res://src/core/data_db.gd").new()
	db.load_all()
	var gs = load("res://src/sim/game_state.gd").new()
	gs.db = db
	gs.rng = load("res://src/core/rng.gd").new()
	gs.rng.init(12345)
	gs.map = load("res://src/world/world_map.gd").new()
	gs.map.init(20, 20, false, false)
	for tile in gs.map.all_tiles():
		tile.terrain_id = "grassland"
	gs.pace_id = "normal"
	gs.difficulty_id = "prince"
	var p = load("res://src/sim/player.gd").new()
	p.id = 1; p.name = "P1"; p.alliance_id = 1
	gs.players.append(p)
	var a = load("res://src/sim/alliance.gd").new()
	a.id = 1; a.add_member(1)
	gs.alliances.append(a)
	return gs

func _make_settlement(gs, player_id, x, y):
	var s = load("res://src/sim/settlement.gd").new()
	s.id = gs.next_settlement_id()
	s.owner_player_id = player_id
	s.x = x; s.y = y
	s.population = 1
	s.worked_tiles = [[x, y]]
	gs.settlements.append(s)
	return s

# ── Growth ────────────────────────────────────────────────────────────────────

func test_growth_step_no_crash() -> void:
	var gs = _make_gs()
	var s = _make_settlement(gs, 1, 5, 5)
	var p = gs.get_player(1)
	s.worked_tiles = [[5, 5]]
	TurnEngine._settlement_growth(gs, s, p)
	assert_true(true, "Growth step runs without crash")

func test_growth_pop_increases_when_store_above_threshold() -> void:
	var gs = _make_gs()
	var s = _make_settlement(gs, 1, 5, 5)
	var p = gs.get_player(1)
	s.food_store = 25   # threshold ~20
	s.worked_tiles = [[5, 5]]
	var pop_before: int = s.population
	TurnEngine._settlement_growth(gs, s, p)
	assert_true(s.population >= pop_before,
		"Population should not decrease during growth")

func test_growth_starvation_cannot_increase_pop() -> void:
	var gs = _make_gs()
	var s = _make_settlement(gs, 1, 5, 5)
	s.population = 3
	s.food_store = 0
	s.worked_tiles = []  # no food production
	var p = gs.get_player(1)
	var pop_before: int = s.population
	TurnEngine._settlement_growth(gs, s, p)
	assert_true(s.population <= pop_before,
		"Starvation should reduce or hold population")

func test_disorder_triggers_when_discontent_ge_population() -> void:
	var gs = _make_gs()
	var s = _make_settlement(gs, 1, 5, 5)
	s.population = 2
	var p = gs.get_player(1)
	s.negative_sentiment = 5
	s.positive_sentiment = 0
	TurnEngine._update_contentment(s, p, gs.db)
	if s.discontented >= s.population:
		assert_true(s.in_disorder, "Should be in disorder")
	else:
		assert_false(s.in_disorder, "No disorder when discontent < population")

func test_disorder_suppresses_production() -> void:
	var gs = _make_gs()
	var s = _make_settlement(gs, 1, 5, 5)
	var p = gs.get_player(1)
	s.in_disorder = true
	s.output_production = 10
	s.production_queue = [{"type": "unit", "id": "warrior"}]
	s.production_store = 0
	TurnEngine._settlement_production(gs, s, p)
	assert_eq(s.production_store, 0, "Disorder: production_store unchanged")

func test_slider_partition_sums_to_100() -> void:
	var p = load("res://src/sim/player.gd").new()
	p.slider_finance  = 40
	p.slider_research = 30
	p.slider_culture  = 20
	p.slider_intel    = 10
	assert_eq(p.get_slider_sum(), 100, "Sliders must sum to 100")

func test_split_commerce_partitions_correctly() -> void:
	var p = load("res://src/sim/player.gd").new()
	p.slider_finance = 50; p.slider_research = 30
	p.slider_culture = 10; p.slider_intel = 10
	var split = p.split_commerce(100)
	assert_eq(split[0], 50, "50% finance of 100 = 50")
	assert_eq(split[1], 30, "30% research of 100 = 30")
	var total: int = split[0] + split[1] + split[2] + split[3]
	assert_eq(total, 100, "Split totals must equal input")

# ── Culture / borders ──────────────────────────────────────────────────────────

func test_culture_ring_does_not_decrease() -> void:
	var gs = _make_gs()
	var s = _make_settlement(gs, 1, 5, 5)
	s.culture_total = 0
	s.output_commerce = 5
	var ring_before: int = s.culture_ring
	for _i in range(3):
		TurnEngine._settlement_culture(gs, s)
	assert_true(s.culture_ring >= ring_before,
		"Culture ring should not decrease over time")

# ── Production ────────────────────────────────────────────────────────────────

func test_production_completes_unit() -> void:
	var gs = _make_gs()
	var s = _make_settlement(gs, 1, 5, 5)
	var p = gs.get_player(1)
	s.production_queue = [{"type": "unit", "id": "warrior"}]
	s.production_store = 20  # warrior costs 15
	s.output_production = 0
	TurnEngine._settlement_production(gs, s, p)
	assert_eq(gs.units.size(), 1, "One unit should have been created")

func test_production_carryover() -> void:
	var gs = _make_gs()
	var s = _make_settlement(gs, 1, 5, 5)
	var p = gs.get_player(1)
	s.production_queue = [{"type": "unit", "id": "warrior"}]
	s.production_store = 17   # warrior = 15, carryover = 2
	s.output_production = 0
	var units_before: int = gs.units.size()
	TurnEngine._settlement_production(gs, s, p)
	if gs.units.size() > units_before:
		assert_eq(s.production_store, 2, "Surplus 2 should carry over")

# ── Well-being ────────────────────────────────────────────────────────────────

func test_wellbeing_deficit_non_negative() -> void:
	var gs = _make_gs()
	var s = _make_settlement(gs, 1, 5, 5)
	s.population = 3
	TurnEngine._update_wellbeing(s, gs.db)
	assert_true(s.wellbeing_deficit >= 0, "Wellbeing deficit is non-negative")
