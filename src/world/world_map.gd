# Humanish — a turn-based 4X strategy game.
# Copyright (C) 2026 thalia-at-lesbos
# SPDX-License-Identifier: GPL-3.0-or-later
#
# This program is free software: you can redistribute it and/or modify it
# under the terms of the GNU General Public License as published by the Free
# Software Foundation, either version 3 of the License, or (at your option)
# any later version. See the LICENSE file for the full text and warranty
# disclaimer.

class_name WorldMap
extends Reference

# Rectangular grid of Tile objects.
# Wrapping is applied per-axis (typically wrap_x=true, wrap_y=false).

var width: int = 0
var height: int = 0
var wrap_x: bool = true
var wrap_y: bool = false

# tiles[y * width + x] = Tile
var _tiles: Array = []

func init(w: int, h: int, wx: bool = true, wy: bool = false) -> void:
	width = w
	height = h
	wrap_x = wx
	wrap_y = wy
	_tiles.resize(w * h)
	for y in range(h):
		for x in range(w):
			_tiles[y * w + x] = Tile.new(x, y)

# ── Tile access ───────────────────────────────────────────────────────────────

func get_tile(x: int, y: int) -> Tile:
	x = _wrap_x(x)
	y = _wrap_y(y)
	if x < 0 or x >= width or y < 0 or y >= height:
		return null
	return _tiles[y * width + x]

func is_valid(x: int, y: int) -> bool:
	x = _wrap_x(x)
	y = _wrap_y(y)
	return x >= 0 and x < width and y >= 0 and y < height

func all_tiles() -> Array:
	return _tiles

# ── Wrap helpers ──────────────────────────────────────────────────────────────

func _wrap_x(x: int) -> int:
	if wrap_x:
		return ((x % width) + width) % width
	return x

func _wrap_y(y: int) -> int:
	if wrap_y:
		return ((y % height) + height) % height
	return y

# Normalize coordinates (apply wrapping) into canonical form.
func normalize(x: int, y: int) -> Array:
	return [_wrap_x(x), _wrap_y(y)]

# ── Adjacency ─────────────────────────────────────────────────────────────────

# Returns up to 8 neighbouring tiles (cardinal + diagonal).
func neighbours8(x: int, y: int) -> Array:
	var result := []
	for dy in [-1, 0, 1]:
		for dx in [-1, 0, 1]:
			if dx == 0 and dy == 0:
				continue
			var nx: int = x + dx
			var ny: int = y + dy
			if is_valid(nx, ny):
				result.append(get_tile(nx, ny))
	return result

# Returns up to 4 cardinal neighbours (N/E/S/W).
func neighbours4(x: int, y: int) -> Array:
	var result := []
	for delta in [[0, -1], [1, 0], [0, 1], [-1, 0]]:
		var nx: int = x + delta[0]
		var ny: int = y + delta[1]
		if is_valid(nx, ny):
			result.append(get_tile(nx, ny))
	return result

# ── Distance ──────────────────────────────────────────────────────────────────

# Chebyshev (8-directional) distance between two tiles, accounting for wrapping.
func distance(ax: int, ay: int, bx: int, by: int) -> int:
	var dx: int = _axis_dist(ax, bx, width, wrap_x)
	var dy: int = _axis_dist(ay, by, height, wrap_y)
	return dx if dx >= dy else dy

# Manhattan (4-directional) distance with wrapping.
func manhattan(ax: int, ay: int, bx: int, by: int) -> int:
	var dx: int = _axis_dist(ax, bx, width, wrap_x)
	var dy: int = _axis_dist(ay, by, height, wrap_y)
	return dx + dy

func _axis_dist(a: int, b: int, size: int, wrap: bool) -> int:
	var d: int = abs(a - b)
	if wrap:
		d = min(d, size - d)
	return d

# All tiles within Chebyshev radius r of (cx, cy).
func tiles_in_range(cx: int, cy: int, r: int) -> Array:
	var result := []
	for dy in range(-r, r + 1):
		for dx in range(-r, r + 1):
			if abs(dx) <= r and abs(dy) <= r:
				var nx: int = cx + dx
				var ny: int = cy + dy
				if is_valid(nx, ny):
					result.append(get_tile(nx, ny))
	return result

# All tiles at exactly Chebyshev distance r (the ring).
func ring_at_distance(cx: int, cy: int, r: int) -> Array:
	if r == 0:
		return [get_tile(cx, cy)] if is_valid(cx, cy) else []
	var result := []
	for dy in range(-r, r + 1):
		for dx in range(-r, r + 1):
			if max(abs(dx), abs(dy)) == r:
				var nx: int = cx + dx
				var ny: int = cy + dy
				if is_valid(nx, ny):
					result.append(get_tile(nx, ny))
	return result

# ── Serialization ─────────────────────────────────────────────────────────────

func serialize() -> Dictionary:
	var tile_data := []
	for t in _tiles:
		tile_data.append(t.serialize())
	return {
		"width": width, "height": height,
		"wrap_x": wrap_x, "wrap_y": wrap_y,
		"tiles": tile_data
	}

static func deserialize(d: Dictionary):
	var m = load("res://src/world/world_map.gd").new()
	m.width = int(d["width"])
	m.height = int(d["height"])
	m.wrap_x = bool(d.get("wrap_x", true))
	m.wrap_y = bool(d.get("wrap_y", false))
	m._tiles.resize(m.width * m.height)
	for td in d["tiles"]:
		var t = Tile.deserialize(td)
		m._tiles[t.y * m.width + t.x] = t
	return m
