# Humanish — a turn-based 4X strategy game.
# Copyright (C) 2026 thalia-at-lesbos
# SPDX-License-Identifier: GPL-3.0-or-later
#
# This program is free software: you can redistribute it and/or modify it
# under the terms of the GNU General Public License as published by the Free
# Software Foundation, either version 3 of the License, or (at your option)
# any later version. See the LICENSE file for the full text and warranty
# disclaimer.

extends "res://scenes/screens/info_screen.gd"

# Religion advisor (§3.1 OPEN_RELIGION): founded beliefs, their founders, and how
# many cities follow each — plus an interactive state-religion picker (§8). The
# active player may adopt "None" or any religion present in their own cities;
# switching away from an existing one triggers anarchy (except the first adoption,
# or for a Spiritual leader).

func init(facade) -> void:
	_title = "Religions"
	.init(facade)

func _populate(vbox) -> void:
	var gs = _facade.get_state()
	var p = gs.get_player(gs.current_player_id)

	# ── State religion picker ──────────────────────────────────────────────────
	_add_line(vbox, "State Religion")
	if p != null and p.transition_turns > 0:
		_add_line(vbox, "  Anarchy: %d turn(s) remaining" % p.transition_turns)

	# "None" is always a valid choice.
	_add_choice(vbox, "(none)", "", p)
	# Beliefs present in at least one of the player's own cities are adoptable.
	var adoptable = {}
	if p != null:
		for s in gs.settlements:
			if s.owner_player_id == p.id and s.belief_id != "":
				adoptable[s.belief_id] = true
	var ids = adoptable.keys()
	ids.sort()
	for belief_id in ids:
		_add_choice(vbox, belief_id, belief_id, p)

	# ── Founded-religion overview (read-only) ──────────────────────────────────
	_add_line(vbox, "")
	_add_line(vbox, "Founded Religions")
	if gs.founded_beliefs.empty():
		_add_line(vbox, "  No religions founded yet.")
		return
	for belief_id in gs.founded_beliefs:
		var founder_id = int(gs.founded_beliefs[belief_id])
		var founder = gs.get_player(founder_id)
		var founder_name = founder.name if founder != null else "?"
		var followers = 0
		for s in gs.settlements:
			if s.belief_id == belief_id:
				followers += 1
		_add_line(vbox, "  %s — founded by %s — %d cities" % [belief_id, founder_name, followers])

# One selectable state-religion row. The current choice is marked and disabled.
func _add_choice(vbox, label: String, belief_id: String, p) -> void:
	var is_current = p != null and p.state_religion == belief_id
	var btn = Button.new()
	btn.text = ("► " if is_current else "  ") + label
	btn.disabled = is_current
	btn.connect("pressed", self, "_on_choose", [belief_id])
	vbox.add_child(btn)

func _on_choose(belief_id: String) -> void:
	var gs = _facade.get_state()
	_facade.apply_command(Commands.set_state_religion(gs.current_player_id, belief_id))
	rebuild()
