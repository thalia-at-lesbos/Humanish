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

# ── Move-unit sort bug: pathfinding over many equal-cost tiles ─────────────────

func test_pathfinding_over_open_field_returns_valid_path() -> void:
	# An open grassland field produces a frontier full of equal-cost nodes — the
	# case that used to hit Array.sort()'s "bad comparison function" on [cost,x,y].
	var db = _db()
	var map = load("res://src/world/world_map.gd").new()
	map.init(8, 8, false, false)
	for tile in map.all_tiles():
		tile.terrain_id = "grassland"
	var u = load("res://src/sim/unit.gd").new()
	u.id = 1; u.unit_type_id = "warrior"; u.owner_player_id = 1; u.x = 0; u.y = 0

	var path = Pathfinding.find_path(map, 0, 0, 5, 3, u, db, [], 1)
	assert_false(path.empty(), "A path across open land must be found")
	var last = path[path.size() - 1]
	assert_eq([int(last[0]), int(last[1])], [5, 3], "Path must end at the destination")
	# 4-directional movement: optimal length is the Manhattan distance.
	assert_eq(path.size(), 8, "Path length should be the Manhattan distance (5+3)")

func test_move_stack_command_succeeds_on_open_map() -> void:
	var db = _db()
	var facade = load("res://src/api/sim_facade.gd").new()
	facade.setup(db, 123, "small", "normal", "warlord",
		[{"name": "A", "leader_id": "", "traits": [], "starting_gold": 50}],
		["time"])
	var gs = facade.get_state()
	for tile in gs.map.all_tiles():
		tile.terrain_id = "grassland"
	var pid = gs.players[0].id
	gs.current_player_id = pid
	var u = load("res://src/sim/unit.gd").new()
	u.id = gs.next_unit_id(); u.unit_type_id = "warrior"; u.owner_player_id = pid
	u.x = 2; u.y = 2; u.movement_total = 200; u.movement_left = 200
	gs.units.append(u)
	var ok = facade.apply_command(Commands.move_stack(pid, 2, 2, 3, 2))
	assert_true(ok, "Moving a unit one tile on open land should succeed")

# ── Bug: "Open City" button shown for a unit when no city is selected ──────────

func _count_buttons_named(node, text):
	var n = 0
	for c in node.get_children():
		if c is Button and c.text == text:
			n += 1
	return n

func test_unit_panel_omits_open_city_button() -> void:
	var db = _db()
	var facade = load("res://src/api/sim_facade.gd").new()
	facade.setup(db, 81, "small", "normal", "warlord",
		[{"name": "A", "leader_id": "", "traits": [], "starting_gold": 50}],
		["time"])
	var gs = facade.get_state()
	var pid = gs.players[0].id
	gs.current_player_id = pid

	# A city and a (garrisoned) warrior on the same tile.
	var s = load("res://src/sim/settlement.gd").new()
	s.id = gs.next_settlement_id(); s.name = "Cap"; s.owner_player_id = pid
	s.x = 5; s.y = 5; s.population = 1
	gs.settlements.append(s)
	var w = load("res://src/sim/unit.gd").new()
	w.id = gs.next_unit_id(); w.unit_type_id = "warrior"; w.owner_player_id = pid
	w.x = 5; w.y = 5
	gs.units.append(w)

	# Sanity: the (right-click) flyout still offers Open City on that tile.
	var has_open = false
	for it in facade.get_flyout_menu(5, 5):
		if int(it.get("action_id", -1)) == IDs.ControlType.OPEN_CITY_SCREEN:
			has_open = true
	assert_true(has_open, "Flyout should still offer Open City on a city tile")

	# But the unit selection panel must not render an Open City button.
	var panel = load("res://scenes/hud/selection_panel.gd").new()
	add_child_autofree(panel)
	panel.init(facade, null)
	facade.select_unit(w.id)
	panel.rebuild()
	assert_eq(_count_buttons_named(panel, "Open City"), 0,
		"A selected unit must not show an Open City button (no city is selected)")
	# It should still show the unit's own actions.
	assert_true(panel.get_child_count() > 0, "The unit panel should still show unit info")

# ── Bug: fog of war doesn't update on movement / settling ──────────────────────

func test_fog_updates_when_world_changes() -> void:
	var db = _db()
	var facade = load("res://src/api/sim_facade.gd").new()
	facade.setup(db, 91, "small", "normal", "warlord",
		[{"name": "A", "leader_id": "", "traits": [], "starting_gold": 50}],
		["time"])
	var gs = facade.get_state()
	var pid = gs.players[0].id
	gs.current_player_id = pid
	var u = load("res://src/sim/unit.gd").new()
	u.id = gs.next_unit_id(); u.unit_type_id = "warrior"; u.owner_player_id = pid
	u.x = 5; u.y = 5
	gs.units.append(u)

	var wv = load("res://scenes/world/world_view.tscn").instance()
	add_child_autofree(wv)
	wv.init(facade)
	var fog = wv.get_node_or_null("FogLayer")
	assert_not_null(fog, "world view should have a fog layer")
	fog.init(facade)  # main.gd initialises the fog layer separately

	# A world change (e.g. a move) marks WORLD dirty; processing it rebuilds fog.
	facade.get_dirty().set_dirty(IDs.DirtyRegion.WORLD)
	wv._process(0.0)
	assert_true(fog.get_visible_tiles().has("5,5"),
		"Fog should reveal the tile the unit stands on")

	# Move the unit; the newly-seen tile must become visible after processing.
	u.x = 12; u.y = 9
	facade.get_dirty().set_dirty(IDs.DirtyRegion.WORLD)
	wv._process(0.0)
	assert_true(fog.get_visible_tiles().has("12,9"),
		"Fog should reveal the unit's new location after it moves")
	assert_false(fog.get_visible_tiles().has("5,5"),
		"The tile left behind should no longer be in current sight")

# ── Bug: units had unlimited movement; it must be class-based ──────────────────

func _move_distance_for(unit_type, sx, sy, tx, ty):
	# Spawn a unit of the given class on an open grassland map and try to move it
	# far in a single command; return how many tiles it actually advanced.
	var db = _db()
	var facade = load("res://src/api/sim_facade.gd").new()
	facade.setup(db, 7, "standard", "normal", "warlord",
		[{"name": "A", "leader_id": "", "traits": [], "starting_gold": 50}],
		["time"])
	var gs = facade.get_state()
	for tile in gs.map.all_tiles():
		tile.terrain_id = "grassland"
	var pid = gs.players[0].id
	gs.current_player_id = pid
	var u = load("res://src/sim/unit.gd").new()
	u.id = gs.next_unit_id(); u.unit_type_id = unit_type; u.owner_player_id = pid
	u.x = sx; u.y = sy
	var udata = db.get_unit(unit_type)
	u.movement_total = int(udata.get("movement", 200))
	u.movement_left = u.movement_total
	gs.units.append(u)
	facade.apply_command(Commands.move_stack(pid, sx, sy, tx, ty))
	# Chebyshev distance moved (4-dir path → equals tiles advanced along a row).
	return gs.map.distance(sx, sy, u.x, u.y)

func test_movement_is_bounded_by_class() -> void:
	# Warrior: movement 200 = 2 tiles per turn on flat land.
	var warrior_dist = _move_distance_for("warrior", 5, 5, 20, 5)
	assert_eq(warrior_dist, 2, "Warrior should advance exactly 2 tiles, not the full path")
	# Scout: movement 300 = 3 tiles, and faster than a warrior.
	var scout_dist = _move_distance_for("scout", 5, 5, 20, 5)
	assert_eq(scout_dist, 3, "Scout should advance exactly 3 tiles per turn")
	assert_true(scout_dist > warrior_dist, "Scout should out-range the warrior")

# ── Bug: units could not attack each other ─────────────────────────────────────

func test_pathfinding_allows_attacking_an_enemy_destination() -> void:
	var db = _db()
	var map = load("res://src/world/world_map.gd").new()
	map.init(8, 8, false, false)
	for tile in map.all_tiles():
		tile.terrain_id = "grassland"
	var attacker = load("res://src/sim/unit.gd").new()
	attacker.id = 1; attacker.unit_type_id = "warrior"; attacker.owner_player_id = 0
	attacker.x = 2; attacker.y = 2
	var enemy = load("res://src/sim/unit.gd").new()
	enemy.id = 2; enemy.unit_type_id = "warrior"; enemy.owner_player_id = 1
	enemy.x = 3; enemy.y = 2

	# A path INTO the enemy's tile (the destination) must be found...
	var into = Pathfinding.find_path(map, 2, 2, 3, 2, attacker, db, [attacker, enemy], 0)
	assert_false(into.empty(), "Should be able to path into an enemy destination (attack)")
	var last = into[into.size() - 1]
	assert_eq([int(last[0]), int(last[1])], [3, 2], "Attack path ends on the enemy tile")

	# ...but you still cannot path THROUGH an enemy to a tile beyond it on a 1-wide
	# corridor. Here the only route from (2,2) to (4,2) on open land goes around,
	# so a path exists but never steps onto the blocked (3,2).
	var through = Pathfinding.find_path(map, 2, 2, 4, 2, attacker, db, [attacker, enemy], 0)
	for step in through:
		assert_false(int(step[0]) == 3 and int(step[1]) == 2,
			"A through-route must not pass over the enemy-occupied tile")

func test_unit_can_attack_adjacent_enemy() -> void:
	var db = _db()
	var facade = load("res://src/api/sim_facade.gd").new()
	facade.setup(db, 5, "small", "normal", "warlord",
		[{"name": "A", "leader_id": "", "traits": [], "starting_gold": 50},
		 {"name": "B", "leader_id": "", "traits": [], "starting_gold": 50}],
		["time"])
	var gs = facade.get_state()
	for tile in gs.map.all_tiles():
		tile.terrain_id = "grassland"
	var p0 = gs.players[0].id
	var p1 = gs.players[1].id
	gs.current_player_id = p0

	var a = load("res://src/sim/unit.gd").new()
	a.id = gs.next_unit_id(); a.unit_type_id = "warrior"; a.owner_player_id = p0
	a.x = 5; a.y = 5; a.base_strength = 100; a.health = 100
	a.movement_total = 200; a.movement_left = 200
	gs.units.append(a)
	var d = load("res://src/sim/unit.gd").new()
	d.id = gs.next_unit_id(); d.unit_type_id = "warrior"; d.owner_player_id = p1
	d.x = 6; d.y = 5; d.base_strength = 1; d.health = 100
	gs.units.append(d)

	watch_signals(facade)
	var ok = facade.apply_command(Commands.move_stack(p0, 5, 5, 6, 5))
	assert_true(ok, "Attack-move onto an adjacent enemy should be accepted")
	assert_signal_emitted(facade, "combat_resolved",
		"Moving onto an enemy must resolve combat")
	# An overwhelmingly strong attacker should win and take the tile.
	assert_null(gs.get_unit(d.id), "The weak defender should be destroyed")
	var av = gs.get_unit(a.id)
	assert_not_null(av, "The strong attacker should survive")
	assert_eq([av.x, av.y], [6, 5], "The victorious attacker advances onto the captured tile")
