# Humanish — a turn-based 4X strategy game.
# Copyright (C) 2026 thalia-at-lesbos
# SPDX-License-Identifier: GPL-3.0-or-later
#
# This program is free software: you can redistribute it and/or modify it
# under the terms of the GNU General Public License as published by the Free
# Software Foundation, either version 3 of the License, or (at your option)
# any later version. See the LICENSE file for the full text and warranty
# disclaimer.

class_name GlobalWarming

# §11 Environmental degradation — global warming.
#
# A map-wide degradation pass run once per world step. Building-driven
# unhealthiness and detonated nukes raise a global "warming value" (GW_VALUE)
# that yields a number of degradation *strikes* each turn; forest/jungle cover
# defends against them. Every landed strike degrades one random non-city land
# tile a single step toward the base terrain (gw_base_terrain, desert),
# stripping any vegetation feature first. Pure static; draws only from gs.rng.
#
# The closed-form per-turn strike probability (see docs/design/game-rules.md §11)
#   PROB = 1 - ((100 - gw_chance)/100 + #FOREST/#LAND * gw_forest_ratio/100) ^ GW_VALUE
# is the probability of at least one strike across GW_VALUE Bernoulli trials,
# each landing with chance  p = gw_chance - (#FOREST/#LAND * gw_forest_ratio).
# We run that trial process directly — same distribution, pure integer math —
# instead of evaluating the fractional-exponent closed form.

# Per-world-step entry point. Consumes RNG draws in a fixed order:
# the fractional-attempt roll (if any), then one landing roll per attempt,
# then a target pick per landed strike.
static func tick(game_state, rng: RNG) -> void:
	var db: DataDB = game_state.db
	# p — the per-strike landing chance (integer percent), reduced by forest cover.
	var per_strike_chance: int = _strike_chance(game_state, db)
	if per_strike_chance <= 0:
		return
	# GW_VALUE — the number of strike attempts this turn (see _strike_attempts).
	var attempts: int = _strike_attempts(game_state, rng, db)
	if attempts <= 0:
		return
	var candidates: Array = _candidate_tiles(game_state, db)
	if candidates.empty():
		return
	for _i in range(attempts):
		if not rng.rand_bool_percent(per_strike_chance):
			continue
		var tile: Tile = candidates[rng.randi_range(0, candidates.size() - 1)]
		_degrade_tile(game_state, tile, db)

# GW_VALUE = #BAD_HEALTH/#PLOTS * gw_global_unhealth_ratio
#            + #NUKES_EXPLODED * gw_nuclear_ratio/100
# Computed ×100 to keep its fractional part under integer math, then split into a
# whole count of attempts plus a single fractional attempt resolved by an RNG roll.
static func _strike_attempts(game_state, rng: RNG, db: DataDB) -> int:
	var plots: int = game_state.map.width * game_state.map.height
	if plots <= 0:
		return 0
	var bad_health: int = _building_unhealth(game_state, db)
	var unhealth_ratio: int = db.get_constant("gw_global_unhealth_ratio", 20)
	var nuclear_ratio: int = db.get_constant("gw_nuclear_ratio", 50)
	var value_x100: int = bad_health * unhealth_ratio * 100 / plots \
		+ game_state.nukes_exploded * nuclear_ratio
	var attempts: int = value_x100 / 100
	var frac: int = value_x100 % 100
	if frac > 0 and rng.rand_bool_percent(frac):
		attempts += 1
	return attempts

# p (integer percent) = gw_chance - GW_DEFENSE, where the forest/jungle defence
# GW_DEFENSE = #FOREST/#LAND * gw_forest_ratio. Clamped to [0, 100].
static func _strike_chance(game_state, db: DataDB) -> int:
	var land: int = 0
	var forest: int = 0
	for tile in game_state.map.all_tiles():
		if db.get_terrain(tile.terrain_id).get("domain", "land") != "land":
			continue
		land += 1
		if tile.feature_id != "" \
				and int(db.get_feature(tile.feature_id).get("growth_probability", 0)) > 0:
			forest += 1
	if land <= 0:
		return 0
	var gw_chance: int = db.get_constant("gw_chance", 20)
	var forest_ratio: int = db.get_constant("gw_forest_ratio", 50)
	var defense: int = forest * forest_ratio / land
	var chance: int = gw_chance - defense
	return chance if chance > 0 else 0

# #BAD_HEALTH — the global unhealthiness caused by *buildings* only (the summed
# structure health_penalty across every settlement). Unhealthiness from
# population, features, or other sources is excluded by design (§11).
static func _building_unhealth(game_state, db: DataDB) -> int:
	var total: int = 0
	for s in game_state.settlements:
		var owner = game_state.get_player(s.owner_player_id)
		for struct_id in s.structures:
			# An obsolete structure's health effects — its pollution included —
			# have stopped (§15.17), so it no longer warms the globe either.
			if owner != null and owner.structure_obsolete(db, struct_id):
				continue
			total += int(db.get_structure(struct_id).get("health_penalty", 0))
	return total

# Land tiles that do not host a settlement — strikes never target a city tile.
static func _candidate_tiles(game_state, db: DataDB) -> Array:
	var out: Array = []
	for tile in game_state.map.all_tiles():
		if db.get_terrain(tile.terrain_id).get("domain", "land") != "land":
			continue
		if game_state.get_settlement_at(tile.x, tile.y) != null:
			continue
		out.append(tile)
	return out

# Degrade one step toward gw_base_terrain: strip a vegetation feature first, then
# shift terrain one rung along its data-driven `degrades_to` chain. Any land
# terrain participates (the chains converge on the base, e.g. mountain → hills →
# plains → desert); a tile already at the base — or any terrain without a
# `degrades_to` successor — falls straight to the base, so the pass always
# terminates. A tile already at the base with no feature is a no-op.
static func _degrade_tile(game_state, tile: Tile, db: DataDB) -> void:
	if tile.feature_id != "":
		# Strip vegetation feature first.
		tile.feature_id = ""
		return
	var base: String = db.get_constant_str("gw_base_terrain", "desert")
	if tile.terrain_id == base:
		return
	# Step one rung along the terrain's degrade chain; terrains with no declared
	# successor collapse directly to the base terrain.
	tile.terrain_id = str(db.get_terrain(tile.terrain_id).get("degrades_to", base))
