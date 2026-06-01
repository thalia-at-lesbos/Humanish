extends Node2D

# Per-player fog-of-war overlay. Draws a dark rectangle on tiles the current
# player cannot see. Rebuilt when HotseatManager signals a turn handoff.

const TILE_SIZE: int = 40
const FOG_COLOR: Color = Color(0.0, 0.0, 0.0, 0.75)

var _visible_tiles: Dictionary = {}   # "x,y" → true
var _facade
var _zoom: float = 1.0
var _offset: Vector2 = Vector2.ZERO

func init(facade) -> void:
	_facade = facade

func get_visible_tiles() -> Dictionary:
	return _visible_tiles

func rebuild(player_id: int) -> void:
	_visible_tiles = {}
	if _facade == null:
		return
	var gs = _facade.get_state()
	if gs == null or gs.map == null:
		return

	var sight_unit: int = gs.db.get_constant("unit_sight", 2)
	var sight_city: int = gs.db.get_constant("city_sight", 3)

	for u in gs.units:
		if u.owner_player_id == player_id:
			_add_visible_range(u.x, u.y, sight_unit, gs.map)

	for s in gs.settlements:
		if s.owner_player_id == player_id:
			_add_visible_range(s.x, s.y, sight_city, gs.map)

	update()

func _add_visible_range(cx: int, cy: int, radius: int, wmap) -> void:
	for dy in range(-radius, radius + 1):
		for dx in range(-radius, radius + 1):
			if abs(dx) + abs(dy) <= radius:
				var tx: int = cx + dx
				var ty: int = cy + dy
				if wmap.is_valid(tx, ty):
					_visible_tiles[str(tx) + "," + str(ty)] = true

func sync_camera(zoom: float, offset: Vector2) -> void:
	_zoom = zoom
	_offset = offset
	update()

func _draw() -> void:
	if _facade == null:
		return
	var gs = _facade.get_state()
	if gs == null or gs.map == null:
		return

	# If no fog data yet (e.g., before first rebuild), show everything
	if _visible_tiles.empty():
		return

	for y in range(gs.map.height):
		for x in range(gs.map.width):
			var key: String = str(x) + "," + str(y)
			if not _visible_tiles.has(key):
				var screen_pos: Vector2 = Vector2(x * TILE_SIZE, y * TILE_SIZE) * _zoom + _offset
				var rect: Rect2 = Rect2(screen_pos, Vector2(TILE_SIZE, TILE_SIZE) * _zoom)
				draw_rect(rect, FOG_COLOR)
