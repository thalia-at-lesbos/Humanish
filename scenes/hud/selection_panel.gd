# Humanish — a turn-based 4X strategy game.
# Copyright (C) 2026 thalia-at-lesbos
# SPDX-License-Identifier: GPL-3.0-or-later
#
# This program is free software: you can redistribute it and/or modify it
# under the terms of the GNU General Public License as published by the Free
# Software Foundation, either version 3 of the License, or (at your option)
# any later version. See the LICENSE file for the full text and warranty
# disclaimer.

extends VBoxContainer

# Shows info about the currently selected unit or city.
# Action buttons are built dynamically from facade.get_flyout_menu().

var _facade
var _world_view

# Bounded visible height for the on-tile stack list (Issue 3) so a large stack
# scrolls instead of pushing the action buttons/terrain readout off-screen.
const STACK_LIST_MAX_HEIGHT: int = 120

# Near-opaque dark-charcoal backing so the unit info, action buttons and tile
# readout read clearly against the map (Issue 1). Drawn in _draw() behind the
# VBox's children — a child ColorRect would be pulled into the vertical layout,
# whereas drawing fills the whole panel rect and never intercepts mouse clicks
# meant for the buttons. The padding bleeds the fill a few pixels past the
# content so labels/buttons are not flush against the charcoal edge.
const BG_COLOR: Color = Color(0.10, 0.11, 0.13, 0.90)
const BG_PADDING: int = 4

func init(facade, world_view) -> void:
	_facade = facade
	_world_view = world_view

# Paint the charcoal background behind all content. _draw() runs before the
# child controls render, so the fill always sits behind the labels/buttons; it
# does not participate in layout and never blocks input. When the panel is empty
# (no selection) get_children() is empty and the VBox collapses to zero size, so
# nothing is drawn — the background only appears when there is content.
func _draw() -> void:
	if get_child_count() == 0:
		return
	var pad: Vector2 = Vector2(BG_PADDING, BG_PADDING)
	draw_rect(Rect2(-pad, rect_size + pad * 2.0), BG_COLOR)

# The VBox resizes as content is added/removed; repaint the background to match.
func _notification(what: int) -> void:
	if what == NOTIFICATION_RESIZED:
		update()

# A natural-width, left-justified action button (Issue 1). Inside the panel's
# VBoxContainer a Button defaults to filling the full width; SIZE_SHRINK_BEGIN
# shrinks it to its content and anchors it to the left, while keeping every
# action button in the same region/anchor between the state info and the terrain
# readout.
func _left_button(text: String) -> Button:
	var btn: Button = Button.new()
	btn.text = text
	# size flags of 0 = shrink to content, anchored at the start (left). Godot 3 has
	# no SIZE_SHRINK_BEGIN; clearing the FILL/EXPAND bits gives a left-justified,
	# natural-width button inside the panel's VBoxContainer.
	btn.size_flags_horizontal = 0
	return btn

func rebuild() -> void:
	if _facade == null:
		return
	_clear_children()

	var sel = _facade.get_selection()
	var gs = _facade.get_state()
	var head_uid: int = sel.head_unit()
	var head_cid: int = sel.head_city()

	if head_uid >= 0:
		_build_unit_panel(head_uid, gs)
	elif head_cid >= 0:
		_build_city_panel(head_cid, gs)
	elif sel.has_inspected_tile():
		_build_tile_panel(int(sel.inspected_tile.x), int(sel.inspected_tile.y))

	# Repaint the charcoal backing after the content set changes (the resize
	# notification covers most cases, but an explicit update() guarantees the fill
	# tracks an empty→populated transition that may not change the panel's size).
	update()

func _build_unit_panel(unit_id: int, gs) -> void:
	var u = gs.get_unit(unit_id)
	if u == null:
		return
	var udata = _facade._db.get_unit(u.unit_type_id)

	var name_lbl: Label = Label.new()
	name_lbl.text = u.unit_type_id.capitalize()
	add_child(name_lbl)

	# Strength line (Issue 4): combat units only — base strength with the net
	# effective (current-tile-modifier-adjusted) value in parentheses. The math
	# lives in the sim layer (SimFacade.unit_strength_text → Unit.effective_strength)
	# so terrain/fortify/promotion/health modifiers stay authoritative; civilians
	# (base_strength 0) get an empty string and no line is shown.
	var strength_text: String = _facade.unit_strength_text(u.id)
	if strength_text != "":
		var strength_lbl: Label = Label.new()
		strength_lbl.text = strength_text
		add_child(strength_lbl)

	var health_lbl: Label = Label.new()
	health_lbl.text = "HP: " + str(u.health) + "/100"
	add_child(health_lbl)

	var move_lbl: Label = Label.new()
	move_lbl.text = "MP: " + str(u.movement_left) + "/" + str(u.movement_total)
	add_child(move_lbl)

	# Current activity/stance (fortified, sleeping, moving to a target, building…),
	# so a selected unit's state is visible at a glance. Text comes from the rules
	# layer (TextGen) so it always matches the actual order semantics.
	var state_lbl: Label = Label.new()
	state_lbl.text = "State: " + TextGen.unit_state_text(u)
	add_child(state_lbl)

	# Issue 2: when this unit shares its tile with the player's own city, surface an
	# "Open City" action ABOVE the on-tile stack list (the city is selectable by
	# left-click cycling too, but a direct button is the discoverable path).
	var sel = _facade.get_selection()
	var city_here = gs.get_settlement_at(u.x, u.y)
	if city_here != null and city_here.owner_player_id == gs.current_player_id:
		var open_city_btn: Button = _left_button("Open City")
		open_city_btn.connect("pressed", self, "_on_open_city", [city_here.id])
		add_child(open_city_btn)

	# On-tile unit list: every unit the player owns on this tile, so a stack can
	# be inspected and addressed member-by-member. Clicking a row selects just
	# that unit; "Select all" makes subsequent action buttons apply to the whole
	# stack at once. The rows live in a bounded ScrollContainer (Issue 3) so a
	# large stack stays reachable instead of overflowing off-screen.
	var stack: Array = _owned_units_on_tile(u.x, u.y, gs)
	if stack.size() > 1:
		var stack_lbl: Label = Label.new()
		stack_lbl.text = "Stack on tile (" + str(stack.size()) + "):"
		add_child(stack_lbl)
		var scroll: ScrollContainer = ScrollContainer.new()
		scroll.rect_min_size = Vector2(0, STACK_LIST_MAX_HEIGHT)
		scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		var list_vbox: VBoxContainer = VBoxContainer.new()
		list_vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		scroll.add_child(list_vbox)
		for su in stack:
			# Left-justified/natural-width like the sibling action buttons (Issue 5):
			# route through _left_button (which clears the FILL/EXPAND size flags) so
			# the ▸-marked rows shrink to content and anchor left instead of stretching
			# the full list width. The list_vbox stays EXPAND_FILL so it spans the
			# ScrollContainer's width (preserving horizontal scroll), while the buttons
			# inside it left-align.
			var mark: String = "▸ " if su.id in sel.selected_unit_ids else "  "
			var row: Button = _left_button(mark + su.unit_type_id.capitalize() + "  (HP " + str(su.health) + ")")
			row.connect("pressed", self, "_on_select_stack_member", [su.id])
			list_vbox.add_child(row)
		add_child(scroll)
		var all_btn: Button = _left_button("Select all (" + str(stack.size()) + ")")
		all_btn.connect("pressed", self, "_on_select_all", [u.x, u.y])
		add_child(all_btn)

	# Action buttons for the SELECTED unit (Issues 4–7): the list comes from
	# get_unit_actions(unit_id), keyed to the head unit, so a settler in a mixed
	# stack shows Found City and a garrisoned defender shows Fortify — instead of
	# only the first unit on the tile dictating the buttons. Buttons are wrapped in
	# a left-aligning row container (Issue 1) so they are natural-width and
	# left-justified within the same region between the state info above and the
	# terrain readout below.
	var menu: Array = _facade.get_unit_actions(u.id)
	for item in menu:
		var btn: Button = _left_button(str(item.get("label", "")))
		btn.connect("pressed", self, "_on_action_pressed", [item])
		add_child(btn)

	# Issue 6: Worker improvement buttons — shown for units that can build.
	var db = _facade._db
	if db.get_unit(u.unit_type_id).get("can_build", false):
		_add_worker_buttons(u, gs)

	# Issue 6/13: Explore button — shown for every combat unit (non-civilian with
	# positive base strength), plus recon/scout and any explicitly explore-tagged
	# unit. Mirrors the facade's MISSION_EXPLORE gate so the button never offers an
	# order the command would reject. Civilians (base_strength 0) and missiles/Great
	# People (also base_strength 0) get no Explore button.
	var udata_sel: Dictionary = db.get_unit(u.unit_type_id)
	var cls_sel: String = str(udata_sel.get("classification", ""))
	var has_explore_tag: bool = "explore" in udata_sel.get("tags", [])
	var is_combat_sel: bool = cls_sel != "civilian" and u.base_strength > 0
	if is_combat_sel or cls_sel == "recon" or has_explore_tag:
		if not u.is_exploring:
			var explore_btn: Button = _left_button("Explore")
			explore_btn.connect("pressed", self, "_on_explore_pressed", [u.id])
			add_child(explore_btn)
		else:
			var stop_exp_btn: Button = _left_button("Stop Exploring")
			stop_exp_btn.connect("pressed", self, "_on_wake_pressed", [u.id])
			add_child(stop_exp_btn)

	# Heal-until-recovered buttons (Issue 9): shown when the unit is injured.
	if u.health < 100:
		var sleep_btn: Button = _left_button("Sleep Until Healed")
		sleep_btn.connect("pressed", self, "_on_sleep_until_healed", [u.id])
		add_child(sleep_btn)

		# Fortify Until Healed: only for non-civilian units.
		var cls: String = str(db.get_unit(u.unit_type_id).get("classification", ""))
		if cls != "civilian":
			var fort_btn: Button = _left_button("Fortify Until Healed")
			fort_btn.connect("pressed", self, "_on_fortify_until_healed", [u.id])
			add_child(fort_btn)

	# Underlying tile terrain readout, so a selected unit also shows the terrain
	# data of the tile it stands on (not just an inspected empty tile).
	_append_tile_terrain(u.x, u.y)

func _build_city_panel(city_id: int, gs) -> void:
	var s = gs.get_settlement(city_id)
	if s == null:
		return

	var name_lbl: Label = Label.new()
	name_lbl.text = s.name
	add_child(name_lbl)

	var pop_lbl: Label = Label.new()
	pop_lbl.text = "Pop: " + str(s.population)
	add_child(pop_lbl)

	var prod_lbl: Label = Label.new()
	if not s.production_queue.empty():
		prod_lbl.text = "Building: " + str(s.production_queue[0].get("id", "?"))
	else:
		prod_lbl.text = "Building: (none)"
	add_child(prod_lbl)

	# Show revolt status for a recently-conquered city (§4.8).
	if s.revolt_turns > 0:
		var revolt_lbl: Label = Label.new()
		revolt_lbl.text = "In revolt: " + str(s.revolt_turns) + " turn(s)"
		add_child(revolt_lbl)

	# Open city screen button (Issue 5: left-justified like the unit-panel buttons).
	var city_btn: Button = _left_button("Open City")
	city_btn.connect("pressed", self, "_on_open_city", [city_id])
	add_child(city_btn)

	# Disband (raze) — the at-any-time disband, and the "raze" choice for a
	# just-conquered city (§4.8). The capital (the city holding the Palace) cannot
	# be disbanded, so it shows no Disband button at all (the command is also
	# rejected facade-side; this keeps the UI honest about what is allowed).
	if not s.has_structure("palace"):
		var disband_btn: Button = _left_button("Disband City")
		disband_btn.connect("pressed", self, "_on_disband_city", [city_id])
		add_child(disband_btn)

	# Underlying tile terrain readout for the city's tile, so a selected city also
	# shows its tile's terrain data (matching the unit and empty-tile panels).
	_append_tile_terrain(s.x, s.y)

# Terrain readout for an inspected (unoccupied / illegal-target) tile.
func _build_tile_panel(tx: int, ty: int) -> void:
	_append_tile_terrain(tx, ty)

# Append the shared terrain readout for a tile (terrain, feature, resource,
# yields, movement cost, defence). Reused by the unit, city and empty-tile
# panels so the formatting never diverges; the text comes from the rules layer
# (SimFacade.tile_info_text) for consistency.
func _append_tile_terrain(tx: int, ty: int) -> void:
	var text: String = _facade.tile_info_text(tx, ty)
	if text == "":
		return
	var lbl: Label = Label.new()
	lbl.text = text
	add_child(lbl)

func _on_action_pressed(item: Dictionary) -> void:
	# Map an action item to a command. The item's "kind" ("mission"/"cmd")
	# disambiguates the UnitCmd/UnitMission enums (whose raw integer values overlap,
	# e.g. FORTIFY==2 and SKIP_TURN==2). When a whole stack is selected, per-unit
	# orders (fortify / sleep / wake / skip) apply to every selected unit; founding a
	# settlement stays a single-settler action on the head unit.
	var gs = _facade.get_state()
	var sel = _facade.get_selection()
	var uid: int = sel.head_unit()
	if uid < 0:
		return
	var pid: int = gs.current_player_id
	var kind: String = str(item.get("kind", ""))
	var aid: int = int(item.get("action_id", -1))
	if kind == "mission" and aid == IDs.UnitMission.FOUND_SETTLEMENT:
		_facade.apply_command(Commands.found_settlement(pid, int(item.get("unit_id", uid))))
	elif kind == "mission" and aid == IDs.UnitMission.SKIP_TURN:
		for id in sel.selected_unit_ids:
			_facade.apply_command(Commands.mission_skip_turn(pid, id))
	elif kind == "cmd" and aid == IDs.UnitCmd.FORTIFY:
		for id in sel.selected_unit_ids:
			_facade.apply_command(Commands.unit_fortify(pid, id))
	elif kind == "cmd" and aid == IDs.UnitCmd.SLEEP:
		for id in sel.selected_unit_ids:
			_facade.apply_command(Commands.unit_sleep(pid, id))
	elif kind == "cmd" and aid == IDs.UnitCmd.WAKE:
		for id in sel.selected_unit_ids:
			_facade.apply_command(Commands.unit_wake(pid, id))
	rebuild()

func _on_select_stack_member(unit_id: int) -> void:
	_facade.select_unit(unit_id)
	rebuild()

func _on_select_all(tx: int, ty: int) -> void:
	_facade.select_stack(tx, ty)
	rebuild()

# Every unit the current player owns on a tile, in stable spawn order.
func _owned_units_on_tile(tx: int, ty: int, gs) -> Array:
	var out: Array = []
	for u in gs.units:
		if u.x == tx and u.y == ty and u.owner_player_id == gs.current_player_id:
			out.append(u)
	return out

func _on_open_city(_city_id: int) -> void:
	_facade.apply_command(Commands.do_control(
		_facade.get_state().current_player_id, IDs.ControlType.OPEN_CITY_SCREEN))

func _on_disband_city(city_id: int) -> void:
	_facade.apply_command(Commands.disband_city(
		_facade.get_state().current_player_id, city_id))

func _on_sleep_until_healed(unit_id: int) -> void:
	_facade.apply_command(Commands.mission_sleep_until_healed(
		_facade.get_state().current_player_id, unit_id))

func _on_fortify_until_healed(unit_id: int) -> void:
	_facade.apply_command(Commands.mission_fortify_until_healed(
		_facade.get_state().current_player_id, unit_id))

# Issue 6: Build the worker improvement buttons for a unit standing on `tile`.
# Only shows improvements valid for the tile's landform and for which the
# player holds the required technology. Skips upgrade-only improvements (they
# are placed automatically), the current improvement (already built), and road
# if the road command is already exposed by the flyout menu.
func _add_worker_buttons(unit, gs) -> void:
	var pid: int = gs.current_player_id
	var player = gs.get_player(pid)
	if player == null:
		return
	var db = _facade._db
	var tile = gs.map.get_tile(unit.x, unit.y)
	if tile == null:
		return
	# A unit standing on a city/settlement tile cannot improve it — show no
	# improvement or chop buttons there.
	if gs.get_settlement_at(unit.x, unit.y) != null:
		return
	var ter: Dictionary = db.get_terrain(tile.terrain_id)
	var landform: String = str(ter.get("landform", "flat"))
	# A tile has a river if its north or west border is a river edge, or if
	# the tile to the south/east has a north/west river edge bordering this tile.
	var has_river: bool = tile.river_n or tile.river_w
	if not has_river:
		var south = gs.map.get_tile(tile.x, tile.y + 1)
		if south != null and south.river_n:
			has_river = true
	if not has_river:
		var east = gs.map.get_tile(tile.x + 1, tile.y)
		if east != null and east.river_w:
			has_river = true
	var feature_id: String = tile.feature_id
	var current_imp: String = tile.improvement_id

	for imp_id in db.improvements:
		var imp: Dictionary = db.improvements[imp_id]
		# Skip upgrade-only improvements (cottage→hamlet→village→town chain etc.).
		if bool(imp.get("upgrade_only", false)):
			continue
		# Road is already handled by MISSION_BUILD_ROAD in the flyout; skip here.
		if imp_id == "road":
			continue
		# Skip if already built on this tile.
		if imp_id == current_imp:
			continue
		# Check landform compatibility.
		var allowed: Array = imp.get("allowed_landforms", [])
		if not (landform in allowed):
			continue
		# Check river requirement.
		if bool(imp.get("requires_river", false)) and not has_river:
			continue
		# Check feature requirement.
		var req_feat: String = str(imp.get("requires_feature", ""))
		if req_feat != "" and feature_id != req_feat:
			continue
		# Check tech requirement.
		var tech_req = imp.get("tech_required", null)
		if tech_req != null and tech_req != "" and not player.has_tech(str(tech_req)):
			continue
		# Check resource requirement: a resource-bound improvement (pasture,
		# plantation, fishing boats, …) only shows on a tile with a matching
		# resource the player can already see (its reveal tech researched).
		if bool(imp.get("requires_resource", false)) \
				and not _facade._tile_offers_resource_improvement(tile, imp_id, player):
			continue
		# Check food requirement (cottage needs a non-zero-food tile, §5): share
		# the facade's authoritative legality predicate so the panel never offers
		# a build the command would reject.
		if not _facade.can_build_improvement(player.id, unit.id, imp_id):
			continue
		# All checks passed: show a button for this improvement.
		var imp_name: String = str(imp.get("name", imp_id.capitalize()))
		var btn: Button = _left_button("Build " + imp_name)
		btn.connect("pressed", self, "_on_build_improvement_pressed", [unit.id, imp_id])
		add_child(btn)

	# Chop/clear (§4.11): a removable surface feature on the tile can be felled on
	# its own (a forest yields production to the nearest city; jungle just clears).
	if feature_id != "":
		var feat: Dictionary = db.get_feature(feature_id)
		if bool(feat.get("removable", false)):
			var feat_name: String = str(feat.get("name", feature_id.capitalize()))
			var chop_btn: Button = _left_button("Chop " + feat_name)
			chop_btn.connect("pressed", self, "_on_clear_feature_pressed", [unit.id])
			add_child(chop_btn)

func _on_build_improvement_pressed(unit_id: int, improvement_id: String) -> void:
	_facade.apply_command(Commands.build_improvement(
		_facade.get_state().current_player_id, unit_id, improvement_id))
	rebuild()

# Chop/clear the removable feature on the worker's tile (§4.11).
func _on_clear_feature_pressed(unit_id: int) -> void:
	_facade.apply_command(Commands.mission_clear_feature(
		_facade.get_state().current_player_id, unit_id))
	rebuild()

# Issue 13: Start Explore mission on a scout/recon unit.
func _on_explore_pressed(unit_id: int) -> void:
	_facade.apply_command(Commands.mission_explore(
		_facade.get_state().current_player_id, unit_id))
	rebuild()

# Stop Exploring: wake the unit (cancel explore stance).
func _on_wake_pressed(unit_id: int) -> void:
	_facade.apply_command(Commands.unit_wake(
		_facade.get_state().current_player_id, unit_id))
	rebuild()

func _clear_children() -> void:
	# Remove from the tree immediately (queue_free alone is deferred, which can
	# leave stale buttons rendered for a frame after the selection changes).
	for child in get_children():
		remove_child(child)
		child.queue_free()
