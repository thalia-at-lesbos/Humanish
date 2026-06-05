# Humanish — a turn-based 4X strategy game.
# Copyright (C) 2026 thalia-at-lesbos
# SPDX-License-Identifier: GPL-3.0-or-later
#
# This program is free software: you can redistribute it and/or modify it
# under the terms of the GNU General Public License as published by the Free
# Software Foundation, either version 3 of the License, or (at your option)
# any later version. See the LICENSE file for the full text and warranty
# disclaimer.

extends CanvasLayer

# HUD dispatcher: watches dirty flags each frame and drives per-panel rebuilds.
# Each panel is a child node that exposes a rebuild() method.

var _facade

func init(facade) -> void:
	_facade = facade

func _process(_delta: float) -> void:
	if _facade == null:
		return
	var d = _facade.get_dirty()

	if d.is_dirty(IDs.DirtyRegion.HUD_GROUPS):
		_rebuild_node("SelectionPanel")
		_rebuild_node("SliderPanel")
		_rebuild_node("ResearchBar")
		_rebuild_node("EndTurnButton")
		d.clear(IDs.DirtyRegion.HUD_GROUPS)

	if d.is_dirty(IDs.DirtyRegion.DATA_PANES):
		_rebuild_node("MessageLog")
		_rebuild_node("TurnScoreBar")
		d.clear(IDs.DirtyRegion.DATA_PANES)

func _rebuild_node(name: String) -> void:
	# The HUD panels live under the VBox container, not directly under the HUD.
	var node = get_node_or_null("VBox/" + name)
	if node != null and node.has_method("rebuild"):
		node.rebuild()
