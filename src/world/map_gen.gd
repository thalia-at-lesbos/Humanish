# Humanish — a turn-based 4X strategy game.
# Copyright (C) 2026 thalia-at-lesbos
# SPDX-License-Identifier: GPL-3.0-or-later
#
# This program is free software: you can redistribute it and/or modify it
# under the terms of the GNU General Public License as published by the Free
# Software Foundation, either version 3 of the License, or (at your option)
# any later version. See the LICENSE file for the full text and warranty
# disclaimer.

class_name MapGen

# Procedural sample-map generator.
#
# Pure rules code: integer math only, no Node/scene references, and every random
# draw comes from the shared GameState RNG so generation is fully deterministic
# for a given seed (and survives save/load, since tiles are serialized in full).
#
# The output is intentionally simple but varied: a mostly-contiguous landmass
# with ocean poles, scattered seas, latitude-based climate bands (snow/tundra →
# grassland/plains → desert), sprinkled hills and mountains, and a coast ring
# wherever ocean meets land. All terrain ids are data-driven (data/terrains.json).

# Percent chances / band thresholds — kept here as named constants so the shape
# of the map is easy to retune without touching the algorithm.
const POLE_OCEAN_ROWS: int = 2     # rows at each pole that are always ocean
const SEA_CHANCE: int = 8          # % of inland tiles that become scattered sea
const MOUNTAIN_CHANCE: int = 6     # % of land tiles that become mountain
const HILLS_CHANCE: int = 18       # % of land tiles that become hills
const COLD_LAT: int = 22           # latitude% below which climate is cold
const WARM_LAT: int = 70           # latitude% above which climate is warm

# Generate terrain into an already-initialised WorldMap.
static func generate(map: WorldMap, db: DataDB, rng: RNG) -> void:
	var w: int = map.width
	var h: int = map.height
	if w <= 0 or h <= 0:
		return

	for y in range(h):
		# Distance to the nearest pole row (0 at the very edge, larger inland).
		var dist_from_pole: int = y if y < (h - 1 - y) else (h - 1 - y)
		for x in range(w):
			var tile: Tile = map.get_tile(x, y)
			if tile == null:
				continue
			tile.terrain_id = _pick_terrain(dist_from_pole, h, rng)

	_add_coasts(map, db)

# Choose a terrain id for one tile from its latitude and the RNG.
static func _pick_terrain(dist_from_pole: int, h: int, rng: RNG) -> String:
	if dist_from_pole < POLE_OCEAN_ROWS:
		return "ocean"

	# latitude%: ~0 near the poles, ~100 at the equator (integer scaled).
	var lat_pct: int = dist_from_pole * 200 / h

	# Scattered inland seas to break up the coastline.
	if rng.rand_bool_percent(SEA_CHANCE):
		return "ocean"

	# Landform: mountains and hills overlay any climate.
	var form: int = rng.randi_range(0, 99)
	if form < MOUNTAIN_CHANCE and dist_from_pole >= POLE_OCEAN_ROWS + 1:
		return "mountain"
	if form < MOUNTAIN_CHANCE + HILLS_CHANCE:
		return "hills"

	# Flat land coloured by climate band.
	if lat_pct < COLD_LAT:
		return "snow" if rng.rand_bool_percent(40) else "tundra"
	elif lat_pct < WARM_LAT:
		return "grassland" if rng.rand_bool_percent(55) else "plains"
	else:
		var warm: int = rng.randi_range(0, 99)
		if warm < 30:
			return "desert"
		elif warm < 65:
			return "plains"
		return "grassland"

# Convert every ocean tile that touches land into coast (shallow water).
static func _add_coasts(map: WorldMap, db: DataDB) -> void:
	var coastal: Array = []
	for y in range(map.height):
		for x in range(map.width):
			var tile: Tile = map.get_tile(x, y)
			if tile == null or tile.terrain_id != "ocean":
				continue
			for nb in map.neighbours8(x, y):
				if db.get_terrain(nb.terrain_id).get("domain", "land") == "land":
					coastal.append(tile)
					break
	for t in coastal:
		t.terrain_id = "coast"

# ── Start positions (used when placing each player's opening units) ────────────

# Return up to `count` spread-out passable land tiles as [x, y] pairs. Picks the
# tile that maximises the minimum distance to already-chosen starts, so players
# begin far apart. Deterministic for a given map.
static func find_start_positions(map: WorldMap, db: DataDB, count: int) -> Array:
	var land: Array = []
	for tile in map.all_tiles():
		var ter: Dictionary = db.get_terrain(tile.terrain_id)
		if ter.get("domain", "land") == "land" and not ter.get("impassable", false):
			land.append(tile)
	if land.empty():
		return []

	var starts: Array = []
	# First start: the land tile nearest the map centre.
	var cx: int = map.width / 2
	var cy: int = map.height / 2
	var best: Tile = land[0]
	var best_d: int = 1 << 30
	for tile in land:
		var d: int = map.distance(tile.x, tile.y, cx, cy)
		if d < best_d:
			best_d = d
			best = tile
	starts.append([best.x, best.y])

	# Remaining starts: greedily maximise distance from existing starts.
	while starts.size() < count:
		var pick: Tile = null
		var pick_score: int = -1
		for tile in land:
			var nearest: int = 1 << 30
			for s in starts:
				var dd: int = map.distance(tile.x, tile.y, int(s[0]), int(s[1]))
				if dd < nearest:
					nearest = dd
			if nearest > pick_score:
				pick_score = nearest
				pick = tile
		if pick == null:
			break
		starts.append([pick.x, pick.y])

	return starts
