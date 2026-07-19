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

	# Title row with prev/next navigation across this player's own cities.
	var owned: Array = _owned_city_ids(gs, s.owner_player_id)
	var title_row := HBoxContainer.new()
	if owned.size() > 1:
		var prev_btn := Button.new()
		prev_btn.text = "◄ Prev"
		prev_btn.connect("pressed", self, "_on_cycle_city", [-1])
		title_row.add_child(prev_btn)
	var title_lbl := Label.new()
	title_lbl.text = "  " + s.name + "   (pop " + str(s.population) + ")   @ " \
		+ str(s.x) + "," + str(s.y)
	if owned.size() > 1:
		title_lbl.text += "   [" + str(owned.find(_city_id) + 1) + "/" + str(owned.size()) + "]"
	title_row.add_child(title_lbl)
	if owned.size() > 1:
		var next_btn := Button.new()
		next_btn.text = "Next ►"
		next_btn.connect("pressed", self, "_on_cycle_city", [1])
		title_row.add_child(next_btn)
	v.add_child(title_row)
	v.add_child(HSeparator.new())
	if s.in_disorder:
		_line(v, "!! IN DISORDER — production is halted")

	# ── City status (health + growth) ──────────────────────────────────────────
	# Jun 9 bug report: the city menu must show the city's defensive health and
	# whether it is growing.
	_header(v, "City status")
	var maxh: int = TurnEngine.city_max_health(s, db, gs.get_player(s.owner_player_id))
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
	# Culture level (§15.4 / D2): the level name plus the border ring it grants;
	# the level's intrinsic city defence shows its bombardment wear, if any.
	var culture_line: String = "Food store: " + str(s.food_store) + "    Culture: " \
		+ str(s.culture_total) + " (" + CultureLevels.level_name(db, s.culture_ring - 1) \
		+ ", border ring " + str(s.culture_ring) + ")"
	var cdef: int = Combat.culture_defence(s, db)
	var cdef_full: int = CultureLevels.defence_pct(db, s.culture_ring - 1)
	if cdef_full > 0:
		culture_line += "    Culture defence: +" + str(cdef) + "%"
		if cdef < cdef_full:
			culture_line += " (bombarded, heals +" \
				+ str(db.get_constant("city_defence_heal_rate", 5)) + "/turn)"
	_line(v, culture_line)

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
	_build_specialists(v, s, db, owner)

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
	var rush_pop_cost: int = 0
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
		# Population rush (§15.2): needs a permitting civic (Slavery), a cost to
		# cover, and enough citizens to keep the minimum city size afterwards.
		rush_pop_cost = _facade.rush_population_cost(_city_id)
		var min_pop: int = db.get_constant("rush_min_population", 1)
		can_rush_pop = PolicyEffects.has_flag(owner, db, "pop_rush") \
			and rush_pop_cost > 0 \
			and s.population - rush_pop_cost >= min_pop
	var rush_gold_btn := Button.new()
	rush_gold_btn.text = "Hurry (Gold: " + str(rush_gold_cost) + ")"
	rush_gold_btn.disabled = not can_rush_treasury
	rush_gold_btn.connect("pressed", self, "_on_rush", ["treasury"])
	action_row.add_child(rush_gold_btn)
	var rush_pop_btn := Button.new()
	rush_pop_btn.text = "Hurry (Pop: " + str(rush_pop_cost) + ")"
	rush_pop_btn.disabled = not can_rush_pop
	rush_pop_btn.connect("pressed", self, "_on_rush_pop")
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
	# A sea unit (e.g. work_boat / fishing boats) can only be built in a coastal
	# city; every option also requires its prerequisite tech (Jun 9 bug report).
	var coastal: bool = TurnEngine._is_coastal(gs, s.x, s.y)
	# Connected-resource set, computed once for the option list (§15.12): a unit
	# with a resource requirement is only offered while the city's owner has it.
	var have: Dictionary = EconOrgs.accessible_resources(gs, s.owner_player_id)
	for opt in options:
		if not _can_offer_production(opt[0], opt[1], db, owner, have, coastal):
			continue
		var btn := Button.new()
		btn.text = "+ " + opt[1]
		btn.disabled = not _can_queue_more(opt[0], opt[1], s.structures, s.production_queue)
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

	_line(v, "Work grid (fixed 5×5) — # = worked, ⌂ = city centre, blank button = unavailable.")
	_line(v, "Click a worked/workable tile to lock/unlock it (★ locked, ☆ locked+idle):")

	var worked := {}
	for wt in s.worked_tiles:
		worked[str(int(wt[0])) + "," + str(int(wt[1]))] = true
	var locked := {}
	for lt in s.locked_tiles:
		locked[str(int(lt[0])) + "," + str(int(lt[1]))] = true

	# Render a FIXED 5×5 grid (a 2-tile radius around the city centre, dx/dy each
	# from -2..+2) so the grid shape is always the full 25 button slots regardless
	# of the city's actual culture_ring. A tile the city cannot currently work
	# (off-map, foreign-owned, or outside the real work radius) renders as a blank
	# button (a Button with no text) so the 5×5 shell stays complete.
	var radius: int = 2
	var grid := GridContainer.new()
	grid.columns = 2 * radius + 1
	for dy in range(-radius, radius + 1):
		for dx in range(-radius, radius + 1):
			var tx: int = s.x + dx
			var ty: int = s.y + dy
			var tile = gs.map.get_tile(tx, ty) if gs.map.is_valid(tx, ty) else null
			if tile == null or not _tile_workable(tile, s, gs):
				# Unavailable tile → blank button keeps the 5×5 shell complete.
				var blank := Button.new()
				blank.text = ""
				blank.disabled = true
				grid.add_child(blank)
				continue
			var key := str(tile.x) + "," + str(tile.y)
			var is_center: bool = (tile.x == s.x and tile.y == s.y)
			# The centre tile is worked for free even if not listed in worked_tiles.
			var is_worked: bool = worked.has(key) or is_center
			var out = TileOutput.compute(tile, db, techs,
				gs.map.tile_has_river(tile.x, tile.y))
			var btn := Button.new()
			var mark: String = _tile_grid_marker(is_center, is_worked, locked.has(key))
			btn.text = mark + tile.terrain_id.left(4) \
				+ " F" + str(out[0]) + "P" + str(out[1]) + "C" + str(out[2])
			btn.connect("pressed", self, "_on_toggle_tile",
				[tile.x, tile.y, not locked.has(key)])
			grid.add_child(btn)
	v.add_child(grid)

# Whether the city can CURRENTLY work this tile: it must lie within the city's
# real work radius (its culture_ring), be owned by the city's player or be
# unowned (-1), and be workable terrain (mountain peaks are unworkable). Tiles
# outside the ring, owned by another player, or unworkable are not currently
# usable — they render as a blank cell in the fixed 5×5 grid. The centre tile
# is always usable (it is worked for free). Mirrors the sim's own auto-assign
# filter in TurnEngine (tiles_in_range(culture_ring) + ownership + workable).
func _tile_workable(tile, s, gs) -> bool:
	if tile.owner_player_id != s.owner_player_id and tile.owner_player_id != -1:
		return false
	if not TileOutput.workable(tile, gs.db):
		return false
	return gs.map.distance(s.x, s.y, tile.x, tile.y) <= s.culture_ring

# The marker prefix for a work-grid cell. A currently-worked tile carries the #
# worked marker; the city centre also shows its ⌂ glyph (and is always worked, so
# it carries the # too). A manual lock is flagged with ★ (locked+worked) or ☆
# (locked but not currently worked). Pure so the worked-vs-unworked convention is
# directly unit-testable.
func _tile_grid_marker(is_center: bool, is_worked: bool, is_locked: bool) -> String:
	var prefix: String = "⌂" if is_center else ""
	if is_locked:
		return prefix + ("★ " if is_worked else "☆ ")
	return prefix + ("# " if is_worked else "  ")

# Specialists: current counts and +/- buttons per assignable type, read from the
# specialists data table (output, GP type, slot ceiling). Adding is capped by the
# sim against the city's population and the per-type slot count (−1 = unlimited,
# e.g. Caste System); the + button greys out at the ceiling.
func _build_specialists(v, s, db, owner) -> void:
	var total := 0
	for k in s.specialists:
		total += int(s.specialists[k])
	_line(v, "Assigned specialists: " + str(total) + " / pop " + str(s.population))
	var grid := GridContainer.new()
	grid.columns = 4
	for stype in Specialists.assignable_types(db):
		var count: int = int(s.specialists.get(stype, 0))
		var slots: int = Specialists.slots_for(db, s, owner, stype)
		var slot_txt: String = "∞" if slots < 0 else str(slots)
		var lbl := Label.new()
		lbl.text = "  " + stype.capitalize() + ": " + str(count) + "/" + slot_txt
		lbl.hint_tooltip = _specialist_tooltip(db, stype)
		grid.add_child(lbl)
		var minus := Button.new()
		minus.text = "−"
		minus.disabled = count <= 0
		minus.connect("pressed", self, "_on_specialist", [stype, count - 1])
		grid.add_child(minus)
		var plus := Button.new()
		plus.text = "+"
		plus.disabled = (slots >= 0 and count >= slots) or total >= s.population
		plus.connect("pressed", self, "_on_specialist", [stype, count + 1])
		grid.add_child(plus)
		var pad := Control.new()
		grid.add_child(pad)
	v.add_child(grid)

# A one-line "+N foo, +M bar" summary of a specialist type's per-head output.
func _specialist_tooltip(db, stype: String) -> String:
	var parts := []
	for ch in Specialists.CHANNELS:
		var amt: int = int(Specialists.output(db, stype).get(ch, 0))
		if amt != 0:
			parts.append("+" + str(amt) + " " + ch)
	return ", ".join(parts) if not parts.empty() else "no yield"

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

# Whether a quick-build option is offered to this city: its prerequisite techs
# must be researched and (for units) its resource requirement met — both via the
# shared compound-prereq reader (§15.12) so the chooser can never offer a unit
# the sim gates would refuse — and a sea-domain unit requires a coastal city
# (Jun 9 bug report — work_boat / other water units only appear once buildable).
# `have` is the owner's connected-resource set (EconOrgs.accessible_resources).
func _can_offer_production(kind: String, id: String, db, owner, have: Dictionary, coastal: bool) -> bool:
	var data: Dictionary = db.get_unit(id) if kind == "unit" else db.get_structure(id)
	if data.empty():
		return false
	if not UnitPrereqs.tech_ok(data.get("tech_required", null), owner):
		return false
	if kind == "unit":
		if not UnitPrereqs.resource_ok(data.get("resource_required", null), have):
			return false
		if str(data.get("domain", "land")) == "sea" and not coastal:
			return false
	return true

# Whether another copy of (kind, id) may be added to this city's queue.
# Repeatable items — units, and anything not one-per-city — stay addable even
# when one is already queued (e.g. three warriors). One-per-city items
# (buildings/wonders: every "structure") are blocked once they are already built
# (present in s.structures) or already queued. Pure so the classification is
# directly unit-testable.
func _can_queue_more(kind: String, id: String, structures: Array, queue: Array) -> bool:
	if not _is_one_per_city(kind):
		return true
	if id in structures:
		return false
	for existing in queue:
		if existing.get("type") == kind and existing.get("id") == id:
			return false
	return true

# A "structure" (building or wonder) can exist at most once per city, so it is
# one-per-city; units (and any other repeatable item) are not.
func _is_one_per_city(kind: String) -> bool:
	return kind == "structure"

func _on_build(itype: String, iid: String) -> void:
	var gs = _facade.get_state()
	var s = gs.get_settlement(_city_id)
	if s == null:
		return
	if not _can_queue_more(itype, iid, s.structures, s.production_queue):
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

func _on_rush_pop() -> void:
	var gs = _facade.get_state()
	var s = gs.get_settlement(_city_id)
	if s == null:
		return
	_facade.apply_command(Commands.rush_population(s.owner_player_id, _city_id))
	rebuild()

func _on_draft() -> void:
	var gs = _facade.get_state()
	var s = gs.get_settlement(_city_id)
	if s == null:
		return
	_facade.apply_command(Commands.draft(s.owner_player_id, _city_id))
	rebuild()

# Ordered list of settlement ids owned by a player (in gs.settlements order, which
# is founding order). Pure-ish helper so the navigation order is deterministic.
func _owned_city_ids(gs, player_id: int) -> Array:
	var ids: Array = []
	for st in gs.settlements:
		if st.owner_player_id == player_id:
			ids.append(st.id)
	return ids

# Cycle the displayed city to the prev (-1) / next (+1) settlement owned by the
# same player, wrapping around. Re-opens the screen on that city.
func _on_cycle_city(dir: int) -> void:
	var gs = _facade.get_state()
	var s = gs.get_settlement(_city_id)
	if s == null:
		return
	var owned: Array = _owned_city_ids(gs, s.owner_player_id)
	if owned.size() <= 1:
		return
	var idx: int = owned.find(_city_id)
	if idx < 0:
		return
	var next_idx: int = (idx + dir + owned.size()) % owned.size()
	show_city(owned[next_idx])

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
