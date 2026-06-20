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

# Per-player fog-of-war overlay. Draws a dark rectangle on tiles the current
# player cannot see. Rebuilt when HotseatManager signals a turn handoff.
#
# Two layers of darkness model "explored memory": a tile the active player has
# *ever* seen stays revealed (remembered terrain, lightly dimmed) even after the
# unit that saw it moves on, and only snaps back to full black if it was never
# seen at all. Currently-visible tiles get no overlay. Live units/cities are
# hidden in remembered-but-not-visible areas (the renderer reads
# get_visible_tiles()), so the player sees the old terrain but not stale unit
# positions — "previous state until vision updates it".

const TILE_SIZE: int = 40
# Fully opaque: never-seen tiles are blacked out completely, with no transparency
# that would let the underlying terrain bleed through.
const FOG_COLOR: Color = Color(0.0, 0.0, 0.0, 1.0)
# Explored-but-not-currently-visible: a translucent veil so the remembered
# terrain reads through, dimmer than live sight.
const REMEMBERED_COLOR: Color = Color(0.0, 0.0, 0.0, 0.55)

var _visible_tiles: Dictionary = {}    # "x,y" → true (current sight this turn)
var _explored_tiles: Dictionary = {}   # "x,y" → true (ever seen by this player)
var _explored_owner: int = -999        # whose memory _explored_tiles holds
var _facade
var _zoom: float = 1.0
var _offset: Vector2 = Vector2.ZERO
# Debug-only: when true, skip all fog rendering (all tiles fully visible).
var fog_disabled: bool = false

func init(facade) -> void:
	_facade = facade

# Debug helper: disable/enable fog rendering globally (session-only, not saved).
func set_fog_disabled(disabled: bool) -> void:
	fog_disabled = disabled
	update()

func is_fog_disabled() -> bool:
	return fog_disabled

func get_visible_tiles() -> Dictionary:
	return _visible_tiles

func get_explored_tiles() -> Dictionary:
	return _explored_tiles

func rebuild(player_id: int) -> void:
	_visible_tiles = {}
	# Explored memory is per player. When the active player changes (hotseat
	# handoff), start their memory fresh rather than leaking the previous
	# player's discoveries.
	if player_id != _explored_owner:
		_explored_tiles = {}
		_explored_owner = player_id
	if _facade == null:
		return
	var gs = _facade.get_state()
	if gs == null or gs.map == null:
		return

	# Single source of truth for current visibility: the facade's authoritative
	# set (unit sight ∪ city sight ∪ owned territory ∪ one-ring fringe), already
	# terrain-aware (sight_bonus + LOS) and map-normalized. We do not recompute
	# sight here, so the fog exactly matches contact detection and the explore
	# mover, and now also lifts over the player's whole cultural territory.
	_visible_tiles = _facade.player_visible_tiles(player_id)

	# Everything in current sight joins the remembered set.
	for key in _visible_tiles:
		_explored_tiles[key] = true

	update()

# Debug helper: mark every tile visible (the '~' console's `reveal` command).
# Not used in normal play; lifts the fog without altering game state.
func reveal_all() -> void:
	if _facade == null:
		return
	var gs = _facade.get_state()
	if gs == null or gs.map == null:
		return
	for y in range(gs.map.height):
		for x in range(gs.map.width):
			var k: String = str(x) + "," + str(y)
			_visible_tiles[k] = true
			_explored_tiles[k] = true
	update()

func sync_camera(zoom: float, offset: Vector2) -> void:
	_zoom = zoom
	_offset = offset
	update()

func _draw() -> void:
	if _facade == null:
		return
	# Debug: fog disabled — skip all overlay rendering so all tiles are visible.
	if fog_disabled:
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
			if _visible_tiles.has(key):
				continue   # in current sight: no overlay
			var screen_pos: Vector2 = Vector2(x * TILE_SIZE, y * TILE_SIZE) * _zoom + _offset
			var rect: Rect2 = Rect2(screen_pos, Vector2(TILE_SIZE, TILE_SIZE) * _zoom)
			# Explored-but-unseen keeps its remembered terrain under a light veil;
			# never-seen tiles stay fully black.
			if _explored_tiles.has(key):
				draw_rect(rect, REMEMBERED_COLOR)
			else:
				draw_rect(rect, FOG_COLOR)
