# Humanish — a turn-based 4X strategy game.
# Copyright (C) 2026 thalia-at-lesbos
# SPDX-License-Identifier: GPL-3.0-or-later
#
# This program is free software: you can redistribute it and/or modify it
# under the terms of the GNU General Public License as published by the Free
# Software Foundation, either version 3 of the License, or (at your option)
# any later version. See the LICENSE file for the full text and warranty
# disclaimer.

extends Control

# Minimap overlay (§3.1): a small, always-visible overview of the entire map
# drawn in the lower-right corner of the HUD. Each tile is one pixel (or a
# small rectangle) colored by terrain type. Only explored (ever-seen) tiles for
# the current player are rendered — unexplored tiles stay black, respecting
# fog-of-war. Visible (currently-in-sight) tiles are shown at full brightness;
# explored-but-not-currently-visible tiles are dimmed.
#
# The minimap is a pure presentation layer: it reads state via facade.get_state()
# and the FogLayer node; it never mutates sim state.

# Terrain colors mirror those used in WorldView (same flat-color palette).
const TERRAIN_COLORS: Dictionary = {
	"grassland": Color(0.4, 0.7, 0.3),
	"plains":    Color(0.8, 0.8, 0.4),
	"desert":    Color(0.9, 0.8, 0.5),
	"tundra":    Color(0.6, 0.7, 0.65),
	"snow":      Color(0.95, 0.95, 1.0),
	"coast":     Color(0.4, 0.6, 0.9),
	"ocean":     Color(0.2, 0.35, 0.7),
	"hills":     Color(0.55, 0.45, 0.3),
	"mountain":  Color(0.46, 0.44, 0.42),
}
const DEFAULT_COLOR: Color = Color(0.3, 0.3, 0.3)
# Fog colors: fully-unexplored is black; explored-but-not-visible is slightly
# lighter so the player can still read old memory, just dimmer than live sight.
const UNEXPLORED_COLOR: Color = Color(0.0, 0.0, 0.0)
const EXPLORED_DIM: float = 0.45   # darkened() factor for remembered tiles

# Fixed pixel size used for each tile on the minimap.
const CELL: int = 3

# Minimap panel dimensions (computed from the map at init time).
const PANEL_PADDING: int = 4
const MIN_SIZE: int = 80

var _facade
var _fog_layer    # FogLayer node; may be null (fog disabled or not wired yet)
var _world_view   # WorldView node; may be null until wired by main.gd

# Whether the minimap is currently shown (default: true).
var _enabled: bool = true

func init(facade, fog_layer) -> void:
	_facade = facade
	_fog_layer = fog_layer
	# STOP (not IGNORE) so clicks register on the minimap for click-to-recenter.
	mouse_filter = Control.MOUSE_FILTER_STOP
	# Listen to facade signals that change what the minimap shows.
	if _facade != null:
		_facade.connect("turn_advanced", self, "_on_state_changed")
		_facade.connect("player_turn_started", self, "_on_state_changed")
		_facade.connect("settlement_founded", self, "_on_state_changed")
		_facade.connect("unit_created", self, "_on_state_changed")

func set_fog_layer(fog_layer) -> void:
	_fog_layer = fog_layer

# Wire the WorldView node so a click on the minimap can recenter the main view.
func set_world_view(world_view) -> void:
	_world_view = world_view

func set_enabled(en: bool) -> void:
	_enabled = en
	visible = en
	update()

func is_enabled() -> bool:
	return _enabled

# Called from hud.gd when the WORLD dirty region is cleared, or directly from
# main.gd after a fog rebuild, so the minimap stays in sync with the main view.
func refresh() -> void:
	update()

func _on_state_changed(_arg = null) -> void:
	# Defer by one frame so the hotseat manager / WorldView has time to rebuild
	# the fog layer before we read it.
	call_deferred("update")

func _draw() -> void:
	if not _enabled or _facade == null:
		return
	var gs = _facade.get_state()
	if gs == null or gs.map == null:
		return

	var map_w: int = gs.map.width
	var map_h: int = gs.map.height
	if map_w <= 0 or map_h <= 0:
		return

	var panel_w: int = map_w * CELL + PANEL_PADDING * 2
	var panel_h: int = map_h * CELL + PANEL_PADDING * 2

	# Dark panel background.
	draw_rect(Rect2(Vector2.ZERO, Vector2(panel_w, panel_h)),
		Color(0.05, 0.05, 0.07, 0.88))
	# Thin border.
	draw_rect(Rect2(Vector2.ZERO, Vector2(panel_w, panel_h)),
		Color(0.5, 0.5, 0.55, 0.8), false)

	var visible_tiles: Dictionary = {}
	var explored_tiles: Dictionary = {}
	if _fog_layer != null:
		visible_tiles = _fog_layer.get_visible_tiles()
		explored_tiles = _fog_layer.get_explored_tiles()

	for y in range(map_h):
		for x in range(map_w):
			var key: String = str(x) + "," + str(y)
			var in_visible: bool = visible_tiles.has(key)
			var in_explored: bool = explored_tiles.has(key)

			var color: Color
			if not visible_tiles.empty() and not in_visible and not in_explored:
				# Never-seen tile: fully black.
				color = UNEXPLORED_COLOR
			else:
				var tile = gs.map.get_tile(x, y)
				var terrain_id: String = tile.terrain_id if tile != null else ""
				color = TERRAIN_COLORS.get(terrain_id, DEFAULT_COLOR)
				# Explored-but-not-currently-visible: dim to show as memory.
				if not visible_tiles.empty() and not in_visible:
					color = color.darkened(EXPLORED_DIM)

			var px: float = PANEL_PADDING + x * CELL
			var py: float = PANEL_PADDING + y * CELL
			draw_rect(Rect2(px, py, CELL, CELL), color)

	# Draw settlement dots (always colored by owner, shown in explored area).
	for s in gs.settlements:
		var s_key: String = str(s.x) + "," + str(s.y)
		if not visible_tiles.empty() and not explored_tiles.has(s_key):
			continue
		var px: float = PANEL_PADDING + s.x * CELL + CELL * 0.5
		var py: float = PANEL_PADDING + s.y * CELL + CELL * 0.5
		var dot_color: Color = _player_color(s.owner_player_id, gs)
		draw_circle(Vector2(px, py), CELL * 0.9, dot_color)

# Player color palette (mirrors WorldView.PLAYER_COLORS).
const PLAYER_COLORS: Array = [
	Color(1.0, 0.2, 0.2),
	Color(0.2, 0.4, 1.0),
	Color(0.2, 0.8, 0.2),
	Color(1.0, 0.8, 0.1),
	Color(0.8, 0.2, 0.8),
	Color(1.0, 0.5, 0.0),
	Color(0.0, 0.8, 0.8),
	Color(0.8, 0.8, 0.8),
]

func _player_color(player_id: int, gs) -> Color:
	for i in range(gs.players.size()):
		if gs.players[i].id == player_id:
			return PLAYER_COLORS[i % PLAYER_COLORS.size()]
	return Color(0.6, 0.6, 0.6)

# Pure inverse of _draw()'s tile->pixel mapping (px = PANEL_PADDING + x * CELL),
# clamped to map bounds. Returns [tx, ty]. Kept pure (no tree access) so the
# click->tile math is unit-testable without a live scene.
static func pixel_to_tile(px: float, py: float, map_w: int, map_h: int) -> Array:
	var tx: int = int((px - PANEL_PADDING) / CELL)
	var ty: int = int((py - PANEL_PADDING) / CELL)
	tx = 0 if tx < 0 else (map_w - 1 if tx > map_w - 1 else tx)
	ty = 0 if ty < 0 else (map_h - 1 if ty > map_h - 1 else ty)
	return [tx, ty]

# Click (or drag) on the minimap recenters the main WorldView on that tile.
func _gui_input(event: InputEvent) -> void:
	if not _enabled or _world_view == null or _facade == null:
		return
	var is_press: bool = event is InputEventMouseButton \
		and event.button_index == BUTTON_LEFT and event.pressed
	var is_drag: bool = event is InputEventMouseMotion \
		and (event.button_mask & BUTTON_MASK_LEFT) != 0
	if not is_press and not is_drag:
		return
	var gs = _facade.get_state()
	if gs == null or gs.map == null:
		return
	var map_w: int = gs.map.width
	var map_h: int = gs.map.height
	if map_w <= 0 or map_h <= 0:
		return
	var tile: Array = pixel_to_tile(event.position.x, event.position.y, map_w, map_h)
	_world_view.pan_to_tile(tile[0], tile[1])
