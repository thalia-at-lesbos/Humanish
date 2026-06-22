# Humanish — a turn-based 4X strategy game.
# Copyright (C) 2026 thalia-at-lesbos
# SPDX-License-Identifier: GPL-3.0-or-later
#
# This program is free software: you can redistribute it and/or modify it
# under the terms of the GNU General Public License as published by the Free
# Software Foundation, either version 3 of the License, or (at your option)
# any later version. See the LICENSE file for the full text and warranty
# disclaimer.

extends Node

# Manages pass-and-play hotseat flow. Subscribes to facade.player_turn_started
# to show the PassDeviceScreen and rebuild fog for the incoming player.

var _facade
var _world_view
var _pass_screen    # PassDeviceScreen node

func init(facade, world_view) -> void:
	_facade = facade
	_world_view = world_view
	_facade.connect("player_turn_started", self, "_on_player_turn_started")
	_facade.connect("game_won", self, "_on_game_won")

func set_pass_screen(screen) -> void:
	_pass_screen = screen

# Drive the opening player's turn. player_turn_started only fires on a turn
# *transition*, never for the very first player, so the opener is not announced.
# If that opener is an AI, nothing would ever set it in motion and the game would
# hang forever waiting on a player that never acts — so kick its turn off here.
# A human opener needs nothing (main centers the map for them); the pass-device
# overlay, if any, opens for the next human via _on_player_turn_started.
func begin() -> void:
	if _facade == null:
		return
	var gs = _facade.get_state()
	var p = gs.get_player(gs.current_player_id)
	if p != null and p.is_ai:
		call_deferred("_run_ai_turn", gs.current_player_id)

func _on_player_turn_started(player_id: int) -> void:
	if _facade == null:
		return
	var gs = _facade.get_state()
	var p = gs.get_player(player_id)
	var player_name: String = p.name if p != null else "Player"

	# Computer players take their whole turn automatically. Defer it so the command
	# that started this turn finishes unwinding first; the AI's end-turn then fires
	# player_turn_started again for whoever is next (chaining through further AI
	# players until a human's turn opens the pass-device screen below).
	if p != null and p.is_ai:
		call_deferred("_run_ai_turn", player_id)
		return

	# Rebuild fog for the new active player and center the map on one of their
	# units so the turn opens looking at something they own.
	if _world_view != null:
		var fog = _world_view.get_node_or_null("FogLayer")
		if fog != null:
			fog.rebuild(player_id)
		# Open the turn on a unit that still needs orders (issue 5): a worker that
		# just finished an improvement, or any freshly-idle unit, is selected and
		# centred rather than landing on whatever owned unit happens to be first.
		if _world_view.has_method("center_on_idle_or_player"):
			_world_view.center_on_idle_or_player(player_id)
		elif _world_view.has_method("center_on_player"):
			_world_view.center_on_player(player_id)

	# Show the pass-device overlay — but only in a true hotseat with two or more
	# humans. With a single human (vs. AI opponents, or solo) there is no one to
	# pass the device to, so the "Pass the device to <name>" prompt is just an
	# extra click between every AI round; skip it and let the human play directly.
	if _pass_screen != null and _pass_screen.has_method("show_for_player") \
			and _human_player_count() > 1:
		_pass_screen.show_for_player(player_name, player_id)

# How many human (non-AI) players are in the game.
func _human_player_count() -> int:
	if _facade == null:
		return 0
	var n: int = 0
	for p in _facade.get_state().players:
		if not p.is_ai:
			n += 1
	return n

func _run_ai_turn(player_id: int) -> void:
	if _facade == null:
		return
	var gs = _facade.get_state()
	# Bail if the game ended or the turn moved on while this deferred call waited.
	if gs.winning_alliance_id >= 0 or gs.current_player_id != player_id:
		return
	PlayerAI.take_turn(_facade, player_id)

func _on_game_won(alliance_id: int) -> void:
	if _pass_screen != null and _pass_screen.has_method("show_game_over"):
		_pass_screen.show_game_over(alliance_id, _facade.get_state())
