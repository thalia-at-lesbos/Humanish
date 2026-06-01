extends "res://addons/gut/test.gd"

# Phase 1: World model tests.
# Note: helper functions omit class-name return types to avoid parse-order issues.

func _make_map(w, h, wrap_x = true, wrap_y = false):
	var m = load("res://src/world/world_map.gd").new()
	m.init(w, h, wrap_x, wrap_y)
	return m

func _make_db():
	var db = load("res://src/core/data_db.gd").new()
	db.load_all()
	return db

# ── Distance & wrapping ────────────────────────────────────────────────────────

func test_distance_no_wrap() -> void:
	var m = _make_map(20, 20, false, false)
	assert_eq(m.distance(0, 0, 3, 4), 4, "Chebyshev max(3,4)=4")
	assert_eq(m.distance(5, 5, 5, 5), 0, "same tile = 0")
	assert_eq(m.distance(0, 0, 2, 2), 2, "diagonal 2 = 2")

func test_distance_wrap_x() -> void:
	var m = _make_map(10, 10, true, false)
	assert_eq(m.distance(0, 0, 9, 0), 1, "wrap-x: shorter path is 1")

func test_distance_no_wrap_y() -> void:
	var m = _make_map(10, 10, false, false)
	assert_eq(m.distance(0, 0, 0, 9), 9, "no wrap-y: direct = 9")

func test_get_tile_wraps_x() -> void:
	var m = _make_map(10, 10, true, false)
	var t1 = m.get_tile(0, 0)
	var t2 = m.get_tile(10, 0)
	assert_eq(t1, t2, "get_tile wraps x correctly")

func test_get_tile_out_of_bounds_no_wrap() -> void:
	var m = _make_map(10, 10, false, false)
	var t = m.get_tile(15, 0)
	assert_null(t, "Out of bounds without wrap returns null")

func test_neighbours4_count_interior() -> void:
	var m = _make_map(10, 10, false, false)
	assert_eq(m.neighbours4(5, 5).size(), 4, "Interior tile has 4 cardinal neighbours")

func test_neighbours4_count_corner_no_wrap() -> void:
	var m = _make_map(10, 10, false, false)
	assert_eq(m.neighbours4(0, 0).size(), 2, "Corner without wrap has 2 neighbours")

func test_neighbours8_count_interior() -> void:
	var m = _make_map(10, 10, false, false)
	assert_eq(m.neighbours8(5, 5).size(), 8, "Interior tile has 8 neighbours")

func test_tiles_in_range() -> void:
	var m = _make_map(20, 20, false, false)
	var tiles = m.tiles_in_range(5, 5, 2)
	assert_eq(tiles.size(), 25, "Range 2 = 25 tiles (5x5)")

func test_ring_at_distance_0() -> void:
	var m = _make_map(10, 10, false, false)
	var ring = m.ring_at_distance(5, 5, 0)
	assert_eq(ring.size(), 1, "Ring at distance 0 = 1 tile (center)")

func test_ring_at_distance_1() -> void:
	var m = _make_map(10, 10, false, false)
	var ring = m.ring_at_distance(5, 5, 1)
	assert_eq(ring.size(), 8, "Ring at distance 1 = 8 tiles")

# ── Tile output ────────────────────────────────────────────────────────────────

func test_tile_output_grassland_no_improvement() -> void:
	var db = _make_db()
	var tile = load("res://src/world/tile.gd").new(0, 0)
	tile.terrain_id = "grassland"
	var out = TileOutput.compute(tile, db, [])
	assert_eq(out[IDs.Output.FOOD], 2, "Grassland: 2 food")
	assert_eq(out[IDs.Output.PRODUCTION], 1, "Grassland: 1 production")

func test_tile_output_clamp_never_negative() -> void:
	var db = _make_db()
	var tile = load("res://src/world/tile.gd").new(0, 0)
	tile.terrain_id = "snow"
	var out = TileOutput.compute(tile, db, [])
	for v in out:
		assert_true(v >= 0, "No output type should be negative")

func test_tile_output_improvement_requires_tech() -> void:
	var db = _make_db()
	var tile = load("res://src/world/tile.gd").new(0, 0)
	tile.terrain_id = "hills"
	tile.improvement_id = "mine"
	var out_no_tech = TileOutput.compute(tile, db, [])
	var out_with_tech = TileOutput.compute(tile, db, ["mining"])
	assert_true(out_with_tech[IDs.Output.PRODUCTION] >= out_no_tech[IDs.Output.PRODUCTION],
		"Mine production with tech >= without tech")

func test_tile_output_resource_with_tech_and_improvement() -> void:
	var db = _make_db()
	var tile = load("res://src/world/tile.gd").new(0, 0)
	tile.terrain_id = "hills"
	tile.resource_id = "gold"
	tile.improvement_id = "mine"
	var out_no = TileOutput.compute(tile, db, [])
	var out_yes = TileOutput.compute(tile, db, ["mining"])
	assert_gt(out_yes[IDs.Output.COMMERCE], out_no[IDs.Output.COMMERCE],
		"Gold commerce visible only with tech + improvement")

# ── Regions & supply groups ────────────────────────────────────────────────────

func test_regions_single_landmass() -> void:
	var m = _make_map(5, 5, false, false)
	var db = _make_db()
	for tile in m.all_tiles():
		tile.terrain_id = "grassland"
	var regions: Dictionary = Regions.compute_regions(m, db)
	var region_ids := {}
	for k in regions:
		region_ids[regions[k]] = true
	assert_eq(region_ids.size(), 1, "All grassland tiles form one region")

func test_regions_land_sea_separate() -> void:
	var m = _make_map(4, 2, false, false)
	var db = _make_db()
	for x in range(4):
		m.get_tile(x, 0).terrain_id = "grassland"
		m.get_tile(x, 1).terrain_id = "coast"
	var regions: Dictionary = Regions.compute_regions(m, db)
	var region_ids := {}
	for k in regions:
		region_ids[regions[k]] = true
	assert_eq(region_ids.size(), 2, "Land and sea form 2 separate regions")

# ── Influence & ownership ──────────────────────────────────────────────────────

func test_influence_found_claim_sets_owner() -> void:
	var m = _make_map(10, 10, false, false)
	for tile in m.all_tiles():
		tile.terrain_id = "grassland"
	var db = _make_db()
	Influence.found_claim(m, 5, 5, 0, 1, 20)
	var center = m.get_tile(5, 5)
	assert_eq(center.owner_player_id, 0, "Center tile owned after founding")

func test_influence_spread_increases_values() -> void:
	var m = _make_map(10, 10, false, false)
	for tile in m.all_tiles():
		tile.terrain_id = "grassland"
	var db = _make_db()
	var tile = m.get_tile(5, 5)
	var before: int = tile.influence.get(0, 0)
	Influence.spread(m, 5, 5, 10, 2, 0, db)
	var after: int = tile.influence.get(0, 0)
	assert_gt(after, before, "Spreading culture increases influence")

func test_influence_resolve_ownership_max_wins() -> void:
	var m = _make_map(5, 5, false, false)
	for tile in m.all_tiles():
		tile.terrain_id = "grassland"
	var tile = m.get_tile(2, 2)
	tile.influence[0] = 5
	tile.influence[1] = 10
	Influence.resolve_ownership(m)
	assert_eq(tile.owner_player_id, 1, "Player with most influence owns the tile")

# ── Serialization round-trip ───────────────────────────────────────────────────

func test_world_map_serialize_roundtrip() -> void:
	var m = _make_map(8, 6, true, false)
	m.get_tile(3, 2).terrain_id = "hills"
	m.get_tile(3, 2).feature_id = "forest"
	var data: Dictionary = m.serialize()
	var m2 = load("res://src/world/world_map.gd").deserialize(data)
	assert_eq(m2.width, 8, "Width preserved")
	assert_eq(m2.height, 6, "Height preserved")
	assert_eq(m2.get_tile(3, 2).terrain_id, "hills", "Terrain preserved")
	assert_eq(m2.get_tile(3, 2).feature_id, "forest", "Feature preserved")
