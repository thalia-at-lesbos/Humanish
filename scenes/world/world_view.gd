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
	"mountain":  Color(0.5, 0.5, 0.5),
}
const DEFAULT_TERRAIN_COLOR: Color = Color(0.3, 0.3, 0.3)

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

# Flash data: tile → flash expiry time (for combat)
var _flash_tiles: Dictionary = {}

func init(facade) -> void:
	_facade = facade
	_facade.connect("combat_resolved", self, "_on_combat_resolved")
	_facade.connect("turn_advanced", self, "_on_turn_advanced")
	_facade.connect("settlement_founded", self, "_on_settlement_founded")

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
	if not expired.empty():
		update()

	if _facade.get_dirty().is_dirty(IDs.DirtyRegion.WORLD):
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
	if fog_node != null:
		visible_tiles = fog_node.get_visible_tiles()

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

			# Terrain base color
			var terrain_id: String = tile.terrain_id if tile != null else ""
			var color: Color = TERRAIN_COLORS.get(terrain_id, DEFAULT_TERRAIN_COLOR)
			if in_fog:
				color = color.darkened(0.5)
			draw_rect(rect, color)

			# Combat flash
			if _flash_tiles.has(tile_key) and now < _flash_tiles[tile_key]:
				draw_rect(rect, Color(1, 0.1, 0.1, 0.4))

			# Selection highlight
			if highlights.has(tile_key):
				var border: Rect2 = rect.grow(-2 * _zoom)
				draw_rect(border, Color(1, 1, 1, 0.9), false)

			# Improvement indicator (small dot)
			if tile != null and tile.improvement_id != "":
				var center: Vector2 = rect.position + Vector2(4, 4) * _zoom
				draw_circle(center, 3 * _zoom, Color(0.9, 0.7, 0.1))

	# Draw settlements
	for s in gs.settlements:
		var screen_pos: Vector2 = _tile_to_screen(s.x, s.y)
		var center: Vector2 = screen_pos + Vector2(TILE_SIZE, TILE_SIZE) * _zoom * 0.5
		var r: float = TILE_SIZE * _zoom * 0.35
		var col: Color = _player_color(s.owner_player_id, gs)
		draw_circle(center, r, col)
		draw_arc(center, r, 0, TAU, 24, Color.black, 1.5)

	# Draw units (on top of settlements)
	for u in gs.units:
		_draw_unit(u, gs)

func _draw_unit(u, gs) -> void:
	var screen_pos: Vector2 = _tile_to_screen(u.x, u.y)
	var sz: float = TILE_SIZE * _zoom * 0.5
	var unit_rect: Rect2 = Rect2(
		screen_pos + Vector2(TILE_SIZE, TILE_SIZE) * _zoom * 0.25,
		Vector2(sz, sz)
	)
	var col: Color = _player_color(u.owner_player_id, gs)
	draw_rect(unit_rect, col)
	draw_rect(unit_rect, Color.black, false)

	# Health bar
	if u.health < 100:
		var bar_w: float = sz * u.health / 100.0
		var bar_rect: Rect2 = Rect2(unit_rect.position,
			Vector2(bar_w, 3 * _zoom))
		draw_rect(bar_rect, Color.green)

func _player_color(player_id: int, gs) -> Color:
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
		if event.button_index == BUTTON_WHEEL_UP and event.pressed:
			_zoom = min(_zoom * 1.1, 4.0)
			update()
		elif event.button_index == BUTTON_WHEEL_DOWN and event.pressed:
			_zoom = max(_zoom / 1.1, 0.25)
			update()
	elif event is InputEventKey and event.pressed:
		var step: float = TILE_SIZE * _zoom
		if event.scancode == KEY_LEFT:
			_offset.x += step
			update()
		elif event.scancode == KEY_RIGHT:
			_offset.x -= step
			update()
		elif event.scancode == KEY_UP:
			_offset.y += step
			update()
		elif event.scancode == KEY_DOWN:
			_offset.y -= step
			update()

func pan_to_tile(tx: int, ty: int) -> void:
	var vp: Vector2 = get_viewport_rect().size
	_offset = vp * 0.5 - Vector2(tx * TILE_SIZE, ty * TILE_SIZE) * _zoom
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
