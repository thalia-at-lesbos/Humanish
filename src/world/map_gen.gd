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

# Procedural multi-script map generator.
#
# Pure rules code: integer math only, no Node/scene references, and every random
# draw comes from the shared GameState RNG so generation is fully deterministic
# for a given seed (and survives save/load, since tiles are serialized in full).
#
# A map type is selected by id from data/map_types.json. Generation is split into
# two orthogonal axes that the data table mixes and matches:
#
#   • shape   — how the land/water *mask* is built (where the continents are).
#   • climate — how each land tile is *painted* (which terrains/features appear).
#
# Most shapes drive a shared height-field pipeline: random noise → box-blur into
# blobs → per-shape height bias → percentile threshold to the target land
# fraction. A couple of shapes (tectonics, terra) add structure on top. The
# painter then colours land by latitude/landform bands and sprinkles features.
#
# All terrain/feature ids are data-driven (data/terrains.json, data/features.json)
# and all per-type tunables (land fraction, landform chances, …) live in
# data/map_types.json. The structural shape constants below stay in code because
# they define the *algorithm*, not the balance.

# Rows at each pole that are always deep ocean, regardless of shape.
const POLE_OCEAN_ROWS: int = 2

# Climate band thresholds (latitude%, ~0 at the poles, ~100 at the equator).
const COLD_LAT: int = 22           # below this: cold band (snow/tundra)
const WARM_LAT: int = 70           # above this: warm band (desert/plains)

# Number of box-blur passes is per-type ("smooth"); these bound the height field.
const HEIGHT_MAX: int = 255

# Each box-blur pass collapses the random noise toward its mean, leaving a spread
# far narrower than the per-shape height bias — so the deterministic bias would
# dictate almost the same coastline every seed (continents/pangaea barely moved).
# After blurring we stretch the field's contrast about its mean by this percent so
# the per-seed noise competes with the bias and maps vary visibly seed-to-seed.
# Pure integer math about the integer mean → fully deterministic per seed.
const HEIGHT_CONTRAST_PCT: int = 260

# Per-shape height-bias amplitudes (added to the blurred noise before threshold).
const PANGAEA_AMP: int = 170       # land peaks at the map centre
const CONTINENT_AMP: int = 160     # land peaks mid-band, ocean in the channels
const CONTINENT_VBIAS: int = 60    # gentle mid-latitude land preference
const HEMI_AMP: int = 170          # two horizontal land bands
const ARCH_BIAS: int = 60          # uniform downward push → fragmentation
const MAIN_AMP: int = 200          # the main continent blob
const ISLAND_BIAS: int = 70        # downward push outside the main blob
const INLAND_SEA_AMP: int = 160    # land at the rim, sea at the centre
const LAKES_BIAS: int = 90         # mostly land; lows become small lakes
const TERRA_OLD_AMP: int = 190     # Old World blob
const TERRA_NEW_AMP: int = 200     # New World blob (larger)

# Generate terrain into an already-initialised WorldMap for the given map type.
static func generate(map: WorldMap, db: DataDB, rng: RNG, map_type_id: String = "continents") -> void:
	var w: int = map.width
	var h: int = map.height
	if w <= 0 or h <= 0:
		return

	var spec: Dictionary = _resolve_spec(db, rng, map_type_id)

	var mask: Dictionary = _build_mask(map, rng, spec)
	_paint(map, db, rng, mask, spec)
	_add_coasts(map, db)
	# Rivers run along tile borders and flow to the sea; added after coasts so the
	# water-distance field they trace toward includes the freshly-cut coastline.
	_add_rivers(map, db, rng)
	if spec.has("new_world"):
		_mark_new_world(map, db, rng, spec)

# Resolve the map-type spec, expanding a "shuffle" type into a concrete pick.
static func _resolve_spec(db: DataDB, rng: RNG, map_type_id: String) -> Dictionary:
	var spec: Dictionary = db.get_map_type(map_type_id)
	if str(spec.get("shape", "")) == "shuffle":
		var pool: Array = spec.get("shuffle_pool", ["continents"])
		var pick: String = str(pool[rng.randi_range(0, pool.size() - 1)])
		return db.get_map_type(pick)
	return spec

# ── Land/water mask ────────────────────────────────────────────────────────────

# Build the land mask (and any forced landforms) for the spec's shape.
# Returns { "land": Array<bool>, "mountain": Array<bool>|null, "hills": Array<bool>|null }.
static func _build_mask(map: WorldMap, rng: RNG, spec: Dictionary) -> Dictionary:
	var w: int = map.width
	var h: int = map.height
	var shape: String = str(spec.get("shape", "continents"))

	if shape == "tectonics":
		return _mask_tectonics(w, h, rng, spec)

	var passes: int = int(spec.get("smooth", 3))
	var hf: Array = _height_field(w, h, rng, passes)
	_apply_bias(hf, w, h, shape, spec)

	var land_fraction: int = int(spec.get("land_fraction", 45))
	var land: Array = _threshold(hf, w, h, land_fraction)

	if shape == "continents":
		var third_chance: int = int(spec.get("third_chance", 0))
		if third_chance > 0 and rng.rand_bool_percent(third_chance):
			var bx: int = rng.randi_range(w / 8, w - 1 - w / 8)
			var by: int = rng.randi_range(h / 3, h - 1 - h / 3)
			_stamp_blob(land, w, h, bx, by, (w if w < h else h) / 8)
	elif shape == "terra":
		_carve_terra(land, w, h, spec)

	return {"land": land, "mountain": null, "hills": null}

# Fill a height field with blurred noise: random values smoothed into soft blobs.
static func _height_field(w: int, h: int, rng: RNG, passes: int) -> Array:
	var hf: Array = []
	hf.resize(w * h)
	for i in range(w * h):
		hf[i] = rng.randi_range(0, HEIGHT_MAX)
	for _p in range(passes):
		hf = _box_blur(hf, w, h)
	_stretch_contrast(hf)
	return hf

# Widen the blurred field's spread about its (integer) mean so the per-seed noise
# is comparable to the per-shape height bias. Without this the blur leaves a band
# far narrower than the bias and every seed carves nearly the same coastline.
# Integer math about the integer mean keeps it deterministic per seed.
static func _stretch_contrast(hf: Array) -> void:
	var n: int = hf.size()
	if n == 0:
		return
	var total: int = 0
	for v in hf:
		total += int(v)
	var mean: int = total / n
	for i in range(n):
		var stretched: int = mean + (int(hf[i]) - mean) * HEIGHT_CONTRAST_PCT / 100
		hf[i] = 0 if stretched < 0 else (HEIGHT_MAX if stretched > HEIGHT_MAX else stretched)

# 3×3 average (wrapping on x, clamped on y) — one smoothing pass. No RNG draws.
static func _box_blur(src: Array, w: int, h: int) -> Array:
	var dst: Array = []
	dst.resize(w * h)
	for y in range(h):
		for x in range(w):
			var total: int = 0
			var count: int = 0
			for dy in [-1, 0, 1]:
				var ny: int = y + dy
				if ny < 0 or ny >= h:
					continue
				for dx in [-1, 0, 1]:
					var nx: int = ((x + dx) % w + w) % w
					total += int(src[ny * w + nx])
					count += 1
			dst[y * w + x] = total / count
	return dst

# Add the per-shape height bias in place, so a later threshold carves the shape.
static func _apply_bias(hf: Array, w: int, h: int, shape: String, spec: Dictionary) -> void:
	for y in range(h):
		for x in range(w):
			hf[y * w + x] += _shape_bias(shape, x, y, w, h, spec)

# Height bias for one tile, in roughly [-amp, +amp]. Positive = more likely land.
static func _shape_bias(shape: String, x: int, y: int, w: int, h: int, spec: Dictionary) -> int:
	# Normalised coordinates on a 0..1000 scale and distance from the centre.
	var fx: int = x * 1000 / w
	var fy: int = y * 1000 / h
	var dcx: int = fx - 500 if fx >= 500 else 500 - fx
	var dcy: int = fy - 500 if fy >= 500 else 500 - fy
	var dmax: int = dcx if dcx >= dcy else dcy

	if shape == "fractal":
		return 0
	if shape == "archipelago":
		return -ARCH_BIAS
	if shape == "lakes":
		return LAKES_BIAS
	if shape == "pangaea":
		return PANGAEA_AMP - dmax * PANGAEA_AMP * 2 / 500
	if shape == "inland_sea":
		return -INLAND_SEA_AMP + dmax * INLAND_SEA_AMP * 2 / 500
	if shape == "hemispheres":
		# Two horizontal land bands centred at fy≈250 and fy≈750.
		var d1: int = fy - 250 if fy >= 250 else 250 - fy
		var d2: int = fy - 750 if fy >= 750 else 750 - fy
		var dband: int = d1 if d1 <= d2 else d2
		return HEMI_AMP - dband * HEMI_AMP * 2 / 250
	if shape == "islands_plus_main":
		var radius: int = int(spec.get("main_size", 320))
		if radius <= 0:
			radius = 1
		if dmax < radius:
			return MAIN_AMP * (radius - dmax) / radius
		return -ISLAND_BIAS
	if shape == "terra":
		var old_b: int = _blob_bias(fx, fy, 280, 500, 300, TERRA_OLD_AMP)
		var new_b: int = _blob_bias(fx, fy, 740, 500, 360, TERRA_NEW_AMP)
		return old_b if old_b >= new_b else new_b
	# Default: continents — land mid-band, ocean in the vertical channels.
	var num: int = int(spec.get("num_continents", 2))
	if num <= 0:
		num = 1
	var bandw: int = w / num
	if bandw <= 0:
		bandw = 1
	var local: int = x % bandw
	var edge: int = local if local <= bandw - local else bandw - local
	var bias_x: int = (edge * 2 * 1000 / bandw - 500) * CONTINENT_AMP / 500
	var vbias: int = CONTINENT_VBIAS - dcy * CONTINENT_VBIAS * 2 / 500
	return bias_x + vbias

# Radial blob bias: +amp at (cx,cy), falling to -amp at `radius` (normalised units).
static func _blob_bias(fx: int, fy: int, cx: int, cy: int, radius: int, amp: int) -> int:
	var dx: int = fx - cx if fx >= cx else cx - fx
	var dy: int = fy - cy if fy >= cy else cy - fy
	var d: int = dx if dx >= dy else dy
	if radius <= 0:
		radius = 1
	return amp - d * amp * 2 / radius

# Threshold the height field to a boolean land mask hitting the target land
# fraction. Pole rows are forced to ocean and excluded from the percentile pool.
static func _threshold(hf: Array, w: int, h: int, land_fraction: int) -> Array:
	var vals: Array = []
	for y in range(h):
		if y < POLE_OCEAN_ROWS or y >= h - POLE_OCEAN_ROWS:
			continue
		for x in range(w):
			vals.append(int(hf[y * w + x]))
	var land: Array = []
	land.resize(w * h)
	for i in range(w * h):
		land[i] = false
	if vals.empty():
		return land
	vals.sort()
	# Cut so that `land_fraction`% of the candidate tiles land above the cutoff.
	var water_frac: int = 100 - land_fraction
	var ci: int = vals.size() * water_frac / 100
	if ci < 0:
		ci = 0
	if ci >= vals.size():
		ci = vals.size() - 1
	var cutoff: int = int(vals[ci])
	for y in range(h):
		if y < POLE_OCEAN_ROWS or y >= h - POLE_OCEAN_ROWS:
			continue
		for x in range(w):
			if int(hf[y * w + x]) > cutoff:
				land[y * w + x] = true
	return land

# Paint a filled land blob (radius r, Chebyshev) into the mask.
static func _stamp_blob(land: Array, w: int, h: int, cx: int, cy: int, r: int) -> void:
	for dy in range(-r, r + 1):
		var y: int = cy + dy
		if y < POLE_OCEAN_ROWS or y >= h - POLE_OCEAN_ROWS:
			continue
		for dx in range(-r, r + 1):
			var x: int = ((cx + dx) % w + w) % w
			land[y * w + x] = true

# Force the Old/New World separation for the Terra script: a deep-ocean channel
# down the middle and along the wrap seam, so the two worlds never touch.
static func _carve_terra(land: Array, w: int, h: int, spec: Dictionary) -> void:
	var channel_lo: int = w * 46 / 100
	var channel_hi: int = w * 54 / 100
	for y in range(h):
		for x in range(w):
			if (x >= channel_lo and x <= channel_hi) or x < 2 or x >= w - 2:
				land[y * w + x] = false

# ── Tectonics ───────────────────────────────────────────────────────────────────

# Plate-based mask: scatter plate seeds, assign each tile to its nearest seed
# (wrapping on x), mark seeds land/ocean, and raise mountains/hills where two
# different plates meet — natural ranges along the collision boundaries.
static func _mask_tectonics(w: int, h: int, rng: RNG, spec: Dictionary) -> Dictionary:
	var count: int = int(spec.get("plate_count", 8))
	if count < 2:
		count = 2
	var land_plate_pct: int = int(spec.get("land_plate_pct", 55))

	var seeds: Array = []          # [x, y]
	var seed_is_land: Array = []   # bool per seed
	for _i in range(count):
		seeds.append([rng.randi_range(0, w - 1), rng.randi_range(0, h - 1)])
		seed_is_land.append(rng.rand_bool_percent(land_plate_pct))

	var land: Array = []
	var mountain: Array = []
	var hills: Array = []
	land.resize(w * h)
	mountain.resize(w * h)
	hills.resize(w * h)

	var plate_of: Array = []
	plate_of.resize(w * h)
	for y in range(h):
		for x in range(w):
			var best: int = 0
			var best_d: int = 1 << 30
			var second_d: int = 1 << 30
			for s in range(count):
				var dx: int = abs(x - int(seeds[s][0]))
				dx = dx if dx <= w - dx else w - dx
				var dy: int = abs(y - int(seeds[s][1]))
				var d: int = dx * dx + dy * dy
				if d < best_d:
					second_d = best_d
					best_d = d
					best = s
				elif d < second_d:
					second_d = d
			var idx: int = y * w + x
			plate_of[idx] = best
			var is_pole: bool = y < POLE_OCEAN_ROWS or y >= h - POLE_OCEAN_ROWS
			land[idx] = bool(seed_is_land[best]) and not is_pole
			mountain[idx] = false
			hills[idx] = false

	# Boundary ridges: a land tile touching a different plate becomes mountain;
	# its neighbours become hills (the range's foothills).
	for y in range(h):
		for x in range(w):
			var idx2: int = y * w + x
			if not bool(land[idx2]):
				continue
			var on_boundary: bool = false
			for dy in [-1, 0, 1]:
				var ny: int = y + dy
				if ny < 0 or ny >= h:
					continue
				for dx in [-1, 0, 1]:
					var nx: int = ((x + dx) % w + w) % w
					var nidx: int = ny * w + nx
					if bool(land[nidx]) and int(plate_of[nidx]) != int(plate_of[idx2]):
						on_boundary = true
			if on_boundary:
				mountain[idx2] = true
	for y in range(h):
		for x in range(w):
			var idx3: int = y * w + x
			if not bool(land[idx3]) or bool(mountain[idx3]):
				continue
			for nb in [[0, -1], [1, 0], [0, 1], [-1, 0]]:
				var nx2: int = ((x + nb[0]) % w + w) % w
				var ny2: int = y + nb[1]
				if ny2 < 0 or ny2 >= h:
					continue
				if bool(mountain[ny2 * w + nx2]):
					hills[idx3] = true
					break

	return {"land": land, "mountain": mountain, "hills": hills}

# ── Painting ─────────────────────────────────────────────────────────────────

# Colour every tile: water → ocean, land → landform/climate terrain, then
# sprinkle surface features.
static func _paint(map: WorldMap, db: DataDB, rng: RNG, mask: Dictionary, spec: Dictionary) -> void:
	var w: int = map.width
	var h: int = map.height
	var land: Array = mask["land"]
	var forced_mtn = mask["mountain"]
	var forced_hill = mask["hills"]
	var climate: String = str(spec.get("climate", "latitude"))
	var mtn_chance: int = int(spec.get("mountain_chance", 6))
	var hill_chance: int = int(spec.get("hills_chance", 18))

	for y in range(h):
		var dist_from_pole: int = y if y < (h - 1 - y) else (h - 1 - y)
		for x in range(w):
			var idx: int = y * w + x
			var tile: Tile = map.get_tile(x, y)
			if tile == null:
				continue
			if not bool(land[idx]):
				tile.terrain_id = "ocean"
				continue
			if forced_mtn != null and bool(forced_mtn[idx]):
				tile.terrain_id = "mountain"
				continue
			if forced_hill != null and bool(forced_hill[idx]):
				tile.terrain_id = "hills"
				continue
			# Landform roll overlays climate; keep peaks off the pole-adjacent row.
			var form: int = rng.randi_range(0, 99)
			if form < mtn_chance and dist_from_pole >= POLE_OCEAN_ROWS + 1:
				tile.terrain_id = "mountain"
				continue
			if form < mtn_chance + hill_chance:
				tile.terrain_id = "hills"
				continue
			tile.terrain_id = _flat_terrain(climate, x, y, w, h, dist_from_pole, rng)

	_add_features(map, rng, spec)
	_place_resources(map, db, rng)

# Choose a flat-land terrain for the tile's climate band.
static func _flat_terrain(climate: String, x: int, y: int, w: int, h: int, dist_from_pole: int, rng: RNG) -> String:
	if climate == "oasis":
		# Desert heart, fertile rim — distance from the map centre sets the band.
		var fx: int = x * 1000 / w
		var fy: int = y * 1000 / h
		var dcx: int = fx - 500 if fx >= 500 else 500 - fx
		var dcy: int = fy - 500 if fy >= 500 else 500 - fy
		var dmax: int = dcx if dcx >= dcy else dcy
		if dmax < 300:
			return "desert"
		return "grassland" if rng.rand_bool_percent(55) else "plains"

	# latitude%: ~0 near the climate poles, ~100 at the climate equator.
	var lat_pct: int
	if climate == "tilted":
		# Poles on the left/right edges: latitude runs along x instead of y.
		var dist_from_side: int = x if x < (w - 1 - x) else (w - 1 - x)
		lat_pct = dist_from_side * 200 / w
	else:
		lat_pct = dist_from_pole * 200 / h

	if climate == "plains":
		# Mostly grassland/plains; only the coldest fringes turn to tundra.
		if lat_pct < 12:
			return "tundra"
		return "grassland" if rng.rand_bool_percent(60) else "plains"

	if climate == "ice_age":
		# Cold world: a wide snow/tundra mass, a narrow temperate equatorial band.
		if lat_pct < 70:
			return "snow" if rng.rand_bool_percent(35) else "tundra"
		elif lat_pct < 88:
			return "tundra" if rng.rand_bool_percent(45) else "plains"
		return "grassland" if rng.rand_bool_percent(50) else "plains"

	# Default latitude climate.
	if lat_pct < COLD_LAT:
		return "snow" if rng.rand_bool_percent(40) else "tundra"
	elif lat_pct < WARM_LAT:
		return "grassland" if rng.rand_bool_percent(55) else "plains"
	var warm: int = rng.randi_range(0, 99)
	if warm < 30:
		return "desert"
	elif warm < 65:
		return "plains"
	return "grassland"

# Sprinkle surface features over freshly-painted land: forests in cool/temperate
# bands, jungle in the warm band, oases on the desert tiles of an Oasis map.
static func _add_features(map: WorldMap, rng: RNG, spec: Dictionary) -> void:
	var w: int = map.width
	var h: int = map.height
	var forest_chance: int = int(spec.get("forest_chance", 0))
	var jungle_chance: int = int(spec.get("jungle_chance", 0))
	var oasis_chance: int = int(spec.get("oasis_chance", 0))
	for y in range(h):
		var dist_from_pole: int = y if y < (h - 1 - y) else (h - 1 - y)
		var lat_pct: int = dist_from_pole * 200 / h
		for x in range(w):
			var tile: Tile = map.get_tile(x, y)
			if tile == null:
				continue
			var ter: String = tile.terrain_id
			if ter == "desert":
				if oasis_chance > 0 and rng.rand_bool_percent(oasis_chance):
					tile.feature_id = "oasis"
				continue
			if ter != "grassland" and ter != "plains" and ter != "tundra" and ter != "hills":
				continue
			if lat_pct >= WARM_LAT and ter != "tundra":
				if jungle_chance > 0 and rng.rand_bool_percent(jungle_chance):
					tile.feature_id = "jungle"
			elif ter != "tundra" or lat_pct >= COLD_LAT:
				if forest_chance > 0 and rng.rand_bool_percent(forest_chance):
					tile.feature_id = "forest"

# Scatter resources across the map. Each tile gets at most one resource; for each
# tile we build the list of resources whose allowed_terrains includes that terrain
# and, with a configurable per-tile probability, assign one at random.
static func _place_resources(map: WorldMap, db: DataDB, rng: RNG) -> void:
	var chance: int = db.get_constant("resource_tile_chance", 6)
	if chance <= 0:
		return
	# Index resources by terrain for fast per-tile lookup.
	var by_terrain: Dictionary = {}
	for res_id in db.resources:
		var res: Dictionary = db.resources[res_id]
		for ter in res.get("allowed_terrains", []):
			var key: String = str(ter)
			if not by_terrain.has(key):
				by_terrain[key] = []
			by_terrain[key].append(str(res_id))
	for y in range(map.height):
		for x in range(map.width):
			var tile: Tile = map.get_tile(x, y)
			if tile == null or tile.resource_id != "":
				continue
			var candidates: Array = by_terrain.get(tile.terrain_id, [])
			if candidates.empty():
				continue
			if rng.rand_bool_percent(chance):
				tile.resource_id = str(candidates[rng.randi_range(0, candidates.size() - 1)])

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

# ── Rivers ───────────────────────────────────────────────────────────────────
#
# Rivers are drawn on the lattice of tile *corners* (integer positions 0..width,
# 0..height) and stored as per-tile border flags (Tile.river_n / river_w). Each
# river starts at an interior high point and walks corner-to-corner downhill to
# the sea, where "downhill" is approximated by a multi-source breadth-first
# distance-to-water field. Deterministic for the map's RNG, and serialized with
# the tiles, so save/load and the determinism gate are unaffected.
static func _add_rivers(map: WorldMap, db: DataDB, rng: RNG) -> void:
	var w: int = map.width
	var h: int = map.height
	var water_dist: Array = _water_distance_field(map, db)

	var land_count: int = 0
	for t in map.all_tiles():
		if db.get_terrain(t.terrain_id).get("domain", "land") == "land":
			land_count += 1
	if land_count == 0:
		return

	var per: int = int(db.get_constant("river_land_per_river", 90))
	if per < 1:
		per = 1
	var count: int = land_count / per
	if count < 1:
		count = 1
	var max_len: int = w + h   # generous cap; a river normally stops at the coast

	for _i in range(count):
		_trace_one_river(map, db, rng, water_dist, max_len)

# Breadth-first distance (in tiles, 4-connected) from every water tile. Water
# tiles are 0; land tiles get their hop-count to the nearest sea. Unreachable
# tiles stay at a large sentinel.
static func _water_distance_field(map: WorldMap, db: DataDB) -> Array:
	var w: int = map.width
	var h: int = map.height
	var dist: Array = []
	dist.resize(w * h)
	var frontier: Array = []
	for y in range(h):
		for x in range(w):
			var t: Tile = map.get_tile(x, y)
			var is_water: bool = t != null and db.get_terrain(t.terrain_id).get("domain", "land") != "land"
			if is_water:
				dist[y * w + x] = 0
				frontier.append([x, y])
			else:
				dist[y * w + x] = 1 << 20
	var head: int = 0
	while head < frontier.size():
		var cell: Array = frontier[head]
		head += 1
		var cx: int = cell[0]
		var cy: int = cell[1]
		var d: int = dist[cy * w + cx] + 1
		for delta in [[0, -1], [1, 0], [0, 1], [-1, 0]]:
			var nx: int = cx + delta[0]
			var ny: int = cy + delta[1]
			if nx < 0 or nx >= w or ny < 0 or ny >= h:
				continue
			if d < dist[ny * w + nx]:
				dist[ny * w + nx] = d
				frontier.append([nx, ny])
	return dist

# Distance-to-water of a *corner*: the min over the up-to-four tiles touching it.
static func _corner_water_dist(cx: int, cy: int, water_dist: Array, w: int, h: int) -> int:
	var best: int = 1 << 20
	for off in [[-1, -1], [0, -1], [-1, 0], [0, 0]]:
		var tx: int = cx + off[0]
		var ty: int = cy + off[1]
		if tx < 0 or tx >= w or ty < 0 or ty >= h:
			continue
		var d: int = water_dist[ty * w + tx]
		if d < best:
			best = d
	return best

# Carve a single river: pick an inland source corner (preferring high, dry land)
# and walk to the sea, marking the border segment crossed at each step.
static func _trace_one_river(map: WorldMap, db: DataDB, rng: RNG, water_dist: Array, max_len: int) -> void:
	var w: int = map.width
	var h: int = map.height

	# Source: best of a few random land tiles — far from water, bonus for relief.
	var src_x: int = -1
	var src_y: int = -1
	var src_score: int = -1
	for _k in range(12):
		var rx: int = rng.randi_range(0, w - 1)
		var ry: int = rng.randi_range(0, h - 1)
		var t: Tile = map.get_tile(rx, ry)
		if t == null or db.get_terrain(t.terrain_id).get("domain", "land") != "land":
			continue
		var wd: int = water_dist[ry * w + rx]
		if wd <= 1:
			continue   # already on the coast: no room for a river to run
		var score: int = wd
		if t.terrain_id == "mountain":
			score += 3
		elif t.terrain_id == "hills":
			score += 2
		if score > src_score:
			src_score = score
			src_x = rx
			src_y = ry
	if src_x < 0:
		return

	var cur: Array = [src_x, src_y]   # start at the source tile's top-left corner
	var prev: Array = [-1, -1]
	var visited: Dictionary = {}
	for _step in range(max_len):
		visited[str(cur[0]) + "," + str(cur[1])] = true
		if _corner_water_dist(cur[0], cur[1], water_dist, w, h) == 0:
			break   # reached the sea
		# Candidate corner moves (4-connected on the corner lattice).
		var best_n: Array = []
		var best_d: int = 1 << 20
		var meander: Array = []
		for delta in [[0, -1], [1, 0], [0, 1], [-1, 0]]:
			var nx: int = cur[0] + delta[0]
			var ny: int = cur[1] + delta[1]
			if nx < 0 or nx > w or ny < 0 or ny > h:
				continue
			if nx == prev[0] and ny == prev[1]:
				continue
			if visited.has(str(nx) + "," + str(ny)):
				continue
			var nd: int = _corner_water_dist(nx, ny, water_dist, w, h)
			meander.append([nx, ny, nd])
			if nd < best_d:
				best_d = nd
				best_n = [nx, ny]
		if best_n.empty():
			break   # boxed in; stop here
		# Mostly flow toward the sea, but occasionally meander to a non-increasing
		# neighbour so courses bend instead of running dead straight.
		var nxt: Array = best_n
		if meander.size() > 1 and rng.rand_bool_percent(30):
			var opts: Array = []
			for m in meander:
				if int(m[2]) <= _corner_water_dist(cur[0], cur[1], water_dist, w, h):
					opts.append([m[0], m[1]])
			if not opts.empty():
				nxt = opts[rng.randi_range(0, opts.size() - 1)]
		_mark_river_segment(map, cur, nxt)
		prev = cur
		cur = nxt

# Mark the border segment between two adjacent corners as a river. A horizontal
# segment is a tile's north edge; a vertical segment is a tile's west edge.
static func _mark_river_segment(map: WorldMap, a: Array, b: Array) -> void:
	if a[1] == b[1]:                       # horizontal: a tile's north border
		var cx: int = a[0] if a[0] < b[0] else b[0]
		var t: Tile = map.get_tile(cx, a[1])
		if t != null:
			t.river_n = true
	elif a[0] == b[0]:                     # vertical: a tile's west border
		var cy: int = a[1] if a[1] < b[1] else b[1]
		var t2: Tile = map.get_tile(a[0], cy)
		if t2 != null:
			t2.river_w = true

# Seed undiscovered exploration sites (§9) on the far side of a Terra map's New
# World, so colonising it later pays off. Deterministic for the seed.
static func _mark_new_world(map: WorldMap, db: DataDB, rng: RNG, spec: Dictionary) -> void:
	var nw: Dictionary = spec.get("new_world", {})
	var x_min: int = map.width * int(nw.get("x_min_pct", 55)) / 100
	var chance: int = int(nw.get("discovery_chance", 5))
	for y in range(map.height):
		for x in range(x_min, map.width):
			var tile: Tile = map.get_tile(x, y)
			if tile == null:
				continue
			if db.get_terrain(tile.terrain_id).get("domain", "land") != "land":
				continue
			if rng.rand_bool_percent(chance):
				tile.has_discovery = true

# ── Start positions ─────────────────────────────────────────────────────────────

# Return up to `count` spread-out passable land tiles as [x, y] pairs. Picks the
# tile that maximises the minimum distance to already-chosen starts, so players
# begin far apart. When the map type defines `start_bounds` (e.g. Terra's Old
# World), candidates are confined to that region. Deterministic for a given map.
static func find_start_positions(map: WorldMap, db: DataDB, count: int, map_type_id: String = "") -> Array:
	var bounds: Dictionary = {}
	if map_type_id != "":
		bounds = db.get_map_type(map_type_id).get("start_bounds", {})

	var land: Array = _candidate_land(map, db, bounds)
	# If the bounded region cannot host everyone, fall back to the whole map.
	if land.size() < count:
		land = _candidate_land(map, db, {})
	if land.empty():
		return []

	var starts: Array = []
	# First start: the candidate tile nearest the region's centre.
	var cx: int = map.width / 2
	var cy: int = map.height / 2
	if not bounds.empty():
		cx = (int(bounds.get("x_min_pct", 0)) + int(bounds.get("x_max_pct", 100))) * map.width / 200
		cy = (int(bounds.get("y_min_pct", 0)) + int(bounds.get("y_max_pct", 100))) * map.height / 200
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

# Passable land tiles, optionally clipped to a percentage-bounded region.
static func _candidate_land(map: WorldMap, db: DataDB, bounds: Dictionary) -> Array:
	var x_lo: int = 0
	var x_hi: int = map.width - 1
	var y_lo: int = 0
	var y_hi: int = map.height - 1
	if not bounds.empty():
		x_lo = map.width * int(bounds.get("x_min_pct", 0)) / 100
		x_hi = map.width * int(bounds.get("x_max_pct", 100)) / 100
		y_lo = map.height * int(bounds.get("y_min_pct", 0)) / 100
		y_hi = map.height * int(bounds.get("y_max_pct", 100)) / 100
	var land: Array = []
	for tile in map.all_tiles():
		if tile.x < x_lo or tile.x > x_hi or tile.y < y_lo or tile.y > y_hi:
			continue
		var ter: Dictionary = db.get_terrain(tile.terrain_id)
		if ter.get("domain", "land") == "land" and not ter.get("impassable", false):
			land.append(tile)
	return land

# ── Goody huts (§9) ──────────────────────────────────────────────────────────────

# Scatter goody huts (discovery sites) across passable land, kept clear of the
# players' start tiles so nobody pops a reward on turn one. Count scales with land
# mass (one hut per `goody_hut_land_per_hut` land tiles). Tiles already flagged
# (e.g. a Terra New-World discovery) are left as-is and never double-counted.
# Draws from the shared map RNG, so placement is deterministic for the seed. Run
# after find_start_positions so the start tiles to avoid are known.
static func place_goody_huts(map: WorldMap, db: DataDB, rng: RNG, starts: Array) -> void:
	var per: int = db.get_constant("goody_hut_land_per_hut", 28)
	if per < 1:
		per = 1
	var min_dist: int = db.get_constant("goody_hut_min_distance_from_start", 4)

	var land_count: int = 0
	var candidates: Array = []
	for t in map.all_tiles():
		var ter: Dictionary = db.get_terrain(t.terrain_id)
		if ter.get("domain", "land") != "land" or ter.get("impassable", false):
			continue
		land_count += 1
		if t.has_discovery:
			continue
		var near: bool = false
		for s in starts:
			if map.distance(t.x, t.y, int(s[0]), int(s[1])) < min_dist:
				near = true
				break
		if not near:
			candidates.append(t)

	var target: int = land_count / per
	if target < 1 and land_count > 0:
		target = 1
	if target > candidates.size():
		target = candidates.size()

	# Sample `target` distinct candidates without replacement (swap-remove keeps the
	# draw count predictable for the seed).
	for _i in range(target):
		var pick: int = rng.randi_range(0, candidates.size() - 1)
		candidates[pick].has_discovery = true
		candidates[pick] = candidates[candidates.size() - 1]
		candidates.remove(candidates.size() - 1)

# ── Start fairness (§1) ──────────────────────────────────────────────────────────

# Reference `normalize*` pass: tidy each capital's surroundings so no player is
# crippled by a hostile spawn. It first repositions weak starts onto better
# nearby plots (step 1), then in fixed start order removes adjacent peaks,
# strips bad features/terrain, guarantees fresh water, tops up food bonuses, and
# upgrades poor terrain in the wider radius (step 8); then two global passes run:
# extras for starts still below par (step 9) and strategic-resource equalisation
# (BonusBalancer). Every random choice comes from the shared map RNG in a fixed
# order, so the result is deterministic for the seed. Per-map tunables may
# override the constants via a `normalize` block in data/map_types.json.
# Mutates `starts` in place when step 1 shifts a plot.
static func normalize_starts(map: WorldMap, db: DataDB, rng: RNG, starts: Array, map_type_id: String = "") -> void:
	if starts.empty():
		return
	var spec: Dictionary = db.get_map_type(map_type_id) if map_type_id != "" else {}
	var nz: Dictionary = spec.get("normalize", {})
	var min_food: int = int(nz.get("min_food_bonuses",
		db.get_constant("start_normalize_min_food_bonuses", 1)))
	var balance_r: int = int(nz.get("balance_radius",
		db.get_constant("start_normalize_balance_radius", 2)))
	var tol: int = int(nz.get("resource_tolerance",
		db.get_constant("start_normalize_resource_tolerance", 1)))
	var repos_r: int = int(nz.get("reposition_radius",
		db.get_constant("start_normalize_reposition_radius", 3)))
	var repos_gain: int = int(nz.get("reposition_min_gain",
		db.get_constant("start_normalize_reposition_min_gain", 4)))
	var good_r: int = int(nz.get("good_terrain_radius",
		db.get_constant("start_normalize_good_terrain_radius", 2)))
	var good_quota: int = int(nz.get("good_terrain_quota",
		db.get_constant("start_normalize_good_terrain_quota", 3)))
	var extras_r: int = int(nz.get("extras_radius",
		db.get_constant("start_normalize_extras_radius", 2)))
	var extras_tol: int = int(nz.get("extras_tolerance",
		db.get_constant("start_normalize_extras_tolerance", 6)))

	# Step 1 (`normalizeStartingPlotLocations`): shift weak starts before the
	# per-start tidy steps run. Purely score-driven — no RNG draw.
	_normalize_reposition_starts(map, db, starts, repos_r, repos_gain, spec)

	for s in starts:
		var sx: int = int(s[0])
		var sy: int = int(s[1])
		_normalize_remove_peaks(map, sx, sy)
		_normalize_strip_bad_features(map, sx, sy)
		_normalize_fix_bad_terrain(map, sx, sy)
		_normalize_add_fresh_water(map, db, sx, sy)
		_normalize_add_food_bonuses(map, db, rng, sx, sy, min_food)
		_normalize_add_good_terrain(map, db, rng, sx, sy, good_r, good_quota)

	_normalize_add_extras(map, db, rng, starts, extras_r, extras_tol)
	_balance_start_resources(map, db, rng, starts, balance_r, tol)

# A capital has fresh water if its tile borders a river or an oasis, or any
# neighbour is a water tile (mirrors TurnEngine._has_fresh_water).
static func _start_has_fresh_water(map: WorldMap, db: DataDB, x: int, y: int) -> bool:
	var t: Tile = map.get_tile(x, y)
	if t != null and t.feature_id == "oasis":
		return true
	if map.tile_has_river(x, y):
		return true
	for nb in map.neighbours8(x, y):
		if db.get_terrain(nb.terrain_id).get("domain", "land") != "land":
			return true
	return false

# Fairness score of a prospective capital plot: summed terrain base yields in
# the scoring radius (food weighted `start_normalize_score_food_weight`×), plus
# `start_normalize_score_resource` per resource in reach, plus
# `start_normalize_score_fresh_water` when the plot has fresh water. Pure integer
# arithmetic and no RNG, so the score is deterministic for a map.
static func _start_plot_score(map: WorldMap, db: DataDB, x: int, y: int) -> int:
	var score_r: int = db.get_constant("start_normalize_score_radius", 2)
	var food_w: int = db.get_constant("start_normalize_score_food_weight", 2)
	var res_b: int = db.get_constant("start_normalize_score_resource", 3)
	var fw_b: int = db.get_constant("start_normalize_score_fresh_water", 8)
	var score: int = 0
	for t in map.tiles_in_range(x, y, score_r):
		var out: Dictionary = db.get_terrain(t.terrain_id).get("base_output", {})
		score += int(out.get("food", 0)) * food_w
		score += int(out.get("production", 0))
		score += int(out.get("commerce", 0))
		if t.resource_id != "":
			score += res_b
	if _start_has_fresh_water(map, db, x, y):
		score += fw_b
	return score

# Step 1 `normalizeStartingPlotLocations`: score each start plot and shift it to
# the best-scoring passable land tile within `radius` when that beats the current
# plot by at least `min_gain`. A candidate must keep the layout's existing
# minimum pairwise start spacing (measured against the other starts' current
# positions) and stay inside any per-map `start_bounds`, so repositioning never
# packs players closer than find_start_positions laid them out. Fully
# deterministic — fixed start order, strict-improvement scan-order tie-break, no
# RNG draw. Mutates `starts` in place.
static func _normalize_reposition_starts(map: WorldMap, db: DataDB, starts: Array, radius: int, min_gain: int, spec: Dictionary) -> void:
	if radius <= 0 or starts.empty():
		return
	# The layout's spacing floor: no shift may bring two starts closer than the
	# closest original pair sits.
	var floor_d: int = 1 << 30
	for i in range(starts.size()):
		for j in range(i + 1, starts.size()):
			var d: int = map.distance(int(starts[i][0]), int(starts[i][1]),
				int(starts[j][0]), int(starts[j][1]))
			if d < floor_d:
				floor_d = d
	var bounds: Dictionary = spec.get("start_bounds", {})
	var x_lo: int = 0
	var x_hi: int = map.width - 1
	var y_lo: int = 0
	var y_hi: int = map.height - 1
	if not bounds.empty():
		x_lo = map.width * int(bounds.get("x_min_pct", 0)) / 100
		x_hi = map.width * int(bounds.get("x_max_pct", 100)) / 100
		y_lo = map.height * int(bounds.get("y_min_pct", 0)) / 100
		y_hi = map.height * int(bounds.get("y_max_pct", 100)) / 100
	for i in range(starts.size()):
		var sx: int = int(starts[i][0])
		var sy: int = int(starts[i][1])
		var best_x: int = sx
		var best_y: int = sy
		# A shift must clear the current plot's score by at least min_gain.
		var best_score: int = _start_plot_score(map, db, sx, sy) + min_gain
		for t in map.tiles_in_range(sx, sy, radius):
			if t.x == sx and t.y == sy:
				continue
			if t.x < x_lo or t.x > x_hi or t.y < y_lo or t.y > y_hi:
				continue
			var ter: Dictionary = db.get_terrain(t.terrain_id)
			if ter.get("domain", "land") != "land" or ter.get("impassable", false):
				continue
			var clear: bool = true
			for j in range(starts.size()):
				if j == i:
					continue
				if map.distance(t.x, t.y, int(starts[j][0]), int(starts[j][1])) < floor_d:
					clear = false
					break
			if not clear:
				continue
			var sc: int = _start_plot_score(map, db, t.x, t.y)
			if sc > best_score:
				best_score = sc
				best_x = t.x
				best_y = t.y
		starts[i] = [best_x, best_y]

# Turn any peak on the start tile or its inner ring into hills (the city tile is
# already passable, so this only affects neighbours).
static func _normalize_remove_peaks(map: WorldMap, sx: int, sy: int) -> void:
	for t in map.tiles_in_range(sx, sy, 1):
		if t.terrain_id == "mountain":
			t.terrain_id = "hills"

# Strip jungle (the only food-negative feature) from the start tile and ring.
static func _normalize_strip_bad_features(map: WorldMap, sx: int, sy: int) -> void:
	for t in map.tiles_in_range(sx, sy, 1):
		if t.feature_id == "jungle":
			t.feature_id = ""

# Upgrade poor terrain: the city tile itself becomes grassland if it is snow or
# desert; ring snow becomes tundra and ring desert becomes plains.
static func _normalize_fix_bad_terrain(map: WorldMap, sx: int, sy: int) -> void:
	var c: Tile = map.get_tile(sx, sy)
	if c != null and (c.terrain_id == "snow" or c.terrain_id == "desert"):
		c.terrain_id = "grassland"
	for t in map.tiles_in_range(sx, sy, 1):
		if t.x == sx and t.y == sy:
			continue
		if t.terrain_id == "snow":
			t.terrain_id = "tundra"
		elif t.terrain_id == "desert":
			t.terrain_id = "plains"

# One-step terrain upgrades toward grass/plains for step 8. Part of the rule
# (like _normalize_fix_bad_terrain's fixed ids), not tunable balance.
const GOOD_TERRAIN_UPGRADE := {"snow": "tundra", "tundra": "grassland", "desert": "plains"}

# Step 8 `normalizeAddGoodTerrain`: upgrade up to `quota` poor flat tiles in the
# wider start radius — beyond the inner ring _normalize_fix_bad_terrain already
# handles — one step toward grass/plains (snow→tundra, tundra→grassland,
# desert→plains), so a tundra/desert-ringed capital gains workable ground. Tiles
# carrying a resource are left alone so resource/terrain pairings stay valid.
# Picks draw from the shared map RNG (swap-remove), deterministic for the seed.
static func _normalize_add_good_terrain(map: WorldMap, db: DataDB, rng: RNG, sx: int, sy: int, radius: int, quota: int) -> void:
	if radius < 2 or quota <= 0:
		return
	var candidates: Array = []
	for t in map.tiles_in_range(sx, sy, radius):
		if map.distance(t.x, t.y, sx, sy) <= 1:
			continue  # start tile + inner ring are step 6's job
		if t.resource_id != "":
			continue
		if GOOD_TERRAIN_UPGRADE.has(t.terrain_id):
			candidates.append(t)
	var left: int = quota
	while left > 0 and not candidates.empty():
		var pick: int = rng.randi_range(0, candidates.size() - 1)
		var tile: Tile = candidates[pick]
		tile.terrain_id = str(GOOD_TERRAIN_UPGRADE[tile.terrain_id])
		left -= 1
		candidates[pick] = candidates[candidates.size() - 1]
		candidates.remove(candidates.size() - 1)

# Guarantee fresh water by carving a short river on the start tile's borders when
# it has none nearby.
static func _normalize_add_fresh_water(map: WorldMap, db: DataDB, sx: int, sy: int) -> void:
	if _start_has_fresh_water(map, db, sx, sy):
		return
	var t: Tile = map.get_tile(sx, sy)
	if t != null:
		t.river_n = true
		t.river_w = true

# Ensure at least `min_food` food resources sit in the start's inner ring, adding
# them on suitable empty tiles (deterministic via the map RNG).
static func _normalize_add_food_bonuses(map: WorldMap, db: DataDB, rng: RNG, sx: int, sy: int, min_food: int) -> void:
	if min_food <= 0:
		return
	var by_ter: Dictionary = _resources_by_terrain(db, "food")
	var have: int = 0
	var slots: Array = []
	for t in map.tiles_in_range(sx, sy, 1):
		if t.resource_id != "":
			if str(db.get_resource(t.resource_id).get("type", "")) == "food":
				have += 1
			continue
		if by_ter.has(t.terrain_id):
			slots.append(t)
	while have < min_food and not slots.empty():
		var pick: int = rng.randi_range(0, slots.size() - 1)
		var tile: Tile = slots[pick]
		var opts: Array = by_ter[tile.terrain_id]
		tile.resource_id = str(opts[rng.randi_range(0, opts.size() - 1)])
		have += 1
		slots[pick] = slots[slots.size() - 1]
		slots.remove(slots.size() - 1)

# Step 9 `normalizeAddExtras`: the final fairness pass for starts still below
# par after the earlier steps. Every start is scored with the step-1 scorer; any
# start more than `tol` points below the richest is topped up with extra food and
# luxury resources on suitable empty tiles within `radius` (strategic access
# stays the BonusBalancer's domain), and a start *still* below par afterwards is
# compensated with up to `start_normalize_extras_huts` extra discovery sites
# nearby (within `start_normalize_extras_hut_radius`, but kept
# `goody_hut_min_distance_from_start` clear of every start so nobody pops one on
# turn one). All picks draw from the shared map RNG in fixed start order.
static func _normalize_add_extras(map: WorldMap, db: DataDB, rng: RNG, starts: Array, radius: int, tol: int) -> void:
	if starts.size() < 2:
		return
	var res_b: int = db.get_constant("start_normalize_score_resource", 3)
	if res_b < 1:
		res_b = 1
	var scores: Array = []
	var par: int = -(1 << 30)
	for s in starts:
		var sc: int = _start_plot_score(map, db, int(s[0]), int(s[1]))
		scores.append(sc)
		if sc > par:
			par = sc
	var floor_s: int = par - tol
	var by_ter: Dictionary = _extras_by_terrain(db)
	var hut_quota: int = db.get_constant("start_normalize_extras_huts", 1)
	var hut_min: int = db.get_constant("goody_hut_min_distance_from_start", 4)
	var hut_max: int = db.get_constant("start_normalize_extras_hut_radius", 6)
	for i in range(starts.size()):
		if scores[i] >= floor_s:
			continue
		var sx: int = int(starts[i][0])
		var sy: int = int(starts[i][1])
		# Extra resources on suitable empty tiles until the start reaches par.
		var slots: Array = []
		for t in map.tiles_in_range(sx, sy, radius):
			if t.resource_id == "" and by_ter.has(t.terrain_id):
				slots.append(t)
		while scores[i] < floor_s and not slots.empty():
			var pick: int = rng.randi_range(0, slots.size() - 1)
			var tile: Tile = slots[pick]
			var opts: Array = by_ter[tile.terrain_id]
			tile.resource_id = str(opts[rng.randi_range(0, opts.size() - 1)])
			scores[i] += res_b
			slots[pick] = slots[slots.size() - 1]
			slots.remove(slots.size() - 1)
		if scores[i] >= floor_s:
			continue
		# Still short after the resource top-up: scatter extra discovery sites.
		var hut_slots: Array = []
		for t in map.tiles_in_range(sx, sy, hut_max):
			if t.has_discovery:
				continue
			var ter: Dictionary = db.get_terrain(t.terrain_id)
			if ter.get("domain", "land") != "land" or ter.get("impassable", false):
				continue
			var near: bool = false
			for s2 in starts:
				if map.distance(t.x, t.y, int(s2[0]), int(s2[1])) < hut_min:
					near = true
					break
			if not near:
				hut_slots.append(t)
		var huts_left: int = hut_quota
		while huts_left > 0 and not hut_slots.empty():
			var hp: int = rng.randi_range(0, hut_slots.size() - 1)
			hut_slots[hp].has_discovery = true
			huts_left -= 1
			hut_slots[hp] = hut_slots[hut_slots.size() - 1]
			hut_slots.remove(hut_slots.size() - 1)

# Food + luxury resources indexed by allowed terrain, for the step-9 extras pass
# (strategic access is equalised separately by _balance_start_resources).
static func _extras_by_terrain(db: DataDB) -> Dictionary:
	var merged: Dictionary = _resources_by_terrain(db, "food")
	var lux: Dictionary = _resources_by_terrain(db, "luxury")
	for k in lux:
		if not merged.has(k):
			merged[k] = []
		for rid in lux[k]:
			merged[k].append(rid)
	return merged

# Equalise strategic-resource access: no start may sit more than `tol` strategic
# resources below the richest start (within Chebyshev `radius`). Poorer starts get
# strategic resources added on suitable empty tiles until they reach the floor.
static func _balance_start_resources(map: WorldMap, db: DataDB, rng: RNG, starts: Array, radius: int, tol: int) -> void:
	var counts: Array = []
	var max_c: int = 0
	for s in starts:
		var c: int = _count_resources_of_type(map, db, int(s[0]), int(s[1]), radius, "strategic")
		counts.append(c)
		if c > max_c:
			max_c = c
	var floor_c: int = max_c - tol
	if floor_c < 0:
		floor_c = 0
	var by_ter: Dictionary = _resources_by_terrain(db, "strategic")
	for i in range(starts.size()):
		if counts[i] >= floor_c:
			continue
		var sx: int = int(starts[i][0])
		var sy: int = int(starts[i][1])
		var slots: Array = []
		for t in map.tiles_in_range(sx, sy, radius):
			if t.resource_id == "" and by_ter.has(t.terrain_id):
				slots.append(t)
		while counts[i] < floor_c and not slots.empty():
			var pick: int = rng.randi_range(0, slots.size() - 1)
			var tile: Tile = slots[pick]
			var opts: Array = by_ter[tile.terrain_id]
			tile.resource_id = str(opts[rng.randi_range(0, opts.size() - 1)])
			counts[i] += 1
			slots[pick] = slots[slots.size() - 1]
			slots.remove(slots.size() - 1)

# Count resources of a given table `type` within Chebyshev `radius` of (cx, cy).
static func _count_resources_of_type(map: WorldMap, db: DataDB, cx: int, cy: int, radius: int, kind: String) -> int:
	var n: int = 0
	for t in map.tiles_in_range(cx, cy, radius):
		if t.resource_id != "" and str(db.get_resource(t.resource_id).get("type", "")) == kind:
			n += 1
	return n

# Index resources of a given table `type` by each allowed terrain id, for fast
# per-tile placement lookups.
static func _resources_by_terrain(db: DataDB, kind: String) -> Dictionary:
	var by_ter: Dictionary = {}
	for rid in db.resources:
		var r: Dictionary = db.resources[rid]
		if str(r.get("type", "")) != kind:
			continue
		for ter in r.get("allowed_terrains", []):
			var k: String = str(ter)
			if not by_ter.has(k):
				by_ter[k] = []
			by_ter[k].append(str(rid))
	return by_ter
