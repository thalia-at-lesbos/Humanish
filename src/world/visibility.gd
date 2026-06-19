# Humanish — a turn-based 4X strategy game.
# Copyright (C) 2026 thalia-at-lesbos
# SPDX-License-Identifier: GPL-3.0-or-later
#
# This program is free software: you can redistribute it and/or modify it
# under the terms of the GNU General Public License as published by the Free
# Software Foundation, either version 3 of the License, or (at your option)
# any later version. See the LICENSE file for the full text and warranty
# disclaimer.

extends Reference
class_name Visibility

# Shared, pure terrain-aware visibility helper. The single source of truth for
# "what can a sight source at (cx, cy) see" — used by the fog-of-war renderer
# (scenes/world/fog_layer.gd), the diplomatic first-contact scan
# (sim/turn_engine.gd) and the wild-spawn darkness mask (sim/wild_forces.gd), so
# all three agree exactly.
#
# Two terrain rules, both DATA-DRIVEN (no hardcoded terrain/feature ids):
#
#  1. SIGHT BONUS — the effective radius is the caller's base_radius plus the
#     source tile's terrain "sight_bonus" (hills grant +1), so a unit on high
#     ground sees one ring farther.
#
#  2. LINE OF SIGHT — a tile flagged "blocks_sight" on its terrain or its feature
#     (hills/mountain, forest/jungle) hides tiles BEYOND it (farther from the
#     source along the straight line). The source tile and the eight immediately
#     adjacent tiles are always visible; a blocker is itself visible (you see its
#     near face) but occludes whatever it stands in front of.
#
# Everything is integer math. To stay correct under east-west wrap the LOS trace
# runs in LOCAL offset space (dx, dy in [-R, R] relative to the source); only the
# final tile coordinate is normalized to a canonical "x,y" key through the map's
# wrap helper.

# Returns the set of visible tile keys ("x,y", map-normalized) for a sight source
# at (cx, cy) with the given base sight radius.
static func visible_tiles(wmap, db, cx: int, cy: int, base_radius: int) -> Dictionary:
	var seen: Dictionary = {}
	if wmap == null or db == null:
		return seen

	# Sight-bonus: extend the radius by the SOURCE tile's terrain sight_bonus.
	var radius: int = base_radius
	var src: Tile = wmap.get_tile(cx, cy)
	if src != null:
		radius += int(db.get_terrain(src.terrain_id).get("sight_bonus", 0))
	if radius < 0:
		radius = 0

	# Walk every offset in the bounding square; keep those inside the Manhattan
	# radius (matching the historical fog/contact/wild model) that survive the LOS
	# trace. dx/dy are local so wrap never distorts the line geometry.
	for dy in range(-radius, radius + 1):
		for dx in range(-radius, radius + 1):
			if abs(dx) + abs(dy) > radius:
				continue
			if not _line_clear(wmap, db, cx, cy, dx, dy):
				continue
			var nx: int = cx + dx
			var ny: int = cy + dy
			if not wmap.is_valid(nx, ny):
				continue
			var norm: Array = wmap.normalize(nx, ny)
			seen[str(norm[0]) + "," + str(norm[1])] = true
	return seen

# True if the straight line from the source (offset 0,0) to the target offset
# (dx, dy) reaches the target without an intervening blocker. The target itself is
# allowed to be a blocker (you see its near edge); only blockers strictly between
# the source and the target occlude it. The source and the eight adjacent tiles
# (Chebyshev distance <= 1) are always reachable.
static func _line_clear(wmap, db, cx: int, cy: int, dx: int, dy: int) -> bool:
	# Source tile and immediate neighbours: always visible.
	var adx: int = dx if dx >= 0 else -dx
	var ady: int = dy if dy >= 0 else -dy
	if adx <= 1 and ady <= 1:
		return true

	# Integer Bresenham from (0,0) to (dx,dy) in local offset space. Test every
	# step BEFORE the final one: if any is a blocker, the target is occluded.
	var sx: int = 1 if dx > 0 else -1
	var sy: int = 1 if dy > 0 else -1
	var err: int = adx - ady
	var x: int = 0
	var y: int = 0
	# Bounded by the bounding-square diagonal; the target is always reached before
	# the cap, but the explicit bound gives the function a definite return path.
	var steps: int = adx + ady + 1
	for _i in range(steps):
		var e2: int = err + err
		if e2 > -ady:
			err -= ady
			x += sx
		if e2 < adx:
			err += adx
			y += sy
		# Reached the target offset: the trace was clear up to here.
		if x == dx and y == dy:
			return true
		# An intermediate tile that blocks sight occludes everything beyond it.
		if _blocks(wmap, db, cx + x, cy + y):
			return false
	# Unreachable in practice (the target is always hit); treat as visible.
	return true

# True if the tile at (tx, ty) blocks sight via its terrain or feature flag.
static func _blocks(wmap, db, tx: int, ty: int) -> bool:
	var t: Tile = wmap.get_tile(tx, ty)
	if t == null:
		return false
	if bool(db.get_terrain(t.terrain_id).get("blocks_sight", false)):
		return true
	if t.feature_id != "" and bool(db.get_feature(t.feature_id).get("blocks_sight", false)):
		return true
	return false
