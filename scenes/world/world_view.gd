# Humanish — a turn-based 4X strategy game.
# Copyright (C) 2026 thalia-at-lesbos
# SPDX-License-Identifier: GPL-3.0-or-later
#
# This program is free software: you can redistribute it and/or modify it
# under the terms of the GNU General Public License as published by the Free
# Software Foundation, either version 3 of the License, or (at your option)
# any later version. See the LICENSE file for the full text and warranty
# disclaimer.

extends Node2D

# Flat-color 2D tile renderer. Draws terrain, units, settlements, and overlays
# via Node2D _draw(). Rebuilds only when the WORLD dirty flag is set.
# No references to sim/ — all data comes through SimFacade queries.

const TILE_SIZE: int = 40

# Terrain ID → Color (flat-color palette)
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
# A glaring magenta, deliberately unlike any real terrain, so a tile whose
# terrain_id is missing/unknown reads as an obvious bug instead of being mistaken
# for the (grey) mountain tiles. If you ever see magenta on the map, a terrain id
# is absent from TERRAIN_COLORS or from the data tables.
const DEFAULT_TERRAIN_COLOR: Color = Color(1.0, 0.0, 1.0)
# Landforms that get a peak glyph drawn on top so they are recognisable as
# raised terrain rather than a flat grey square that looks like an artifact.
const PEAK_COLOR: Color = Color(0.30, 0.28, 0.26)
# Rivers are drawn as bright water-blue lines along tile borders.
const RIVER_COLOR: Color = Color(0.30, 0.55, 0.95)

# Resource dot colors keyed by resource type string.
const RESOURCE_COLORS: Dictionary = {
	"strategic": Color(0.4, 0.55, 0.85),  # steel blue
	"luxury":    Color(0.95, 0.80, 0.1),  # amber/gold
	"food":      Color(0.25, 0.85, 0.3),  # bright green
}

# Wild/raider forces (owner id -2) — a deliberate charcoal so they read as
# hostile barbarians rather than rendering glitches.
const WILD_OWNER_ID: int = -2
const WILD_COLOR: Color = Color(0.22, 0.20, 0.24)

# Player colors (indexed by player slot 0–7)
const PLAYER_COLORS: Array = [
	Color(1.0, 0.2, 0.2),   # 0 red
	Color(0.2, 0.4, 1.0),   # 1 blue
	Color(0.2, 0.8, 0.2),   # 2 green
	Color(1.0, 0.8, 0.1),   # 3 yellow
	Color(0.8, 0.2, 0.8),   # 4 purple
	Color(1.0, 0.5, 0.0),   # 5 orange
	Color(0.0, 0.8, 0.8),   # 6 cyan
	Color(0.8, 0.8, 0.8),   # 7 white
]

var _facade                          # SimFacade
var _offset: Vector2 = Vector2.ZERO  # camera pan in pixels
var _zoom: float = 1.0               # camera zoom factor

var _dragging: bool = false
var _drag_last_pos: Vector2 = Vector2.ZERO

# Flash data: tile → flash expiry time (for combat)
var _flash_tiles: Dictionary = {}
# Move-order flash: tile → flash expiry time (for right-click move feedback)
var _move_flash_tiles: Dictionary = {}

func init(facade) -> void:
	_facade = facade
	_facade.connect("combat_resolved", self, "_on_combat_resolved")
	_facade.connect("turn_advanced", self, "_on_turn_advanced")
	_facade.connect("settlement_founded", self, "_on_settlement_founded")
	var fog = get_node_or_null("FogLayer")
	if fog != null and fog.has_method("sync_camera"):
		fog.sync_camera(_zoom, _offset)

func _process(delta: float) -> void:
	if _facade == null:
		return
	# Expire flash tiles
	var now: float = OS.get_ticks_msec() / 1000.0
	var expired: Array = []
	for key in _flash_tiles:
		if now >= _flash_tiles[key]:
			expired.append(key)
	for key in expired:
		_flash_tiles.erase(key)
	# Expire move-order flash tiles
	var move_expired: Array = []
	for key in _move_flash_tiles:
		if now >= _move_flash_tiles[key]:
			move_expired.append(key)
	for key in move_expired:
		_move_flash_tiles.erase(key)
	if not expired.empty() or not move_expired.empty():
		update()

	if _facade.get_dirty().is_dirty(IDs.DirtyRegion.WORLD):
		# Refresh fog for the active player so moving a unit or founding a city
		# reveals the newly-seen tiles (and re-hides ones left behind).
		var fog = get_node_or_null("FogLayer")
		if fog != null and fog.has_method("rebuild"):
			fog.rebuild(_facade.get_state().current_player_id)
		update()
		_facade.get_dirty().clear(IDs.DirtyRegion.WORLD)

func _draw() -> void:
	if _facade == null:
		return
	var gs = _facade.get_state()
	if gs == null or gs.map == null:
		return

	var fog_node = get_node_or_null("FogLayer")
	var visible_tiles: Dictionary = {}
	var explored_tiles: Dictionary = {}
	if fog_node != null:
		visible_tiles = fog_node.get_visible_tiles()
		explored_tiles = fog_node.get_explored_tiles()

	var highlights: Dictionary = _facade.get_tile_highlights()
	var now: float = OS.get_ticks_msec() / 1000.0

	# Draw tiles
	for y in range(gs.map.height):
		for x in range(gs.map.width):
			var tile = gs.map.get_tile(x, y)
			var screen_pos: Vector2 = _tile_to_screen(x, y)
			var rect: Rect2 = Rect2(screen_pos, Vector2(TILE_SIZE, TILE_SIZE) * _zoom)

			# Skip if outside visible area (simple culling)
			if rect.position.x > get_viewport_rect().size.x or rect.end.x < 0:
				continue
			if rect.position.y > get_viewport_rect().size.y or rect.end.y < 0:
				continue

			# Fog: if fog layer active and tile is not visible, skip (FogLayer draws the overlay)
			var tile_key: String = str(x) + "," + str(y)
			var in_fog: bool = not visible_tiles.empty() and not visible_tiles.has(tile_key)
			# A tile the active player has seen at least once is drawn with its
			# remembered detail (territory, rivers); never-seen tiles are not.
			var explored: bool = explored_tiles.empty() or explored_tiles.has(tile_key)

			# Terrain base color
			var terrain_id: String = tile.terrain_id if tile != null else ""
			var color: Color = TERRAIN_COLORS.get(terrain_id, DEFAULT_TERRAIN_COLOR)
			if in_fog:
				color = color.darkened(0.5)
			draw_rect(rect, color)

			# Cultural territory: a thin diagonal hatch in the owner's colour, so
			# borders read at a glance without hiding the terrain underneath. Wild
			# forces (owner -2, e.g. a Raider Camp) get a charcoal hatch too; only a
			# genuinely unowned tile (-1) draws no border.
			if explored and tile != null and tile.owner_player_id != -1 \
					and tile.owner_player_id >= WILD_OWNER_ID:
				_draw_territory_hatch(rect, _player_color(tile.owner_player_id, gs), in_fog)

			# Raised-terrain glyph: a peak so mountains/hills read as terrain
			# (and never as a featureless grey "error" square). Dimmed in fog.
			if terrain_id == "mountain" or terrain_id == "hills":
				_draw_peak(rect, terrain_id == "mountain", in_fog)

			# Rivers run along tile borders — the lines *between* tiles.
			if explored and tile != null:
				_draw_rivers(tile, rect, in_fog)

			# Combat flash
			if _flash_tiles.has(tile_key) and now < _flash_tiles[tile_key]:
				draw_rect(rect, Color(1, 0.1, 0.1, 0.4))

			# Move-order flash: a brief cyan outline fading over 0.4 s
			if _move_flash_tiles.has(tile_key):
				var expiry: float = _move_flash_tiles[tile_key]
				if now < expiry:
					var age: float = 0.4 - (expiry - now)   # 0 → 0.4
					var alpha: float = 1.0 - (age / 0.4)    # 1.0 → 0.0
					var border: Rect2 = rect.grow(-2 * _zoom)
					draw_rect(border, Color(0.2, 1.0, 0.9, alpha), false)
					draw_rect(rect, Color(0.2, 1.0, 0.9, alpha * 0.25))

			# Selection highlight
			if highlights.has(tile_key):
				var border: Rect2 = rect.grow(-2 * _zoom)
				draw_rect(border, Color(1, 1, 1, 0.9), false)

			# Improvement indicator (small dot)
			if tile != null and tile.improvement_id != "":
				var center: Vector2 = rect.position + Vector2(4, 4) * _zoom
				draw_circle(center, 3 * _zoom, Color(0.9, 0.7, 0.1))

			# Resource indicator: a small colored dot in the bottom-right corner,
			# color-coded by type (food/luxury/strategic). Only drawn on explored tiles
			# so fog hides unknown resources the way it would in-universe. Resources
			# with a tech_required are additionally hidden until the active player has
			# researched that technology.
			if tile != null and tile.resource_id != "" and explored:
				var res: Dictionary = _facade._db.get_resource(tile.resource_id)
				var tech_req = res.get("tech_required", null)
				var player = gs.get_player(gs.current_player_id)
				var tech_ok: bool = (tech_req == null or tech_req == "" or tech_req in player.technologies)
				if tech_ok:
					var rtype: String = str(res.get("type", "food"))
					var rcol: Color = RESOURCE_COLORS.get(rtype, Color(0.8, 0.8, 0.8))
					if in_fog:
						rcol = rcol.darkened(0.5)
					var rcenter: Vector2 = rect.position + Vector2(TILE_SIZE - 5, TILE_SIZE - 5) * _zoom
					draw_circle(rcenter, 3 * _zoom, rcol)

	# Draw settlements. A city the player has discovered stays on the map even
	# when it leaves current sight (you remember it is there); cities on
	# never-explored tiles stay hidden under the fog.
	for s in gs.settlements:
		var s_key: String = str(s.x) + "," + str(s.y)
		if not explored_tiles.empty() and not explored_tiles.has(s_key):
			continue
		var screen_pos: Vector2 = _tile_to_screen(s.x, s.y)
		var center: Vector2 = screen_pos + Vector2(TILE_SIZE, TILE_SIZE) * _zoom * 0.5
		var r: float = TILE_SIZE * _zoom * 0.35
		var col: Color = _player_color(s.owner_player_id, gs)
		draw_circle(center, r, col)
		draw_arc(center, r, 0, TAU, 24, Color.black, 1.5)

	# Draw units (on top of settlements). The selected unit is drawn last so it
	# sits on top of the others sharing its tile, and any tile holding more than
	# one unit gets a small count badge so stacks are obvious and cycle-able.
	# Units are only drawn where the player currently has vision: a remembered
	# tile shows its old terrain (via the fog veil) but not stale unit positions.
	var head_uid: int = _facade.get_selection().head_unit()
	var counts: Dictionary = {}   # "x,y" → number of units on that tile
	var selected_unit = null
	for u in gs.units:
		var key: String = str(u.x) + "," + str(u.y)
		if not visible_tiles.empty() and not visible_tiles.has(key):
			continue
		counts[key] = int(counts.get(key, 0)) + 1
		if u.id == head_uid:
			selected_unit = u
		else:
			_draw_unit(u, gs, false)
	if selected_unit != null:
		_draw_unit(selected_unit, gs, true)

	# Stack-size badges sit above the unit markers (drawn once per tile).
	var badged: Dictionary = {}
	for u in gs.units:
		var key2: String = str(u.x) + "," + str(u.y)
		if not counts.has(key2):
			continue
		if int(counts.get(key2, 0)) > 1 and not badged.has(key2):
			badged[key2] = true
			_draw_stack_badge(u.x, u.y, int(counts[key2]))

func _draw_unit(u, gs, is_selected: bool = false) -> void:
	var screen_pos: Vector2 = _tile_to_screen(u.x, u.y)
	var sz: float = TILE_SIZE * _zoom * 0.5
	var unit_rect: Rect2 = Rect2(
		screen_pos + Vector2(TILE_SIZE, TILE_SIZE) * _zoom * 0.25,
		Vector2(sz, sz)
	)
	var col: Color = _player_color(u.owner_player_id, gs)
	draw_rect(unit_rect, col)
	draw_rect(unit_rect, Color.black, false)

	# A bright outline marks which unit in the stack is currently active.
	if is_selected:
		draw_rect(unit_rect.grow(2 * _zoom), Color(1, 1, 0.2, 1.0), false)

	# Health bar
	if u.health < 100:
		var bar_w: float = sz * u.health / 100.0
		var bar_rect: Rect2 = Rect2(unit_rect.position,
			Vector2(bar_w, 3 * _zoom))
		draw_rect(bar_rect, Color.green)

# Draw a peak (a triangle, two peaks for mountains) centred in the tile so raised
# terrain is visually distinct from flat grey. `tall` draws the bigger mountain
# glyph; otherwise the smaller hill bump.
func _draw_peak(rect: Rect2, tall: bool, in_fog: bool) -> void:
	var col: Color = PEAK_COLOR.darkened(0.5) if in_fog else PEAK_COLOR
	var base_y: float = rect.position.y + rect.size.y * (0.78 if tall else 0.72)
	var top_y: float = rect.position.y + rect.size.y * (0.22 if tall else 0.42)
	var cx: float = rect.position.x + rect.size.x * 0.5
	var half: float = rect.size.x * (0.28 if tall else 0.22)
	draw_colored_polygon(PoolVector2Array([
		Vector2(cx - half, base_y),
		Vector2(cx, top_y),
		Vector2(cx + half, base_y),
	]), col)
	if tall:
		# A second, lower peak so a mountain reads as a range, not a single spike.
		var cx2: float = cx + half * 0.9
		var by2: float = base_y
		var ty2: float = rect.position.y + rect.size.y * 0.40
		draw_colored_polygon(PoolVector2Array([
			Vector2(cx2 - half * 0.7, by2),
			Vector2(cx2, ty2),
			Vector2(cx2 + half * 0.7, by2),
		]), col.darkened(0.1))

# Draw a tile's river borders as lines between tiles. A tile only owns its north
# and west edges (its south/east edges belong to the neighbours below/right), so
# iterating every tile and drawing only those two edges paints every river
# segment on the map exactly once.
func _draw_rivers(tile, rect: Rect2, in_fog: bool) -> void:
	var col: Color = RIVER_COLOR.darkened(0.5) if in_fog else RIVER_COLOR
	var width: float = 3.0 * _zoom
	if tile.river_n:
		draw_line(rect.position, rect.position + Vector2(rect.size.x, 0), col, width)
	if tile.river_w:
		draw_line(rect.position, rect.position + Vector2(0, rect.size.y), col, width)

# Fill a tile with a thin, widely-spaced diagonal hatch in the owner's colour to
# mark cultural territory. The hatch phase is keyed to absolute screen position
# (lines of constant x − y), so the strokes line up across neighbouring tiles
# into continuous diagonals instead of breaking at every tile edge.
func _draw_territory_hatch(rect: Rect2, owner_col: Color, in_fog: bool) -> void:
	var col: Color = Color(owner_col.r, owner_col.g, owner_col.b, 0.30 if in_fog else 0.55)
	var spacing: float = 14.0 * _zoom   # wide gaps between strokes
	if spacing < 4.0:
		spacing = 4.0
	var line_w: float = 1.0
	# Diagonals satisfy x - y = c; sweep c across the values that cross this rect.
	var c_min: float = rect.position.x - rect.end.y
	var c_max: float = rect.end.x - rect.position.y
	var k: int = int(ceil(c_min / spacing))
	while k * spacing <= c_max:
		var c: float = k * spacing
		# Clip the line x = c + y to the rect: y ranges over [top, bottom] ∩ where x ∈ [left, right].
		var y1: float = max(rect.position.y, rect.position.x - c)
		var y2: float = min(rect.end.y, rect.end.x - c)
		if y2 > y1:
			draw_line(Vector2(c + y1, y1), Vector2(c + y2, y2), col, line_w)
		k += 1

# A small circular badge in the tile's top-right corner showing how many units
# share the tile, so the player knows there is a stack to click through.
func _draw_stack_badge(tx: int, ty: int, count: int) -> void:
	var screen_pos: Vector2 = _tile_to_screen(tx, ty)
	var center: Vector2 = screen_pos + Vector2(TILE_SIZE - 9, 9) * _zoom
	var r: float = 7 * _zoom
	draw_circle(center, r, Color(0.1, 0.1, 0.1, 0.9))
	draw_arc(center, r, 0, TAU, 16, Color.white, 1.0)
	var font = _get_badge_font()
	if font != null:
		var txt: String = str(count)
		var ts: Vector2 = font.get_string_size(txt)
		draw_string(font, center - ts * 0.5 + Vector2(0, ts.y * 0.35), txt, Color.white)

var _badge_font = null
var _badge_font_loaded: bool = false

func _get_badge_font():
	if not _badge_font_loaded:
		_badge_font_loaded = true
		var ctrl: Control = Control.new()
		add_child(ctrl)
		_badge_font = ctrl.get_font("font")
		ctrl.queue_free()
	return _badge_font

func _player_color(player_id: int, gs) -> Color:
	if player_id == WILD_OWNER_ID:
		return WILD_COLOR
	for i in range(gs.players.size()):
		if gs.players[i].id == player_id:
			return PLAYER_COLORS[i % PLAYER_COLORS.size()]
	return Color(0.6, 0.6, 0.6)

func _tile_to_screen(tx: int, ty: int) -> Vector2:
	return Vector2(tx * TILE_SIZE, ty * TILE_SIZE) * _zoom + _offset

func screen_to_tile(screen_pos: Vector2) -> Vector2:
	var world_pos: Vector2 = (screen_pos - _offset) / _zoom
	return Vector2(int(world_pos.x / TILE_SIZE), int(world_pos.y / TILE_SIZE))

# ── Camera ────────────────────────────────────────────────────────────────────

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		if event.button_index == BUTTON_MIDDLE:
			if event.pressed:
				_dragging = true
				_drag_last_pos = event.position
			else:
				_dragging = false
			get_viewport().set_input_as_handled()
		elif event.button_index == BUTTON_WHEEL_UP and event.pressed:
			_zoom_toward_cursor(min(_zoom * 1.1, 4.0), event.position)
		elif event.button_index == BUTTON_WHEEL_DOWN and event.pressed:
			_zoom_toward_cursor(max(_zoom / 1.1, 0.25), event.position)
	elif event is InputEventMouseMotion and _dragging:
		_offset += event.position - _drag_last_pos
		_drag_last_pos = event.position
		_camera_changed()
	elif event is InputEventKey and event.pressed:
		var step: float = TILE_SIZE * _zoom
		if event.scancode == KEY_LEFT:
			_offset.x += step
			_camera_changed()
		elif event.scancode == KEY_RIGHT:
			_offset.x -= step
			_camera_changed()
		elif event.scancode == KEY_UP:
			_offset.y += step
			_camera_changed()
		elif event.scancode == KEY_DOWN:
			_offset.y -= step
			_camera_changed()

# Zoom to a new level while keeping the world point under `cursor_pos` fixed on
# screen. The invariant is: world_pos = (cursor_pos - offset) / zoom must be the
# same before and after the zoom, so the new offset is derived from that.
func _zoom_toward_cursor(new_zoom: float, cursor_pos: Vector2) -> void:
	var world_pos: Vector2 = (cursor_pos - _offset) / _zoom
	_zoom = new_zoom
	_offset = cursor_pos - world_pos * _zoom
	_camera_changed()

# Shift the camera by a pixel delta (left-button drag-pan from InputRouter).
func pan_by(delta: Vector2) -> void:
	_offset += delta
	_camera_changed()

func pan_to_tile(tx: int, ty: int) -> void:
	var vp: Vector2 = get_viewport_rect().size
	_offset = vp * 0.5 - Vector2(tx * TILE_SIZE, ty * TILE_SIZE) * _zoom
	_camera_changed()

# Center the camera on one of the given player's units, so each turn opens
# looking at something the player owns. Falls back to a settlement if they have
# no units left. Returns true if it found something to center on.
func center_on_player(player_id: int) -> bool:
	if _facade == null:
		return false
	var gs = _facade.get_state()
	if gs == null:
		return false
	for u in gs.units:
		if u.owner_player_id == player_id:
			pan_to_tile(u.x, u.y)
			return true
	for s in gs.settlements:
		if s.owner_player_id == player_id:
			pan_to_tile(s.x, s.y)
			return true
	return false

# Center the camera on the currently-selected unit, if any. Used by the
# idle-unit cycle (auto-advance after an order, and the explicit "next idle
# unit" hotkey) so the view follows the player through their army. Returns true
# if there was a selected unit to center on; false (no camera move) otherwise,
# so callers never pan when the cycle wrapped to nothing.
func center_on_selection() -> bool:
	if _facade == null:
		return false
	var gs = _facade.get_state()
	if gs == null:
		return false
	var head_uid: int = _facade.get_selection().head_unit()
	if head_uid < 0:
		return false
	var u = gs.get_unit(head_uid)
	if u == null:
		return false
	pan_to_tile(u.x, u.y)
	return true

# Redraw the world and keep the fog overlay locked to the same camera, so fog
# stays pinned to the map instead of drifting when the view pans or zooms.
func _camera_changed() -> void:
	update()
	var fog = get_node_or_null("FogLayer")
	if fog != null and fog.has_method("sync_camera"):
		fog.sync_camera(_zoom, _offset)

# Flash the tile at (tx, ty) with a brief cyan outline for ~0.4 s to confirm a
# move order was received (Issue 14). Called by InputRouter after a right-click
# move command is issued.
func flash_move_tile(tx: int, ty: int) -> void:
	var key: String = str(tx) + "," + str(ty)
	_move_flash_tiles[key] = OS.get_ticks_msec() / 1000.0 + 0.4
	update()

# ── Signal handlers ───────────────────────────────────────────────────────────

func _on_combat_resolved(result: Dictionary) -> void:
	# Flash the combatant tiles red for 1 second
	var expiry: float = OS.get_ticks_msec() / 1000.0 + 1.0
	_flash_tiles[str(result.get("ax", 0)) + "," + str(result.get("ay", 0))] = expiry
	_flash_tiles[str(result.get("dx", 0)) + "," + str(result.get("dy", 0))] = expiry
	update()

func _on_turn_advanced(_turn: int) -> void:
	update()

func _on_settlement_founded(_sid: int) -> void:
	update()
