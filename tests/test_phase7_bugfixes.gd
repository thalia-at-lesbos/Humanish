extends "res://addons/gut/test.gd"

# Phase 7: regression tests for the user-reported bug fixes.
# Covers the tech tree, civics, map generation, starting units, and slider math.

func _db():
	var db = load("res://src/core/data_db.gd").new()
	db.load_all()
	return db

func _new_player(db):
	var p = load("res://src/sim/player.gd").new()
	p.id = 1
	p.alliance_id = 1
	return p

# ── Bug 9: 4-stage tech tree (stone → bronze → iron → silicon) ─────────────────

func test_tech_tree_loads_without_errors() -> void:
	var db = _db()
	assert_true(db.get_errors().empty(),
		"DataDB should load all tables (incl. tech tree) with no errors: " + str(db.get_errors()))

func test_tech_tree_four_ages_present() -> void:
	var db = _db()
	for tid in ["stone_age", "bronze_age", "iron_age", "silicon_age"]:
		assert_false(db.get_technology(tid).empty(), "Tech '%s' must exist" % tid)

func test_tech_tree_is_linear_progression() -> void:
	var db = _db()
	assert_eq(db.get_technology("bronze_age").get("prereqs_all"), ["stone_age"],
		"bronze_age requires stone_age")
	assert_eq(db.get_technology("iron_age").get("prereqs_all"), ["bronze_age"],
		"iron_age requires bronze_age")
	assert_eq(db.get_technology("silicon_age").get("prereqs_all"), ["iron_age"],
		"silicon_age requires iron_age")

func test_tech_tree_research_gating() -> void:
	var db = _db()
	var Research = load("res://src/sim/research.gd")
	var p = _new_player(db)
	# Knows nothing → only stone_age (no prereqs) is researchable.
	assert_true(Research.can_research("stone_age", p, db), "stone_age open from the start")
	assert_false(Research.can_research("bronze_age", p, db), "bronze_age locked without stone_age")
	p.technologies = ["stone_age"]
	assert_true(Research.can_research("bronze_age", p, db), "bronze_age unlocks after stone_age")
	assert_false(Research.can_research("iron_age", p, db), "iron_age still locked")

func test_setup_seeds_starting_tech_and_research() -> void:
	var db = _db()
	var facade = load("res://src/api/sim_facade.gd").new()
	facade.setup(db, 42, "tiny", "normal", "warlord",
		[{"name": "A", "leader_id": "", "traits": [], "starting_gold": 100}],
		["time"])
	var p = facade.get_state().players[0]
	assert_true(p.has_tech("stone_age"), "Players start knowing stone_age")
	assert_eq(p.current_research_id, "bronze_age", "Default research target is bronze_age")
