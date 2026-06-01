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

# ── Bug 10: 4-item civic system ────────────────────────────────────────────────

func test_civics_all_four_present() -> void:
	var db = _db()
	var pols = db.policies.get("policies", {})
	for cid in ["communism", "anarcho_communism", "anarcho_capitalism", "fascism"]:
		assert_true(pols.has(cid), "Civic '%s' must exist" % cid)
		assert_eq(str(pols[cid].get("category", "")), "civic",
			"Civic '%s' is in the 'civic' category" % cid)

func test_civics_category_registered() -> void:
	var db = _db()
	assert_true("civic" in db.policies.get("categories", []),
		"'civic' must be a registered policy category")

func test_set_civic_policy_applies() -> void:
	var db = _db()
	var facade = load("res://src/api/sim_facade.gd").new()
	facade.setup(db, 7, "tiny", "normal", "warlord",
		[{"name": "A", "leader_id": "", "traits": [], "starting_gold": 100}],
		["time"])
	var gs = facade.get_state()
	var pid = gs.players[0].id
	gs.current_player_id = pid
	var ok = facade.apply_command(Commands.set_policy(pid, "civic", "fascism"))
	assert_true(ok, "Selecting the fascism civic should be accepted")
	assert_eq(gs.players[0].policies.get("civic", ""), "fascism",
		"The civic category should now hold fascism")

# ── Bug 6: map generation ──────────────────────────────────────────────────────

func _generated_map(seed_val = 99):
	var db = _db()
	var facade = load("res://src/api/sim_facade.gd").new()
	facade.setup(db, seed_val, "small", "normal", "warlord",
		[{"name": "A", "leader_id": "", "traits": [], "starting_gold": 100}],
		["time"])
	return facade.get_state()

func test_map_has_terrain_on_every_tile() -> void:
	var gs = _generated_map()
	for tile in gs.map.all_tiles():
		assert_true(tile.terrain_id != "",
			"Every tile must have a terrain id after generation")

func test_map_is_varied() -> void:
	var gs = _generated_map()
	var kinds = {}
	for tile in gs.map.all_tiles():
		kinds[tile.terrain_id] = true
	assert_true(kinds.size() >= 4,
		"A varied map should contain several terrain types, got: " + str(kinds.keys()))

func test_map_has_substantial_land() -> void:
	var gs = _generated_map()
	var db = gs.db
	var land = 0
	for tile in gs.map.all_tiles():
		if db.get_terrain(tile.terrain_id).get("domain", "land") == "land":
			land += 1
	assert_true(land > gs.map.all_tiles().size() / 3,
		"At least a third of the map should be land for players to settle")

func test_map_generation_is_deterministic() -> void:
	var a = _generated_map(2024)
	var b = _generated_map(2024)
	var identical = true
	for i in range(a.map.all_tiles().size()):
		if a.map.all_tiles()[i].terrain_id != b.map.all_tiles()[i].terrain_id:
			identical = false
			break
	assert_true(identical, "Same seed must produce identical terrain across the whole map")

func test_start_positions_are_land_and_spread() -> void:
	var gs = _generated_map(555)
	var starts = MapGen.find_start_positions(gs.map, gs.db, 4)
	assert_eq(starts.size(), 4, "Should find four start positions")
	for s in starts:
		var ter = gs.db.get_terrain(gs.map.get_tile(int(s[0]), int(s[1])).terrain_id)
		assert_eq(ter.get("domain", "land"), "land", "Start tile must be land")
		assert_false(ter.get("impassable", false), "Start tile must be passable")

# ── Bug 4+5: starting units ────────────────────────────────────────────────────

func test_scout_unit_exists() -> void:
	var db = _db()
	assert_false(db.get_unit("scout").empty(), "A 'scout' unit type must exist")

func test_every_society_has_required_starting_units() -> void:
	var db = _db()
	var required = ["settler", "worker", "scout", "warrior", "archer"]
	for sid in db.get_societies():
		var su = db.get_society(sid).get("starting_units", [])
		for r in required:
			assert_true(r in su,
				"Society '%s' starting_units must include a %s" % [sid, r])

func test_player_with_society_spawns_units() -> void:
	var db = _db()
	var facade = load("res://src/api/sim_facade.gd").new()
	var annunaki = db.get_society("annunaki")
	facade.setup(db, 17, "small", "normal", "warlord",
		[{"name": "A", "leader_id": annunaki.get("leader_id", ""),
			"traits": annunaki.get("traits", []),
			"starting_gold": 120,
			"starting_units": annunaki.get("starting_units", [])}],
		["time"])
	var gs = facade.get_state()
	var pid = gs.players[0].id
	var mine = []
	for u in gs.units:
		if u.owner_player_id == pid:
			mine.append(u.unit_type_id)
	assert_eq(mine.size(), annunaki.get("starting_units", []).size(),
		"Player should spawn exactly its society's starting units")
	assert_true("settler" in mine and "scout" in mine and "archer" in mine,
		"Spawned units should include the core opening types")

func test_no_starting_units_when_config_omits_them() -> void:
	# Headless/test configs without a society spawn no units (keeps end-turn ready).
	var db = _db()
	var facade = load("res://src/api/sim_facade.gd").new()
	facade.setup(db, 3, "tiny", "normal", "warlord",
		[{"name": "A", "leader_id": "", "traits": [], "starting_gold": 50}],
		["time"])
	assert_eq(facade.get_state().units.size(), 0,
		"A config with no starting_units should spawn no units")

func test_starting_units_on_passable_land() -> void:
	var db = _db()
	var facade = load("res://src/api/sim_facade.gd").new()
	facade.setup(db, 88, "small", "normal", "warlord",
		[{"name": "A", "leader_id": "enlil", "traits": [],
			"starting_gold": 120,
			"starting_units": ["settler", "warrior"]}],
		["time"])
	var gs = facade.get_state()
	for u in gs.units:
		var ter = db.get_terrain(gs.map.get_tile(u.x, u.y).terrain_id)
		assert_eq(ter.get("domain", "land"), "land", "Units must spawn on land")
		assert_false(ter.get("impassable", false), "Units must spawn on passable tiles")

# ── Bug 1: Start Game blocked when a player has "No Society" ────────────────────

var _bug1_started = false
func _bug1_on_start(_facade, _db) -> void:
	_bug1_started = true

func test_bug1_blocks_start_until_every_player_picks_a_society() -> void:
	var db = _db()
	var screen = load("res://scenes/setup/setup_screen.gd").new()
	screen.anchor_right = 1.0
	screen.anchor_bottom = 1.0
	add_child_autofree(screen)
	screen.init(db, funcref(self, "_bug1_on_start"))
	_bug1_started = false

	# Default 2 players. Leave player 1 at "— No Society —" (index 0).
	screen._player_rows[0]["society_btn"].select(0)
	screen._player_rows[1]["society_btn"].select(1)
	assert_eq(screen._players_missing_society(2), [1],
		"Player 1 should be flagged as missing a society")

	screen._on_start_pressed()
	assert_false(_bug1_started,
		"Start must be blocked while any player has no society")
	assert_true(screen._error_label.visible, "An error message should be shown")

	# Give player 1 a society too → start should now proceed.
	screen._player_rows[0]["society_btn"].select(1)
	assert_eq(screen._players_missing_society(2), [],
		"No players should be missing a society now")
	screen._on_start_pressed()
	assert_true(_bug1_started,
		"Start proceeds once all players have chosen a society")

# ── Bug 8: slider redistribution keeps a predictable sum of 100 ────────────────

func _sum(a):
	var s = 0
	for v in a:
		s += int(v)
	return s

func test_slider_rebalance_always_sums_to_100() -> void:
	var SM = load("res://src/api/slider_math.gd")
	# Try moving each slider to each step value from a few starting splits.
	var starts = [[40, 40, 10, 10], [25, 25, 25, 25], [100, 0, 0, 0], [70, 10, 10, 10]]
	for st in starts:
		for idx in range(4):
			for target in [0, 10, 30, 50, 70, 100]:
				var out = SM.rebalance(st, idx, target)
				assert_eq(_sum(out), 100,
					"sum must stay 100 for start %s idx %d -> %d (got %s)" % [st, idx, target, out])
				assert_eq(int(out[idx]), target,
					"the moved slider must hold its new value")
				for v in out:
					assert_true(int(v) >= 0 and int(v) <= 100, "each value within [0,100]")

func test_slider_rebalance_is_deterministic() -> void:
	var SM = load("res://src/api/slider_math.gd")
	var a = SM.rebalance([40, 40, 10, 10], 0, 70)
	var b = SM.rebalance([40, 40, 10, 10], 0, 70)
	assert_eq(a, b, "Same input must give the same redistribution every time")

func test_slider_rebalance_takes_from_following_sliders_first() -> void:
	var SM = load("res://src/api/slider_math.gd")
	# Finance 40 -> 60: the +20 is pulled from research (next index) first.
	var out = SM.rebalance([40, 40, 10, 10], 0, 60)
	assert_eq(out, [60, 20, 10, 10],
		"Increase should be absorbed by the immediately following slider first")

# ── Bug 7: wild forces no longer flood the map each turn ───────────────────────

func test_wild_units_are_capped_over_many_turns() -> void:
	var db = _db()
	var facade = load("res://src/api/sim_facade.gd").new()
	facade.setup(db, 4242, "small", "normal", "warlord",
		[{"name": "A", "leader_id": "", "traits": [], "starting_gold": 50},
		 {"name": "B", "leader_id": "", "traits": [], "starting_gold": 50}],
		["time"])
	var gs = facade.get_state()

	# Run a number of world steps by cycling end-turns.
	for _t in range(20):
		for p in gs.players:
			gs.current_player_id = p.id
			facade.apply_command(Commands.end_turn(p.id))

	# Count land tiles and wild units; the cap is land/wild_land_per_unit.
	var land = 0
	for tile in gs.map.all_tiles():
		if db.get_terrain(tile.terrain_id).get("domain", "land") == "land":
			land += 1
	var wild = 0
	for u in gs.units:
		if u.is_wild:
			wild += 1
	var cap = land / int(db.constants.get("wild_land_per_unit", 80))
	assert_true(wild <= cap + 1,
		"Wild units (%d) must stay near the land-based cap (%d), not flood" % [wild, cap])

# ── Bug 2+3: pass-device overlay sits on top, OK dismisses and advances ─────────

func test_bug3_pass_device_overlay_wiring() -> void:
	var scene = load("res://scenes/hotseat/pass_device_screen.tscn").instance()
	add_child_autofree(scene)

	# It must live on its own CanvasLayer (above the HUD's layer) so input reaches
	# the OK button instead of being swallowed by the HUD.
	assert_true(scene is CanvasLayer, "overlay must be a CanvasLayer")
	assert_true(scene.layer > 1, "overlay layer must be above the HUD CanvasLayer")

	scene.init(null)
	assert_false(scene._root.visible, "overlay starts hidden")
	assert_true(scene._button.is_connected("pressed", scene, "_on_ok_pressed"),
		"OK button must be connected to its dismiss handler")

	scene.show_for_player("Bob", 2)
	assert_true(scene._root.visible, "overlay is visible after show_for_player")
	assert_true(get_tree().paused, "the game is paused while the overlay is up")

	scene._on_ok_pressed()
	assert_false(scene._root.visible, "OK dismisses the overlay")
	assert_false(get_tree().paused, "OK resumes the game so the next turn proceeds")

	get_tree().paused = false  # safety: never leave the test tree paused

# ── Bug E: a settler can found a city from the flyout menu ──────────────────────

func test_found_city_action_offered_and_works() -> void:
	var db = _db()
	var facade = load("res://src/api/sim_facade.gd").new()
	facade.setup(db, 31, "small", "normal", "warlord",
		[{"name": "A", "leader_id": "", "traits": [], "starting_gold": 50}],
		["time"])
	var gs = facade.get_state()
	var pid = gs.players[0].id
	gs.current_player_id = pid

	# Place a settler on a known land tile.
	gs.map.get_tile(6, 6).terrain_id = "grassland"
	var u = load("res://src/sim/unit.gd").new()
	u.id = gs.next_unit_id(); u.unit_type_id = "settler"
	u.owner_player_id = pid; u.x = 6; u.y = 6
	u.movement_total = 200; u.movement_left = 200
	gs.units.append(u)

	# The flyout must offer a Found City action for the settler.
	var menu = facade.get_flyout_menu(6, 6)
	var found_item = {}
	for it in menu:
		if int(it.get("action_id", -1)) == IDs.UnitMission.FOUND_SETTLEMENT:
			found_item = it
			break
	assert_false(found_item.empty(), "Flyout should offer Found City for a settler")

	var before = gs.settlements.size()
	var ok = facade.apply_command(Commands.found_settlement(pid, int(found_item.get("unit_id", u.id))))
	assert_true(ok, "Found settlement command should succeed")
	assert_eq(gs.settlements.size(), before + 1, "A new settlement should exist")
	assert_null(gs.get_unit(u.id), "The founding settler should be consumed")

func test_found_city_not_offered_for_warrior() -> void:
	var db = _db()
	var facade = load("res://src/api/sim_facade.gd").new()
	facade.setup(db, 32, "small", "normal", "warlord",
		[{"name": "A", "leader_id": "", "traits": [], "starting_gold": 50}],
		["time"])
	var gs = facade.get_state()
	var pid = gs.players[0].id
	gs.current_player_id = pid
	var u = load("res://src/sim/unit.gd").new()
	u.id = gs.next_unit_id(); u.unit_type_id = "warrior"
	u.owner_player_id = pid; u.x = 7; u.y = 7
	gs.units.append(u)
	for it in facade.get_flyout_menu(7, 7):
		assert_true(int(it.get("action_id", -1)) != IDs.UnitMission.FOUND_SETTLEMENT,
			"A warrior must not be offered Found City")

# ── Bug F: city view builds full info from a real settlement ───────────────────

func test_city_view_builds_from_settlement() -> void:
	var db = _db()
	var facade = load("res://src/api/sim_facade.gd").new()
	facade.setup(db, 71, "small", "normal", "warlord",
		[{"name": "A", "leader_id": "", "traits": [], "starting_gold": 50}],
		["time"])
	var gs = facade.get_state()
	var pid = gs.players[0].id
	gs.current_player_id = pid

	var s = load("res://src/sim/settlement.gd").new()
	s.id = gs.next_settlement_id(); s.name = "Testopolis"; s.owner_player_id = pid
	s.x = 5; s.y = 5; s.population = 3
	s.output_food = 4; s.output_production = 3; s.output_commerce = 6
	s.structures = ["granary"]
	s.production_queue = [{"type": "unit", "id": "warrior"}]
	s.worked_tiles = [[5, 5], [5, 6]]
	gs.settlements.append(s)
	gs.map.get_tile(5, 6).terrain_id = "grassland"

	var screen = load("res://scenes/screens/city_screen.gd").new()
	add_child_autofree(screen)
	screen.init(facade)
	# Call _build directly to bypass rebuild()'s idle-frame yield.
	screen._city_id = s.id
	screen.visible = true
	screen._build()
	assert_true(screen.get_child_count() > 0,
		"City screen must build content (background + info) from the settlement")

func test_city_view_add_to_production_queues_item() -> void:
	var db = _db()
	var facade = load("res://src/api/sim_facade.gd").new()
	facade.setup(db, 72, "small", "normal", "warlord",
		[{"name": "A", "leader_id": "", "traits": [], "starting_gold": 50}],
		["time"])
	var gs = facade.get_state()
	var pid = gs.players[0].id
	gs.current_player_id = pid
	var s = load("res://src/sim/settlement.gd").new()
	s.id = gs.next_settlement_id(); s.name = "Buildtown"; s.owner_player_id = pid
	s.x = 4; s.y = 4; s.population = 2
	gs.settlements.append(s)

	var screen = load("res://scenes/screens/city_screen.gd").new()
	add_child_autofree(screen)
	screen.init(facade)
	screen._city_id = s.id
	screen.visible = true
	screen._on_build("structure", "granary")
	assert_eq(s.production_queue.size(), 1, "Build button should queue one item")
	assert_eq(str(s.production_queue[0].get("id", "")), "granary",
		"The queued item should be the chosen structure")

# ── Scene smoke test: the whole main scene boots and is wired ───────────────────

func test_main_scene_boots_and_wires_overlays() -> void:
	var main = load("res://scenes/main.tscn").instance()
	add_child_autofree(main)
	# _ready ran the default 2-player fallback game.
	assert_not_null(main.get_facade(), "main should have a facade after _ready")
	assert_not_null(main.get_node_or_null("WorldView"), "world view present")
	assert_not_null(main.get_node_or_null("Screens/CityScreen"), "city screen wired")
	assert_not_null(main.get_node_or_null("Screens/TechChooser"), "tech chooser wired")
	assert_not_null(main.get_node_or_null("Screens/PolicyScreen"), "policy screen wired")
	# The fallback game gives both players their default opening units.
	assert_true(main.get_facade().get_state().units.size() > 0,
		"the booted game should have starting units")
	get_tree().paused = false  # safety in case an overlay toggled pause
