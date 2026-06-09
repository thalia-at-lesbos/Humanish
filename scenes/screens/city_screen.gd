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

# Full-screen city view: outputs, the F/R/C/I commerce split, wellbeing and
# contentment, the worked tiles (resources used), current production with
# progress, a quick build chooser, and the building list.
# Opened via OPEN_CITY_SCREEN (selection panel / flyout "Open City").

# Emitted when the screen is closed, so a turn-start prompt chain can move on to
# the next idle city (or finish).
signal closed

var _facade
var _city_id: int = -1

func init(facade) -> void:
	_facade = facade
	visible = false

func show_city(city_id: int) -> void:
	if city_id < 0:
		return
	_city_id = city_id
	visible = true
	rebuild()

func rebuild() -> void:
	for child in get_children():
		child.queue_free()
	yield(get_tree(), "idle_frame")
	if _facade == null or _city_id < 0 or not visible:
		return
	_build()

func _build() -> void:
	var gs = _facade.get_state()
	var db = _facade._db
	var s = gs.get_settlement(_city_id)
	if s == null:
		return
	var owner = gs.get_player(s.owner_player_id)
	var techs = owner.technologies if owner != null else []

	# Opaque backdrop so the map is not visible behind the screen.
	var bg := ColorRect.new()
	bg.anchor_right = 1.0
	bg.anchor_bottom = 1.0
	bg.color = Color(0.10, 0.10, 0.13, 1.0)
	add_child(bg)

	var scroll := ScrollContainer.new()
	scroll.anchor_right = 1.0
	scroll.anchor_bottom = 1.0
	scroll.margin_left = 14
	scroll.margin_top = 14
	scroll.margin_right = -14
	scroll.margin_bottom = -14
	add_child(scroll)

	var v := VBoxContainer.new()
	v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(v)

	_title(v, s.name + "   (pop " + str(s.population) + ")   @ " + str(s.x) + "," + str(s.y))
	if s.in_disorder:
		_line(v, "!! IN DISORDER — production is halted")

	# ── City status (health + growth) ──────────────────────────────────────────
	# Jun 9 bug report: the city menu must show the city's defensive health and
	# whether it is growing.
	_header(v, "City status")
	var maxh: int = TurnEngine.city_max_health(s, db)
	# health < 0 is the "full" sentinel; a shrunk city may sit above the new cap.
	var cur_h: int = maxh if (s.health < 0 or s.health > maxh) else s.health
	_line(v, "Health: " + str(cur_h) + "/" + str(maxh) \
		+ ("   (full)" if cur_h >= maxh else "   (recovering)"))
	# Net food per turn = raw food output, less the wellbeing deficit, less what the
	# population eats (mirrors TurnEngine._settlement_growth's surplus calculation).
	var food_per: int = db.get_constant("food_per_citizen", 2)
	var net_food: int = s.output_food - s.wellbeing_deficit - s.population * food_per
	var growth_txt: String
	if net_food > 0:
		growth_txt = "growing (+" + str(net_food) + " food/turn, store " \
			+ str(s.food_store) + ")"
	elif net_food < 0:
		growth_txt = "starving (" + str(net_food) + " food/turn)"
	else:
		growth_txt = "stagnant (no food surplus)"
	_line(v, "Growth: " + growth_txt)

	# ── Output ────────────────────────────────────────────────────────────────
	_header(v, "Output")
	_line(v, "Food " + _sgn(s.output_food) + "    Production " + _sgn(s.output_production) \
		+ "    Commerce " + _sgn(s.output_commerce))
	if owner != null:
		var split = owner.split_commerce(s.output_commerce)
		_line(v, "Commerce split →  Finance " + str(split[0]) + "   Research " + str(split[1]) \
			+ "   Culture " + str(split[2]) + "   Intel " + str(split[3]))
	_line(v, "Food store: " + str(s.food_store) + "    Culture: " + str(s.culture_total) \
		+ " (border ring " + str(s.culture_ring) + ")")

	# ── Wellbeing & contentment ────────────────────────────────────────────────
	_header(v, "Wellbeing & Contentment")
	_line(v, "Wellbeing  +" + str(s.wellbeing_positive) + " / -" + str(s.wellbeing_negative) \
		+ "   (deficit " + str(s.wellbeing_deficit) + ")")
	_line(v, "Contentment  +" + str(s.positive_sentiment) + " / -" + str(s.negative_sentiment) \
		+ "   discontented " + str(s.discontented) + "/" + str(s.population))

	# ── Citizen management (worked tiles) ──────────────────────────────────────
	_header(v, "Worked tiles")
	_build_citizen_management(v, s, gs, db, techs)

	# ── Specialists ────────────────────────────────────────────────────────────
	_header(v, "Specialists")
	_build_specialists(v, s)

	# ── Current production ─────────────────────────────────────────────────────
	_header(v, "Production")
	if s.production_queue.empty():
		if s.produce_nothing:
			var nothing_btn := Button.new()
			nothing_btn.text = "Producing: Nothing  [click to resume]"
			nothing_btn.connect("pressed", self, "_on_resume_production")
			v.add_child(nothing_btn)
		else:
			_line(v, "Currently building: (nothing queued)")
			var nothing_btn := Button.new()
			nothing_btn.text = "Produce Nothing"
			nothing_btn.connect("pressed", self, "_on_produce_nothing")
			v.add_child(nothing_btn)
	else:
		var item = s.production_queue[0]
		var pace = db.get_pace(gs.pace_id)
		var cost = TurnEngine._item_cost(item, db, owner, pace)
		var head_row := HBoxContainer.new()
		var head_btn := Button.new()
		head_btn.text = "Building: " + str(item.get("id", "?")) + " (" \
			+ str(item.get("type", "")) + ")   " \
			+ str(s.production_store) + "/" + str(cost) + "  [click to remove]"
		head_btn.connect("pressed", self, "_on_dequeue", [0])
		head_row.add_child(head_btn)
		v.add_child(head_row)
		for i in range(1, s.production_queue.size()):
			var q_row := HBoxContainer.new()
			var up_btn := Button.new()
			up_btn.text = "^"
			up_btn.connect("pressed", self, "_on_move_up", [i])
			q_row.add_child(up_btn)
			var down_btn := Button.new()
			down_btn.text = "v"
			down_btn.connect("pressed", self, "_on_move_down", [i])
			q_row.add_child(down_btn)
			var q_btn := Button.new()
			q_btn.text = "   next: " + str(s.production_queue[i].get("id", "?")) \
				+ "  [click to remove]"
			q_btn.connect("pressed", self, "_on_dequeue", [i])
			q_row.add_child(q_btn)
			v.add_child(q_row)

	# ── City actions: hurry production / draft ─────────────────────────────────
	_header(v, "City Actions")
	var action_row := HBoxContainer.new()
	var can_rush_treasury: bool = false
	var can_rush_pop: bool = false
	var rush_gold_cost: int = 0
	if not s.production_queue.empty() and owner != null:
		var pace2 = db.get_pace(gs.pace_id)
		var item2 = s.production_queue[0]
		var cost2: int = TurnEngine._item_cost(item2, db, owner, pace2)
		rush_gold_cost = cost2 - s.production_store
		if rush_gold_cost < 0:
			rush_gold_cost = 0
		can_rush_treasury = rush_gold_cost > 0 \
			and PolicyEffects.has_flag(owner, db, "can_rush_with_gold") \
			and owner.treasury >= rush_gold_cost
		can_rush_pop = PolicyEffects.has_flag(owner, db, "rush_by_pop") \
			and s.population > 1
	var rush_gold_btn := Button.new()
	rush_gold_btn.text = "Hurry (Gold: " + str(rush_gold_cost) + ")"
	rush_gold_btn.disabled = not can_rush_treasury
	rush_gold_btn.connect("pressed", self, "_on_rush", ["treasury"])
	action_row.add_child(rush_gold_btn)
	var rush_pop_btn := Button.new()
	rush_pop_btn.text = "Hurry (Pop)"
	rush_pop_btn.disabled = not can_rush_pop
	rush_pop_btn.connect("pressed", self, "_on_rush", ["population"])
	action_row.add_child(rush_pop_btn)
	var min_pop: int = db.get_constant("draft_min_population", 2)
	var can_draft: bool = owner != null \
		and PolicyEffects.has_flag(owner, db, "can_draft") \
		and s.population >= min_pop and not s.in_disorder
	var draft_btn := Button.new()
	draft_btn.text = "Draft Unit"
	draft_btn.disabled = not can_draft
	draft_btn.connect("pressed", self, "_on_draft")
	action_row.add_child(draft_btn)
	v.add_child(action_row)

	# ── Quick build chooser ────────────────────────────────────────────────────
	_header(v, "Add to production")
	var options = [
		["unit", "warrior"], ["unit", "worker"], ["unit", "settler"],
		["unit", "scout"], ["unit", "archer"], ["unit", "work_boat"],
		["structure", "granary"], ["structure", "barracks"],
		["structure", "library"], ["structure", "market"]
	]
	var grid := GridContainer.new()
	grid.columns = 3
	for opt in options:
		var btn := Button.new()
		btn.text = "+ " + opt[1]
		var already: bool = false
		for existing in s.production_queue:
			if existing.get("type") == opt[0] and existing.get("id") == opt[1]:
				already = true
				break
		btn.disabled = already
		btn.connect("pressed", self, "_on_build", [opt[0], opt[1]])
		grid.add_child(btn)
	v.add_child(grid)

	# ── Buildings ──────────────────────────────────────────────────────────────
	_header(v, "Buildings")
	if s.structures.empty():
		_line(v, "  (none)")
	else:
		for st in s.structures:
			_line(v, "  - " + str(st))

	var close_btn := Button.new()
	close_btn.text = "Close"
	close_btn.connect("pressed", self, "_on_close")
	v.add_child(close_btn)

# Specialist types the city screen lets the player assign. The sim caps the
# total by population (there is no per-building slot ceiling yet — see
# designgaps §2), so these are offered uniformly.
const SPECIALIST_TYPES: Array = ["scientist", "merchant", "artist", "priest", "engineer"]

# Citizen management: an automate toggle plus a simplified grid of the tiles in
# the city's work radius. Each tile button shows its yield and whether it is
# worked/locked; clicking toggles a manual lock (auto-fill handles the rest when
# automation is on). The grid is a flat representation of the surrounding area,
# not a geographic map.
func _build_citizen_management(v, s, gs, db, techs) -> void:
	var auto_btn := Button.new()
	auto_btn.text = "Automate citizens: " + ("ON" if s.manage_citizens_auto else "OFF")
	auto_btn.connect("pressed", self, "_on_toggle_automation", [not s.manage_citizens_auto])
	v.add_child(auto_btn)

	_line(v, "Click a tile to lock/unlock it (★ locked+worked, ☆ locked, ● auto-worked):")

	var worked := {}
	for wt in s.worked_tiles:
		worked[str(int(wt[0])) + "," + str(int(wt[1]))] = true
	var locked := {}
	for lt in s.locked_tiles:
		locked[str(int(lt[0])) + "," + str(int(lt[1]))] = true

	var grid := GridContainer.new()
	grid.columns = 5
	for tile in gs.map.tiles_in_range(s.x, s.y, s.culture_ring):
		# Skip tiles the city can never work (owned by another player).
		if not (tile.owner_player_id == s.owner_player_id or tile.owner_player_id == -1):
			continue
		var key := str(tile.x) + "," + str(tile.y)
		var out = TileOutput.compute(tile, db, techs)
		var btn := Button.new()
		var mark := ""
		if locked.has(key):
			mark = "★ " if worked.has(key) else "☆ "
		elif worked.has(key):
			mark = "● "          # auto-assigned (worked but not locked)
		else:
			mark = "· "
		# The city's own tile is tagged for orientation.
		if tile.x == s.x and tile.y == s.y:
			mark = "⌂" + mark
		btn.text = mark + tile.terrain_id.left(4) \
			+ " F" + str(out[0]) + "P" + str(out[1]) + "C" + str(out[2])
		btn.connect("pressed", self, "_on_toggle_tile",
			[tile.x, tile.y, not locked.has(key)])
		grid.add_child(btn)
	v.add_child(grid)

# Specialists: current counts and +/- buttons per type. Adding is capped by the
# sim against the city's population.
func _build_specialists(v, s) -> void:
	var total := 0
	for k in s.specialists:
		total += int(s.specialists[k])
	_line(v, "Assigned specialists: " + str(total) + " / pop " + str(s.population))
	var grid := GridContainer.new()
	grid.columns = 4
	for stype in SPECIALIST_TYPES:
		var count: int = int(s.specialists.get(stype, 0))
		var lbl := Label.new()
		lbl.text = "  " + stype.capitalize() + ": " + str(count)
		grid.add_child(lbl)
		var minus := Button.new()
		minus.text = "−"
		minus.disabled = count <= 0
		minus.connect("pressed", self, "_on_specialist", [stype, count - 1])
		grid.add_child(minus)
		var plus := Button.new()
		plus.text = "+"
		plus.connect("pressed", self, "_on_specialist", [stype, count + 1])
		grid.add_child(plus)
		var pad := Control.new()
		grid.add_child(pad)
	v.add_child(grid)

func _on_toggle_automation(auto: bool) -> void:
	var gs = _facade.get_state()
	var s = gs.get_settlement(_city_id)
	if s == null:
		return
	_facade.apply_command(Commands.set_citizen_automation(s.owner_player_id, _city_id, auto))
	rebuild()

func _on_toggle_tile(tx: int, ty: int, worked: bool) -> void:
	var gs = _facade.get_state()
	var s = gs.get_settlement(_city_id)
	if s == null:
		return
	_facade.apply_command(Commands.set_tile_worked(s.owner_player_id, _city_id, tx, ty, worked))
	rebuild()

func _on_specialist(stype: String, new_count: int) -> void:
	if new_count < 0:
		return
	var gs = _facade.get_state()
	var s = gs.get_settlement(_city_id)
	if s == null:
		return
	_facade.apply_command(Commands.assign_specialist(s.owner_player_id, _city_id, stype, new_count))
	rebuild()

func _on_build(itype: String, iid: String) -> void:
	var gs = _facade.get_state()
	var s = gs.get_settlement(_city_id)
	if s == null:
		return
	for existing in s.production_queue:
		if existing.get("type") == itype and existing.get("id") == iid:
			return
	var q = s.production_queue.duplicate(true)
	q.append({"type": itype, "id": iid})
	_facade.apply_command(Commands.set_production(s.owner_player_id, _city_id, q))
	rebuild()

func _on_produce_nothing() -> void:
	var gs = _facade.get_state()
	var s = gs.get_settlement(_city_id)
	if s == null:
		return
	_facade.apply_command(Commands.set_production(
		s.owner_player_id, _city_id, [], true))
	rebuild()

func _on_resume_production() -> void:
	var gs = _facade.get_state()
	var s = gs.get_settlement(_city_id)
	if s == null:
		return
	_facade.apply_command(Commands.set_production(
		s.owner_player_id, _city_id, [], false))
	rebuild()

func _on_move_up(index: int) -> void:
	var gs = _facade.get_state()
	var s = gs.get_settlement(_city_id)
	if s == null or index <= 0:
		return
	_facade.apply_command(Commands.move_production_item(
		s.owner_player_id, _city_id, index, index - 1))
	rebuild()

func _on_move_down(index: int) -> void:
	var gs = _facade.get_state()
	var s = gs.get_settlement(_city_id)
	if s == null:
		return
	if index >= s.production_queue.size() - 1:
		return
	_facade.apply_command(Commands.move_production_item(
		s.owner_player_id, _city_id, index, index + 1))
	rebuild()

func _on_dequeue(index: int) -> void:
	var gs = _facade.get_state()
	var s = gs.get_settlement(_city_id)
	if s == null:
		return
	_facade.apply_command(Commands.dequeue_production(s.owner_player_id, _city_id, index))
	rebuild()

func _on_rush(method: String) -> void:
	var gs = _facade.get_state()
	var s = gs.get_settlement(_city_id)
	if s == null:
		return
	_facade.apply_command(Commands.rush_production(s.owner_player_id, _city_id, method))
	rebuild()

func _on_draft() -> void:
	var gs = _facade.get_state()
	var s = gs.get_settlement(_city_id)
	if s == null:
		return
	_facade.apply_command(Commands.draft(s.owner_player_id, _city_id))
	rebuild()

func close_screen() -> void:
	_on_close()

func _on_close() -> void:
	visible = false
	emit_signal("closed")

# ── Small UI helpers ───────────────────────────────────────────────────────────

func _title(parent, text: String) -> void:
	var lbl := Label.new()
	lbl.text = text
	parent.add_child(lbl)
	var sep := HSeparator.new()
	parent.add_child(sep)

func _header(parent, text: String) -> void:
	var sep := HSeparator.new()
	parent.add_child(sep)
	var lbl := Label.new()
	lbl.text = "[ " + text + " ]"
	parent.add_child(lbl)

func _line(parent, text: String) -> void:
	var lbl := Label.new()
	lbl.text = text
	parent.add_child(lbl)

func _sgn(v: int) -> String:
	return ("+" + str(v)) if v >= 0 else str(v)
