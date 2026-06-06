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

# Technology tree selector (§11 tech chooser / tech tree). Lays the tech graph
# out as a tree: columns by era, rows by prereq tier (how deep in the prereq
# chain a tech sits), with each node showing its status, cost, prerequisites and
# what it unlocks. Researchable techs are clickable → Commands.set_research; the
# current research and already-known techs are marked. Click an enabled tech to
# queue it and close.

# Canonical era ordering for the horizontal tree axis.
const ERA_ORDER: Array = [
	"ancient", "classical", "medieval", "renaissance",
	"industrial", "modern", "future"
]

var _facade
var _depth_cache: Dictionary = {}

func init(facade) -> void:
	_facade = facade
	visible = false

func show_screen() -> void:
	visible = true
	rebuild()

func rebuild() -> void:
	for child in get_children():
		child.queue_free()
	yield(get_tree(), "idle_frame")
	if _facade == null or not visible:
		return

	var gs = _facade.get_state()
	var p = gs.get_player(gs.current_player_id)
	if p == null:
		return

	# Opaque backdrop so the map is not visible behind the screen.
	var bg: ColorRect = ColorRect.new()
	bg.anchor_right = 1.0
	bg.anchor_bottom = 1.0
	bg.color = Color(0.10, 0.10, 0.13, 1.0)
	add_child(bg)

	var scroll: ScrollContainer = ScrollContainer.new()
	scroll.anchor_right = 1.0
	scroll.anchor_bottom = 1.0
	add_child(scroll)

	# Eras run left→right as columns; within a column techs stack by prereq tier.
	var hbox: HBoxContainer = HBoxContainer.new()
	hbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hbox.add_constant_override("separation", 18)
	scroll.add_child(hbox)

	var by_era: Dictionary = _techs_by_era()
	var rendered_any: bool = false
	for era in ERA_ORDER:
		if not by_era.has(era):
			continue
		rendered_any = true
		hbox.add_child(_build_era_column(era, by_era[era], p))
	# Any techs with an unrecognised era still get a column so nothing is hidden.
	for era in by_era:
		if era in ERA_ORDER:
			continue
		rendered_any = true
		hbox.add_child(_build_era_column(era, by_era[era], p))

	if not rendered_any:
		var none: Label = Label.new()
		none.text = "(no technologies defined)"
		hbox.add_child(none)

	var close_btn: Button = Button.new()
	close_btn.text = "Cancel"
	close_btn.connect("pressed", self, "_on_close")
	hbox.add_child(close_btn)

# One vertical column of tech nodes for an era, sorted by prereq tier then name.
func _build_era_column(era: String, tech_ids: Array, p) -> VBoxContainer:
	var col: VBoxContainer = VBoxContainer.new()
	col.size_flags_horizontal = Control.SIZE_EXPAND_FILL

	var header: Label = Label.new()
	header.text = "── " + era.capitalize() + " ──"
	col.add_child(header)

	# Sort by tier (prereq depth) then by display name for a stable tree shape.
	var ordered: Array = tech_ids.duplicate()
	ordered.sort_custom(self, "_compare_tech")
	for tech_id in ordered:
		col.add_child(_build_tech_node(tech_id, p))
	return col

func _build_tech_node(tech_id: String, p) -> Button:
	var tech: Dictionary = _facade._db.get_technology(tech_id)
	var known: bool = p.has_tech(tech_id)
	var current: bool = p.current_research_id == tech_id
	var can: bool = load("res://src/sim/research.gd").can_research(tech_id, p, _facade._db)

	var btn: Button = Button.new()
	var disp: String = str(tech.get("name", tech_id))
	var marker: String = ""
	if known:
		marker = " ✓"
	elif current:
		marker = " (researching)"
	elif can:
		marker = ""
	else:
		marker = " (locked)"
	btn.text = _tier_indent(tech_id) + disp + "   [" + str(tech.get("cost", 0)) + "]" + marker
	# Only an unknown, currently-researchable tech is selectable.
	btn.disabled = known or not can
	btn.hint_tooltip = _node_tooltip(tech_id, tech)
	btn.connect("pressed", self, "_on_tech_selected", [tech_id])
	return btn

# A leading indent proportional to the tech's prereq tier, so deeper techs sit
# visibly further into the tree.
func _tier_indent(tech_id: String) -> String:
	var d: int = _tech_depth(tech_id)
	var s: String = ""
	for _i in range(d):
		s += "  "
	return s

func _node_tooltip(tech_id: String, tech: Dictionary) -> String:
	# Prefer the rules layer's widget help; append the tree relationships.
	var lines: Array = []
	var help: String = _facade.widget_help(
		{"type": IDs.WidgetType.TECH_NODE, "tech_id": tech_id})
	if help != "":
		lines.append(help)
	var prereqs: Array = []
	for pr in tech.get("prereqs_all", []):
		prereqs.append(str(pr))
	for pr in tech.get("prereqs_any", []):
		prereqs.append(str(pr) + "?")
	if not prereqs.empty():
		lines.append("Requires: " + PoolStringArray(prereqs).join(", "))
	var unlocks: Array = []
	for u in tech.get("unlocks_units", []):
		unlocks.append(str(u))
	for u in tech.get("unlocks_structures", []):
		unlocks.append(str(u))
	for u in tech.get("unlocks_improvements", []):
		unlocks.append(str(u))
	if not unlocks.empty():
		lines.append("Unlocks: " + PoolStringArray(unlocks).join(", "))
	return PoolStringArray(lines).join("\n")

# ── Tree layout helpers ────────────────────────────────────────────────────────

func _techs_by_era() -> Dictionary:
	var by_era: Dictionary = {}
	for tech_id in _facade._db.technologies:
		var era: String = str(_facade._db.get_technology(tech_id).get("era", "other"))
		if not by_era.has(era):
			by_era[era] = []
		by_era[era].append(tech_id)
	return by_era

# Prereq tier: 0 for a tech with no prerequisites, else one more than the deepest
# prerequisite. Memoised; cycle-safe via an in-progress sentinel.
func _tech_depth(tech_id: String) -> int:
	if _depth_cache.has(tech_id):
		var cached = _depth_cache[tech_id]
		return 0 if cached == null else int(cached)
	_depth_cache[tech_id] = null   # mark in-progress to break any cycle
	var tech: Dictionary = _facade._db.get_technology(tech_id)
	var deepest: int = -1
	for pr in tech.get("prereqs_all", []):
		var d: int = _tech_depth(str(pr))
		if d > deepest:
			deepest = d
	for pr in tech.get("prereqs_any", []):
		var d2: int = _tech_depth(str(pr))
		if d2 > deepest:
			deepest = d2
	var depth: int = deepest + 1
	_depth_cache[tech_id] = depth
	return depth

# Sort comparator: shallower tier first, ties broken by display name.
func _compare_tech(a: String, b: String) -> bool:
	var da: int = _tech_depth(a)
	var db: int = _tech_depth(b)
	if da != db:
		return da < db
	var na: String = str(_facade._db.get_technology(a).get("name", a))
	var nb: String = str(_facade._db.get_technology(b).get("name", b))
	return na < nb

func _on_tech_selected(tech_id: String) -> void:
	var gs = _facade.get_state()
	_facade.apply_command(Commands.set_research(gs.current_player_id, tech_id))
	visible = false

func _on_close() -> void:
	visible = false
