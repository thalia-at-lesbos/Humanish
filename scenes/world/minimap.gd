# Humanish — a turn-based 4X strategy game.
# Copyright (C) 2026 thalia-at-lesbos
# SPDX-License-Identifier: GPL-3.0-or-later
#
# This program is free software: you can redistribute it and/or modify it
# under the terms of the GNU General Public License as published by the Free
# Software Foundation, either version 3 of the License, or (at your option)
# any later version. See the LICENSE file for the full text and warranty
# disclaimer.

extends TextureRect

# Thumbnail raster minimap. One pixel per tile, click to pan WorldView.
# Rebuilt each turn from current game state via SimFacade.

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
const PLAYER_COLORS: Array = [
	Color(1.0, 0.2, 0.2), Color(0.2, 0.4, 1.0), Color(0.2, 0.8, 0.2),
	Color(1.0, 0.8, 0.1), Color(0.8, 0.2, 0.8), Color(1.0, 0.5, 0.0),
]

var _facade
var _world_view

func init(facade, world_view) -> void:
	_facade = facade
	_world_view = world_view
	rebuild()

func rebuild() -> void:
	if _facade == null:
		return
	var gs = _facade.get_state()
	if gs == null or gs.map == null:
		return

	var w: int = gs.map.width
	var h: int = gs.map.height
	var img: Image = Image.new()
	img.create(w, h, false, Image.FORMAT_RGB8)
	img.lock()

	# Build settlement ownership lookup for fast coloring
	var city_tiles: Dictionary = {}
	for s in gs.settlements:
		city_tiles[str(s.x) + "," + str(s.y)] = s.owner_player_id

	for y in range(h):
		for x in range(w):
			var tile = gs.map.get_tile(x, y)
			var color: Color
			var key: String = str(x) + "," + str(y)
			if city_tiles.has(key):
				color = _player_color(city_tiles[key], gs)
			elif tile != null and tile.owner_player_id >= 0:
				color = _player_color(tile.owner_player_id, gs).lightened(0.3)
			else:
				var terrain_id: String = tile.terrain_id if tile != null else ""
				color = TERRAIN_COLORS.get(terrain_id, Color(0.3, 0.3, 0.3))
			img.set_pixel(x, y, color)

	img.unlock()
	var tex: ImageTexture = ImageTexture.new()
	tex.create_from_image(img, 0)
	texture = tex

func _player_color(player_id: int, gs) -> Color:
	for i in range(gs.players.size()):
		if gs.players[i].id == player_id:
			return PLAYER_COLORS[i % PLAYER_COLORS.size()]
	return Color(0.6, 0.6, 0.6)

func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.button_index == BUTTON_LEFT and event.pressed:
		if _world_view == null or _facade == null:
			return
		var gs = _facade.get_state()
		if gs == null or gs.map == null:
			return
		var local_pos: Vector2 = event.position
		var ratio_x: float = local_pos.x / rect_size.x
		var ratio_y: float = local_pos.y / rect_size.y
		var tx: int = int(ratio_x * gs.map.width)
		var ty: int = int(ratio_y * gs.map.height)
		_world_view.pan_to_tile(tx, ty)
