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

# Encyclopedia (§3.1 OPEN_ENCYCLOPEDIA, §11): interactive tabbed reference.
# Top-level TabContainer with one tab per category; data tabs use a list+detail
# split so the player can browse entries. The Guide tab covers game mechanics
# drawn from the user-reference document. Read-only; no commands issued.

const _LIST_W = 230
const _ERA_ORDER = [
	"ancient", "classical", "medieval", "renaissance",
	"industrial", "modern", "future"
]
const _CLASS_ORDER = [
	"civilian", "melee", "ranged", "mounted", "siege",
	"gunpowder", "armor", "naval", "air", "recon", "missile", "great_person"
]

var _facade
var _tab_state: Dictionary = {}  # tab_key -> {items: Array, detail: VBoxContainer}

# ── lifecycle ───────────────────────────────────────────────────────────────

func init(facade) -> void:
	_facade = facade
	anchor_right = 1.0
	anchor_bottom = 1.0
	mouse_filter = Control.MOUSE_FILTER_STOP
	visible = false

func show_screen() -> void:
	visible = true
	rebuild()

func rebuild() -> void:
	_tab_state = {}
	for c in get_children():
		remove_child(c)
		c.free()

	var bg = ColorRect.new()
	bg.anchor_right = 1.0
	bg.anchor_bottom = 1.0
	bg.color = Color(0.10, 0.10, 0.13, 1.0)
	add_child(bg)

	var root = VBoxContainer.new()
	root.anchor_right = 1.0
	root.anchor_bottom = 1.0
	add_child(root)

	var hdr = HBoxContainer.new()
	var ttl = Label.new()
	ttl.text = "Encyclopedia"
	hdr.add_child(ttl)
	var sp = Control.new()
	sp.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hdr.add_child(sp)
	var close_btn = Button.new()
	close_btn.text = "Close"
	close_btn.connect("pressed", self, "_on_close")
	hdr.add_child(close_btn)
	root.add_child(hdr)

	var tabs = TabContainer.new()
	tabs.size_flags_vertical = Control.SIZE_EXPAND_FILL
	root.add_child(tabs)

	var db = _facade._db
	_add_guide_tab(tabs)
	_add_data_tab(tabs, "Technologies", _collect_techs(db))
	_add_data_tab(tabs, "Units", _collect_units(db))
	_add_data_tab(tabs, "Buildings", _collect_buildings(db))
	_add_data_tab(tabs, "Resources", _collect_resources(db))
	_add_data_tab(tabs, "Civics", _collect_civics(db))
	_add_data_tab(tabs, "Promotions", _collect_promos(db))
	_add_data_tab(tabs, "Beliefs & Orgs", _collect_beliefs_orgs(db))
	_add_data_tab(tabs, "Societies", _collect_societies(db))
	_add_maps_tab(tabs, db)
	_add_reference_tab(tabs, db)

func close_screen() -> void:
	_on_close()

func _on_close() -> void:
	visible = false

# ── string helpers ──────────────────────────────────────────────────────────

func _fmt(s: String) -> String:
	return s.capitalize()

func _fmt_name(d: Dictionary) -> String:
	if d.has("name") and str(d["name"]) != "":
		return str(d["name"])
	return _fmt(str(d.get("id", "?")))

func _join(arr: Array) -> String:
	if arr.empty():
		return "none"
	var parts = PoolStringArray()
	for item in arr:
		parts.append(_fmt(str(item)))
	return parts.join(", ")

func _sign_int(v: int) -> String:
	return ("+" if v >= 0 else "") + str(v)

# ── vbox helpers ────────────────────────────────────────────────────────────

func _clear(vbox: VBoxContainer) -> void:
	for c in vbox.get_children():
		vbox.remove_child(c)
		c.free()

func _lbl(vbox: VBoxContainer, text: String, wrap: bool = false) -> void:
	var l = Label.new()
	l.text = text
	if wrap:
		l.autowrap = true
		l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	vbox.add_child(l)

func _sep(vbox: VBoxContainer) -> void:
	vbox.add_child(HSeparator.new())

func _spacer(vbox: VBoxContainer) -> void:
	var c = Control.new()
	c.rect_min_size = Vector2(0, 4)
	vbox.add_child(c)

# ── panel builder ───────────────────────────────────────────────────────────

func _make_split_panel(tabs: TabContainer, key: String) -> Dictionary:
	var panel = HBoxContainer.new()
	panel.name = key
	panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	panel.size_flags_vertical = Control.SIZE_EXPAND_FILL
	tabs.add_child(panel)

	var list = ItemList.new()
	list.rect_min_size = Vector2(_LIST_W, 0)
	list.size_flags_vertical = Control.SIZE_EXPAND_FILL
	panel.add_child(list)

	var scroll = ScrollContainer.new()
	scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	panel.add_child(scroll)

	var detail = VBoxContainer.new()
	detail.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	detail.rect_min_size = Vector2(400, 0)
	scroll.add_child(detail)

	return {list = list, detail = detail}

# ── signal handler ──────────────────────────────────────────────────────────

func _on_item_selected(idx: int, key: String) -> void:
	if not _tab_state.has(key):
		return
	var state = _tab_state[key]
	if idx >= state.items.size():
		return
	var item = state.items[idx]
	if item.get("_header", false):
		return
	_clear(state.detail)
	_populate_detail(state.detail, item, key)

func _populate_detail(vbox: VBoxContainer, item: Dictionary, key: String) -> void:
	match key:
		"Guide":         _detail_guide(vbox, item)
		"Technologies":  _detail_tech(vbox, item)
		"Units":         _detail_unit(vbox, item)
		"Buildings":     _detail_building(vbox, item)
		"Resources":     _detail_resource(vbox, item)
		"Civics":        _detail_civic(vbox, item)
		"Promotions":    _detail_promo(vbox, item)
		"Beliefs & Orgs": _detail_belief_org(vbox, item)
		"Societies":     _detail_society(vbox, item)
		"Maps":          _detail_map(vbox, item)

# ── generic data tab ────────────────────────────────────────────────────────

func _add_data_tab(tabs: TabContainer, key: String, items: Array) -> void:
	var panel = _make_split_panel(tabs, key)
	var list = panel.list
	var detail = panel.detail
	_tab_state[key] = {items = items, detail = detail}

	for i in range(items.size()):
		var item = items[i]
		if item.get("_header", false):
			list.add_item("── " + str(item.get("_section", "")) + " ──")
			list.set_item_disabled(i, true)
			list.set_item_selectable(i, false)
		else:
			list.add_item(_fmt_name(item))

	list.connect("item_selected", self, "_on_item_selected", [key])

	# Pre-select first non-header entry.
	for i in range(items.size()):
		if not items[i].get("_header", false):
			list.select(i)
			_on_item_selected(i, key)
			break

# ── data collectors ─────────────────────────────────────────────────────────

func _collect_techs(db) -> Array:
	var items = []
	for era in _ERA_ORDER:
		var era_techs = []
		for id in db.technologies:
			var t = db.technologies[id]
			if str(t.get("era", "")) == era:
				era_techs.append(t)
		if era_techs.empty():
			continue
		era_techs.sort_custom(self, "_sort_by_cost")
		items.append({_header = true, _section = era.capitalize()})
		for t in era_techs:
			items.append(t)
	for id in db.technologies:
		var t = db.technologies[id]
		if not (str(t.get("era", "")) in _ERA_ORDER):
			items.append(t)
	return items

func _collect_units(db) -> Array:
	var items = []
	for cls in _CLASS_ORDER:
		var group = []
		for id in db.units:
			var u = db.units[id]
			if str(u.get("classification", "")) == cls:
				group.append(u)
		if group.empty():
			continue
		group.sort_custom(self, "_sort_by_cost")
		items.append({_header = true, _section = cls.capitalize()})
		for u in group:
			items.append(u)
	return items

func _collect_buildings(db) -> Array:
	var items = []
	var wonders = []
	var nationals = []
	var regulars = []
	for id in db.structures:
		var s = db.structures[id]
		if s.get("is_wonder", false):
			wonders.append(s)
		elif s.get("is_national_wonder", false):
			nationals.append(s)
		else:
			regulars.append(s)
	regulars.sort_custom(self, "_sort_by_cost")
	wonders.sort_custom(self, "_sort_by_cost")
	nationals.sort_custom(self, "_sort_by_cost")
	if not regulars.empty():
		items.append({_header = true, _section = "Buildings"})
		for s in regulars:
			items.append(s)
	if not nationals.empty():
		items.append({_header = true, _section = "National Wonders"})
		for s in nationals:
			items.append(s)
	if not wonders.empty():
		items.append({_header = true, _section = "World Wonders"})
		for s in wonders:
			items.append(s)
	return items

func _collect_resources(db) -> Array:
	var items = []
	var by_type: Dictionary = {}
	for id in db.resources:
		var r = db.resources[id]
		var t = str(r.get("type", "other"))
		if not by_type.has(t):
			by_type[t] = []
		by_type[t].append(r)
	for t in ["strategic", "luxury", "bonus", "other"]:
		if not by_type.has(t):
			continue
		items.append({_header = true, _section = t.capitalize()})
		for r in by_type[t]:
			items.append(r)
	return items

func _collect_civics(db) -> Array:
	var items = []
	var cats = db.policies.get("categories", [])
	var all_policies = db.policies.get("policies", {})
	for cat in cats:
		var group = []
		for id in all_policies:
			var p = all_policies[id]
			if str(p.get("category", "")) == cat:
				group.append(p)
		if group.empty():
			continue
		items.append({_header = true, _section = cat.capitalize()})
		for p in group:
			items.append(p)
	return items

func _collect_promos(db) -> Array:
	var items = []
	var no_prereqs = []
	var has_prereqs = []
	for id in db.promotions:
		var p = db.promotions[id]
		if (p.get("prereqs", []) as Array).empty():
			no_prereqs.append(p)
		else:
			has_prereqs.append(p)
	no_prereqs.sort_custom(self, "_sort_by_name")
	has_prereqs.sort_custom(self, "_sort_by_name")
	if not no_prereqs.empty():
		items.append({_header = true, _section = "Base Promotions"})
		for p in no_prereqs:
			items.append(p)
	if not has_prereqs.empty():
		items.append({_header = true, _section = "Advanced Promotions"})
		for p in has_prereqs:
			items.append(p)
	return items

func _collect_beliefs_orgs(db) -> Array:
	var items = []
	if not db.beliefs.empty():
		items.append({_header = true, _section = "Beliefs"})
		for id in db.beliefs:
			var b = db.beliefs[id].duplicate()
			b["_kind"] = "belief"
			items.append(b)
	if not db.econ_orgs.empty():
		items.append({_header = true, _section = "Economic Organisations"})
		for id in db.econ_orgs:
			var o = db.econ_orgs[id].duplicate()
			o["_kind"] = "org"
			items.append(o)
	return items

func _collect_societies(db) -> Array:
	var socs = db.get_societies()
	var items = []
	var names = socs.keys()
	names.sort()
	for id in names:
		items.append(socs[id])
	return items

func _sort_by_cost(a, b) -> bool:
	return int(a.get("cost", 0)) < int(b.get("cost", 0))

func _sort_by_name(a, b) -> bool:
	return _fmt_name(a) < _fmt_name(b)

# ── detail renderers ────────────────────────────────────────────────────────

func _detail_tech(vbox: VBoxContainer, d: Dictionary) -> void:
	_lbl(vbox, _fmt_name(d))
	_sep(vbox)
	_lbl(vbox, "Era:  " + _fmt(str(d.get("era", "?"))))
	_lbl(vbox, "Cost: %d science" % [d.get("cost", 0)])
	var prereqs_all = d.get("prereqs_all", []) as Array
	var prereqs_any = d.get("prereqs_any", []) as Array
	if prereqs_all.empty() and prereqs_any.empty():
		_lbl(vbox, "Prerequisites: none")
	else:
		if not prereqs_all.empty():
			_lbl(vbox, "Requires (all): " + _join(prereqs_all))
		if not prereqs_any.empty():
			_lbl(vbox, "Requires (any): " + _join(prereqs_any))
	_sep(vbox)
	var units = d.get("unlocks_units", []) as Array
	var structs = d.get("unlocks_structures", []) as Array
	var imps = d.get("unlocks_improvements", []) as Array
	if units.empty() and structs.empty() and imps.empty():
		_lbl(vbox, "Unlocks: nothing specific")
	else:
		if not units.empty():
			_lbl(vbox, "Units:        " + _join(units), true)
		if not structs.empty():
			_lbl(vbox, "Buildings:    " + _join(structs), true)
		if not imps.empty():
			_lbl(vbox, "Improvements: " + _join(imps), true)

func _detail_unit(vbox: VBoxContainer, d: Dictionary) -> void:
	_lbl(vbox, _fmt_name(d))
	_sep(vbox)
	_lbl(vbox, "Classification: " + _fmt(str(d.get("classification", "?"))))
	_lbl(vbox, "Domain:         " + _fmt(str(d.get("domain", "?"))))
	var str_val = int(d.get("base_strength", 0))
	if str_val > 0:
		_lbl(vbox, "Strength:       %d" % [str_val])
	_lbl(vbox, "Movement:       %d" % [int(d.get("movement", 100)) / 100])
	_lbl(vbox, "Cost:           %d production" % [d.get("cost", 0)])
	var upkeep = int(d.get("upkeep", 0))
	_lbl(vbox, "Upkeep:         %s" % ["none" if upkeep == 0 else "%d gold/turn" % upkeep])
	var tech = d.get("tech_required", null)
	_lbl(vbox, "Tech required:  " + ("none" if tech == null else _fmt(str(tech))))
	var res = d.get("resource_required", null)
	if res != null:
		_lbl(vbox, "Resource:       " + _fmt(str(res)))
	var upgrades = d.get("upgrades_to", null)
	if upgrades != null:
		_lbl(vbox, "Upgrades to:    " + _fmt(str(upgrades)))
	var tags = d.get("tags", []) as Array
	if not tags.empty():
		_sep(vbox)
		_lbl(vbox, "Abilities: " + _join(tags), true)
	_sep(vbox)
	var fs = int(d.get("first_strikes", 0))
	if fs > 0:
		_lbl(vbox, "First strikes: %d" % [fs])
	var wd = int(d.get("withdrawal_chance", 0))
	if wd > 0:
		_lbl(vbox, "Withdrawal chance: %d%%" % [wd])
	var tc = int(d.get("transport_capacity", 0))
	if tc > 0:
		_lbl(vbox, "Transport capacity: %d units" % [tc])
	var cc = int(d.get("cargo_capacity", 0))
	if cc > 0:
		_lbl(vbox, "Cargo capacity: %d" % [cc])

func _detail_building(vbox: VBoxContainer, d: Dictionary) -> void:
	_lbl(vbox, _fmt_name(d))
	_sep(vbox)
	if d.get("is_wonder", false):
		_lbl(vbox, "Type: World Wonder")
	elif d.get("is_national_wonder", false):
		_lbl(vbox, "Type: National Wonder")
	_lbl(vbox, "Cost:   %d production" % [d.get("cost", 0)])
	var upkeep = int(d.get("upkeep", 0))
	_lbl(vbox, "Upkeep: %s" % ["none" if upkeep == 0 else "%d gold/turn" % upkeep])
	var tech = d.get("tech_required", null)
	_lbl(vbox, "Tech required: " + ("none" if tech == null else _fmt(str(tech))))
	var res = d.get("resource_required", null)
	if res != null:
		_lbl(vbox, "Resource required: " + _fmt(str(res)))
	var req_bld = d.get("building_req", null)
	if req_bld != null:
		_lbl(vbox, "Requires building: " + _fmt(str(req_bld)))
	var obs = d.get("obsoleted_by", null)
	if obs != null:
		_lbl(vbox, "Obsoleted by: " + _fmt(str(obs)))
	var era = d.get("era", null)
	if era != null:
		_lbl(vbox, "Era: " + _fmt(str(era)))

	var delta = d.get("output_delta", {}) as Dictionary
	var bonuses = PoolStringArray()
	if int(delta.get("food", 0)) != 0:
		bonuses.append(_sign_int(int(delta["food"])) + " food")
	if int(delta.get("production", 0)) != 0:
		bonuses.append(_sign_int(int(delta["production"])) + " production")
	if int(delta.get("commerce", 0)) != 0:
		bonuses.append(_sign_int(int(delta["commerce"])) + " commerce")
	if int(d.get("happiness_bonus", 0)) != 0:
		bonuses.append(_sign_int(int(d["happiness_bonus"])) + " happiness")
	if int(d.get("health_bonus", 0)) != 0:
		bonuses.append(_sign_int(int(d["health_bonus"])) + " health")
	if int(d.get("culture_bonus", 0)) != 0:
		bonuses.append(_sign_int(int(d["culture_bonus"])) + " culture")
	if int(d.get("science_bonus", 0)) != 0:
		bonuses.append(_sign_int(int(d["science_bonus"])) + " science")
	if int(d.get("commerce_bonus", 0)) != 0:
		bonuses.append(_sign_int(int(d["commerce_bonus"])) + "% commerce")
	if int(d.get("production_bonus", 0)) != 0:
		bonuses.append(_sign_int(int(d["production_bonus"])) + "% production")
	if int(d.get("growth_bonus", 0)) != 0:
		bonuses.append(_sign_int(int(d["growth_bonus"])) + "% growth")
	if int(d.get("defence_bonus", 0)) != 0:
		bonuses.append(_sign_int(int(d["defence_bonus"])) + "% city defence")
	if not bonuses.empty():
		_sep(vbox)
		_lbl(vbox, "Bonuses: " + bonuses.join(", "), true)

	var slots = d.get("specialist_slots", {}) as Dictionary
	if not slots.empty():
		_sep(vbox)
		_lbl(vbox, "Specialist slots:")
		for stype in slots:
			_lbl(vbox, "  " + _fmt(stype) + ": %d" % [slots[stype]])

	var effects = d.get("effects", {}) as Dictionary
	if not effects.empty():
		_sep(vbox)
		_lbl(vbox, "Effects:")
		for key in effects:
			_lbl(vbox, "  " + _fmt(key) + ": " + str(effects[key]), true)

func _detail_resource(vbox: VBoxContainer, d: Dictionary) -> void:
	_lbl(vbox, _fmt_name(d))
	_sep(vbox)
	_lbl(vbox, "Type: " + _fmt(str(d.get("type", "?"))))
	var tech = d.get("tech_required", null)
	_lbl(vbox, "Revealed by: " + ("start" if tech == null else _fmt(str(tech))))
	var imp_tech = d.get("improve_tech", null)
	if imp_tech != null:
		_lbl(vbox, "Improve tech: " + _fmt(str(imp_tech)))
	var imp = d.get("improvement_required", null)
	if imp != null:
		_lbl(vbox, "Improvement: " + _fmt(str(imp)))
	var output = d.get("output", {}) as Dictionary
	var bonuses = PoolStringArray()
	if int(output.get("food", 0)) != 0:
		bonuses.append(_sign_int(int(output["food"])) + " food")
	if int(output.get("production", 0)) != 0:
		bonuses.append(_sign_int(int(output["production"])) + " production")
	if int(output.get("commerce", 0)) != 0:
		bonuses.append(_sign_int(int(output["commerce"])) + " commerce")
	if not bonuses.empty():
		_sep(vbox)
		_lbl(vbox, "Tile output: " + bonuses.join(", "))

func _detail_civic(vbox: VBoxContainer, d: Dictionary) -> void:
	_lbl(vbox, _fmt_name(d))
	_sep(vbox)
	_lbl(vbox, "Category: " + _fmt(str(d.get("category", "?"))))
	var tech = d.get("tech_required", null)
	_lbl(vbox, "Requires: " + ("available from start" if tech == null else _fmt(str(tech))))
	_sep(vbox)
	var upkeep = int(d.get("upkeep_modifier", 0))
	if upkeep != 0:
		_lbl(vbox, "Unit upkeep modifier: " + _sign_int(upkeep) + "%")
	var anger = int(d.get("anger_modifier", 0))
	if anger != 0:
		_lbl(vbox, "Anger modifier: " + _sign_int(anger))
	var transition = int(d.get("transition_turns", 0))
	if transition > 0:
		_lbl(vbox, "Anarchy on switch: %d turns" % [transition])
	else:
		_lbl(vbox, "Anarchy on switch: none")
	var slider_min = int(d.get("slider_min_research", 0))
	if slider_min > 0:
		_lbl(vbox, "Min research slider: %d%%" % [slider_min])
	var effects = d.get("effects", {}) as Dictionary
	if not effects.empty():
		_sep(vbox)
		_lbl(vbox, "Effects:")
		for key in effects:
			_lbl(vbox, "  " + _fmt(key) + ": " + str(effects[key]), true)

func _detail_promo(vbox: VBoxContainer, d: Dictionary) -> void:
	_lbl(vbox, _fmt_name(d))
	_sep(vbox)
	_lbl(vbox, "Applies to: " + _fmt(str(d.get("applies_to", "all"))))
	var prereqs = d.get("prereqs", []) as Array
	_lbl(vbox, "Prereqs: " + _join(prereqs))
	_sep(vbox)
	# Render every mechanical field generically; skip metadata fields.
	var skip = ["id", "name", "applies_to", "prereqs"]
	for key in d:
		if key in skip:
			continue
		var val = d[key]
		if typeof(val) == TYPE_BOOL:
			if bool(val):
				_lbl(vbox, _fmt(key))
		elif typeof(val) == TYPE_INT or typeof(val) == TYPE_REAL:
			var v = int(val)
			if v != 0:
				_lbl(vbox, _fmt(key) + ": " + (_sign_int(v) + "%" if key.ends_with("_bonus") or key.ends_with("_chance") else str(v)))
		else:
			_lbl(vbox, _fmt(key) + ": " + str(val), true)

func _detail_belief_org(vbox: VBoxContainer, d: Dictionary) -> void:
	_lbl(vbox, _fmt_name(d))
	_sep(vbox)
	if d.get("_kind", "") == "belief":
		var found_tech = d.get("founding_tech", null)
		_lbl(vbox, "Founded by: " + ("special condition" if found_tech == null else _fmt(str(found_tech))))
		_lbl(vbox, "Base spread chance: %d%%" % [d.get("spread_chance_base", 0)])
		var hss = d.get("holy_site_structure", null)
		if hss != null:
			_lbl(vbox, "Holy site structure: " + _fmt(str(hss)))
		_sep(vbox)
		var skip = ["id", "name", "_kind", "founding_prereq", "founding_tech", "spread_chance_base", "holy_site_structure"]
		for key in d:
			if key in skip:
				continue
			_lbl(vbox, _fmt(key) + ": " + str(d[key]))
	else:
		var inputs = d.get("input_resources", []) as Array
		if not inputs.empty():
			_lbl(vbox, "Input resources: " + _join(inputs))
		_lbl(vbox, "Spread cost: %d gold" % [d.get("spread_cost", 0)])
		_lbl(vbox, "Base spread chance: %d%%" % [d.get("spread_chance_base", 0)])
		var delta = d.get("output_delta", {}) as Dictionary
		var bonuses = PoolStringArray()
		for k in ["food", "production", "commerce"]:
			if int(delta.get(k, 0)) != 0:
				bonuses.append(_sign_int(int(delta[k])) + " " + k)
		if not bonuses.empty():
			_sep(vbox)
			_lbl(vbox, "Per-city output: " + bonuses.join(", "))

func _detail_society(vbox: VBoxContainer, d: Dictionary) -> void:
	_lbl(vbox, _fmt_name(d))
	_sep(vbox)
	var leader = d.get("leader_name", d.get("leader_id", null))
	if leader != null:
		_lbl(vbox, "Leader: " + str(leader))
	var desc = str(d.get("description", ""))
	if desc != "":
		_lbl(vbox, desc, true)
	_sep(vbox)
	var traits = d.get("traits", []) as Array
	_lbl(vbox, "Traits: " + _join(traits))
	var uu = d.get("unique_unit", null)
	if uu != null:
		_lbl(vbox, "Unique unit: " + _fmt(str(uu)))
	var ub = d.get("unique_building", null)
	if ub != null:
		_lbl(vbox, "Unique building: " + _fmt(str(ub)))
	_lbl(vbox, "Starting gold: %d" % [d.get("starting_gold", 0)])
	var st = d.get("starting_techs", []) as Array
	if not st.empty():
		_lbl(vbox, "Starting techs: " + _join(st))
	if not traits.empty():
		_sep(vbox)
		_lbl(vbox, "Trait details:")
		var db = _facade._db
		var all_traits = db.leaders_traits.get("traits", {})
		for trait_id in traits:
			if all_traits.has(trait_id):
				var td = all_traits[trait_id]
				_spacer(vbox)
				_lbl(vbox, _fmt_name(td))
				for key in td:
					if key in ["id", "name"]:
						continue
					var val = td[key]
					if typeof(val) == TYPE_ARRAY:
						if not (val as Array).empty():
							_lbl(vbox, "  " + _fmt(key) + ": " + _join(val as Array), true)
					elif typeof(val) == TYPE_INT or typeof(val) == TYPE_REAL:
						if int(val) != 0:
							_lbl(vbox, "  " + _fmt(key) + ": " + _sign_int(int(val)))
					else:
						_lbl(vbox, "  " + _fmt(key) + ": " + str(val), true)

func _detail_map(vbox: VBoxContainer, d: Dictionary) -> void:
	_lbl(vbox, _fmt_name(d))
	_sep(vbox)
	var desc = str(d.get("description", ""))
	if desc != "":
		_lbl(vbox, desc, true)
	_sep(vbox)
	_lbl(vbox, "Category: " + _fmt(str(d.get("category", "?"))))
	_lbl(vbox, "Land fraction: ~%d%%" % [d.get("land_fraction", 0)])
	var mtn = int(d.get("mountain_chance", 0))
	if mtn > 0:
		_lbl(vbox, "Mountain chance: %d%%" % [mtn])
	var hills = int(d.get("hills_chance", 0))
	if hills > 0:
		_lbl(vbox, "Hills chance: %d%%" % [hills])
	var forest = int(d.get("forest_chance", 0))
	if forest > 0:
		_lbl(vbox, "Forest chance: %d%%" % [forest])
	var jungle = int(d.get("jungle_chance", 0))
	if jungle > 0:
		_lbl(vbox, "Jungle chance: %d%%" % [jungle])

# ── guide tab ───────────────────────────────────────────────────────────────

func _add_guide_tab(tabs: TabContainer) -> void:
	var sections = _guide_sections()
	var items = []
	for s in sections:
		items.append({_guide_title = s[0], content = s[1]})

	var panel = _make_split_panel(tabs, "Guide")
	var list = panel.list
	var detail = panel.detail
	_tab_state["Guide"] = {items = items, detail = detail}

	for item in items:
		list.add_item(str(item._guide_title))

	list.connect("item_selected", self, "_on_item_selected", ["Guide"])

	if not items.empty():
		list.select(0)
		_on_item_selected(0, "Guide")

func _detail_guide(vbox: VBoxContainer, item: Dictionary) -> void:
	_lbl(vbox, str(item._guide_title))
	_sep(vbox)
	for line in (item.content as Array):
		if str(line) == "":
			_spacer(vbox)
		else:
			_lbl(vbox, str(line), true)

func _guide_sections() -> Array:
	return [
		["Navigation & Controls", [
			"Main Controls",
			"Left-click a tile — select your unit/city there, or inspect an empty/foreign tile",
			"Right-click a tile — move selected unit(s) or attack enemy at that tile",
			"",
			"Keyboard Shortcuts",
			"E — End Turn",
			"N — Next idle unit",
			"B — Next idle worker",
			"C — Centre camera on selection",
			"F1 — Encyclopedia",
			"F2 — Technology tree",
			"F3 — Civics / Policy screen",
			"F4 — Diplomacy screen",
			"F5 — Quick Save",
			"F9 — Quick Load",
			"Escape — Pause menu (Resume / Save / Load / New Game / Quit)",
			"",
			"Advisor Bar (top of HUD)",
			"A row of buttons opens full-screen info panels: Encyclopedia, Tech Tree,",
			"Civics, Diplomacy, Finance, Military, Domestic Advisor, Espionage,",
			"Religion, Corporation, Turn Log, Victory Progress, Options.",
		]],
		["Economy Sliders", [
			"Your empire's commerce output is divided four ways. The sliders always total 100.",
			"",
			"Finance       — Gold income added to treasury each turn",
			"Research      — Science progress toward the current technology",
			"Culture       — Cultural output; drives city border expansion",
			"Intelligence  — Espionage points accumulated against rival alliances",
			"",
			"Adjust from the slider panel on the HUD or via the Options screen.",
			"Changing one slider redistributes the difference across the others.",
		]],
		["Cities", [
			"Founding",
			"Select a Settler and use 'Found City' in the selection panel.",
			"Best sites: grassland or plains nearby, fresh water (river/coast/oasis),",
			"resources your tech can improve, not too close to other cities.",
			"",
			"City Screen  (double-click a city)",
			"Production queue — build units, structures, or endgame projects one at a time.",
			"Worked tiles — city works a number of tiles equal to its population (3-ring radius).",
			"Click a tile to lock or unlock it; locked tiles override Automate.",
			"Automate Citizens — the AI picks tiles, favouring food or production.",
			"Specialists — assign idle citizens to built specialist slots for Great Person points.",
			"Rush Production — spend gold to instantly finish part of the current item.",
			"",
			"Growth",
			"Each turn food surplus accumulates. Reaching the threshold adds +1 population.",
			"Disorder (discontented citizens ≥ effective workers) zeroes production and food.",
			"",
			"Culture and Borders",
			"Cities produce culture each turn; accumulated culture expands the city's border,",
			"claiming nearby tiles. A tile belongs to the player with the highest culture there.",
		]],
		["Units", [
			"Selection",
			"Left-click a tile with your units to select them.",
			"Clicking the same tile again cycles to the next unit if multiple are stacked.",
			"The selection panel shows health, movement, and available actions.",
			"On a tile with both units and your city, clicking cycles units then the city.",
			"",
			"Movement",
			"Right-click a destination tile to move the selected unit(s) there.",
			"Multi-turn paths: if movement runs out, the order carries over to the next turn.",
			"N jumps to the next idle unit.",
			"",
			"Stacks",
			"Multiple units can share one tile. Right-click a friendly unit tile to merge into it.",
			"'Select all' in the selection panel selects every unit on the current tile.",
			"",
			"Actions",
			"Fortify          — entrench, gaining a defence bonus each turn it stays",
			"Sleep            — rest until manually woken; removed from idle-unit cycle",
			"Found City        — (Settler only) found a city on this tile",
			"Build Improvement — (Worker) build a farm, mine, road, etc.",
			"Spread Belief     — (Missionary) spread state religion to a city",
			"Perform GP Action — (Great Person) use the unit's special ability",
			"Disband           — remove unit permanently",
			"",
			"Workers",
			"Assign them via action buttons, or toggle Automate to let the AI decide.",
		]],
		["Combat", [
			"Initiating",
			"Right-click an enemy tile while you have a unit selected.",
			"The attacker moves toward the target; only one combat resolves per order.",
			"",
			"Resolution",
			"Each round: effective strength is calculated for both sides (base strength",
			"plus promotions, terrain, fortification, and health). Odds are derived",
			"proportionally and the RNG picks which side takes damage.",
			"Combat ends when one side is destroyed, retreats, or a round limit is hit.",
			"",
			"First strikes — some units attack before the defender can respond early on.",
			"Spillover damage — siege units deal partial damage to units behind the target.",
			"Flanking — fast units can hit multiple units in a stack.",
			"",
			"Experience and Promotions",
			"Surviving units gain XP. At thresholds you choose a promotion — a permanent",
			"combat bonus. Open the Military advisor to review eligibility.",
			"",
			"War Fatigue",
			"Prolonged war accumulates fatigue on both alliances, raising unhappiness.",
			"Fatigue decays once fighting stops.",
		]],
		["Research", [
			"Tech Tree  (F2)",
			"Technologies are arranged in a prerequisite graph across seven eras:",
			"Ancient → Classical → Medieval → Renaissance → Industrial → Modern → Future.",
			"Researching a technology unlocks units, buildings, improvements, and game mechanics.",
			"",
			"Research Cost",
			"Scales with the Pace setting (slower = higher cost).",
			"Each owned prerequisite gives a 10% discount.",
			"Each other player who already knows it gives a 5% discount (capped at 25%).",
			"",
			"Funding",
			"The Research slider sets the fraction of commerce going to science each turn.",
			"Progress is shown in the Research bar at the top of the screen.",
			"",
			"Eras",
			"Advancing to a new era happens automatically when you research a tech tagged to it.",
			"You receive a notification when it happens.",
		]],
		["Civics & Policies", [
			"Civics Screen  (F3)",
			"Policies are grouped into five categories: Government, Legal, Labor, Economic,",
			"Religion. Each category lets you adopt one policy at a time.",
			"Switching costs an anarchy period (no research, culture, or production).",
			"",
			"Effects",
			"Each policy carries passive effects applied every turn: modifiers to commerce,",
			"treasury, unit upkeep, research, happiness, health, production bonuses,",
			"specialist rates, and combat bonuses.",
			"",
			"Transition",
			"When you switch policies in a category, your empire enters anarchy for the",
			"number of turns shown. Plan switches carefully — nothing accumulates during it.",
		]],
		["Diplomacy", [
			"Diplomacy Screen  (F4)",
			"Shows each rival's stance toward you and the options available.",
			"",
			"Declare war / Make peace  — acts at the alliance level; all members join",
			"Open borders            — units may pass through each other's territory",
			"Trade                   — exchange gold, resources, or technologies",
			"Alliance                — military alliance; shared research, unified war",
			"Subjugation             — one alliance becomes a client state of the other",
			"",
			"Relationships deteriorate from aggression and improve slowly under peace.",
			"",
			"United Nations",
			"The UN wonder enables the Diplomatic victory condition: an alliance that wins",
			"the world assembly election with 67% of the weighted vote wins the game.",
		]],
		["Beliefs & Economic Orgs", [
			"Beliefs (Religions)",
			"The first player to meet a founding condition (usually researching a specific tech)",
			"founds a belief. Once founded it spreads to other cities — passively or via Missionary.",
			"Adopting a state religion (in Civics → Religion) gives passive bonuses;",
			"changing it triggers anarchy.",
			"",
			"Economic Organisations",
			"Founded by a Great Merchant or specific Great Person action.",
			"Like beliefs, organisations spread and provide per-city economic bonuses.",
			"Maintaining an organisation costs treasury each turn.",
		]],
		["Great People", [
			"Specialists in your cities generate Great Person (GP) points each turn.",
			"When a city's total crosses the current threshold, a Great Person is born.",
			"",
			"Great Scientist  — Scientist specialists  — instant technology, boost research",
			"Great Engineer   — Engineer specialists   — rush production, construct wonders",
			"Great Merchant   — Merchant specialists   — trade route, found economic org",
			"Great Artist     — Artist specialists     — trigger Cultural Golden Age",
			"Great Prophet    — Priest specialists     — found/spread a belief, holy structures",
			"Great General    — Combat XP (all units)  — combat leader bonus for stacked units",
			"",
			"Use a Great Person's action from the selection panel when on a suitable tile.",
			"",
			"Golden Age",
			"Certain Great Person actions (and accumulating several of them) trigger a Golden Age:",
			"a fixed number of turns where all worked tiles produce extra output.",
			"War fatigue is frozen during a Golden Age.",
		]],
		["Eras", [
			"Seven eras unlock progressively stronger units, buildings, and mechanics.",
			"Era advancement triggers automatically when you research a tech tagged to that era.",
			"",
			"Ancient      — Settlers, Warriors, basic improvements",
			"Classical    — Swordsmen, Catapults, Libraries, Aqueducts",
			"Medieval     — Knights, Castles, Universities",
			"Renaissance  — Cannons, Caravels, Printing Press",
			"Industrial   — Rifles, Factories, Steam power",
			"Modern       — Infantry, Tanks, Flight, Computers",
			"Future       — Advanced units, Space Race projects",
			"",
			"Entering a new era produces a notification and may immediately unlock new build options.",
		]],
		["Wild Forces & Raiders", [
			"Unclaimed territory spawns raiders — AI-controlled units (owner: Wild Forces)",
			"that wander and attack cities and units they encounter.",
			"Raiders are not controlled by any player.",
			"",
			"They are a persistent early-game threat.",
			"Garrison your cities with at least one warrior unit and keep a mobile force nearby.",
			"",
			"At higher difficulties, raiders have early free combat wins removed,",
			"making them more dangerous in the opening turns.",
		]],
		["Save & Load", [
			"Quick Save   — F5 — overwrites quicksave.sav immediately",
			"Quick Load   — F9 — restores the last quick save immediately",
			"Named save   — Escape → Save — pick a slot or name a new one",
			"Load (pause) — Escape → Load — browse saved games",
			"Load (title) — Title screen → Load Game",
			"",
			"Save files are stored in your user data folder.",
			"The headless multiplayer server autosaves after every turn.",
		]],
		["Multiplayer", [
			"Joining a Game",
			"Title screen → Multiplayer → enter host address, port (default 9080), and name.",
			"When it is your turn you receive the game state, make your moves,",
			"and click End Turn to submit.",
			"",
			"Hosting In-Game",
			"Title screen → Multiplayer Server → set port, player count, AI slots, save file.",
			"Choose New Game (runs normal setup) or Load a save → Start.",
			"",
			"Headless Server",
			"For always-on hosting without a GUI, run from a terminal:",
			"  ./run_server.sh --save=game.sav --players=3 --ai=1 --port=9080",
			"",
			"--save=<file>   Save-file path (required). Autosaves every turn.",
			"--players=<n>   Total players including AI.",
			"--ai=<n>        AI-controlled player count.",
			"--port=<n>      Port to listen on (default 9080).",
			"--load=<file>   Resume from a saved game.",
			"--world=<size>  World size ID (duel/tiny/small/standard/large/huge).",
			"--map=<type>    Map type ID.",
		]],
		["Victory Conditions", [
			"Select which conditions are active at game setup.",
			"The game ends immediately when any alliance achieves an active condition.",
			"",
			"Conquest",
			"Eliminate every other alliance. No enemy settlements or units may remain.",
			"",
			"Domination",
			"Hold at least 66% of all land tiles and 66% of total population simultaneously.",
			"",
			"Space Race",
			"Complete all seven spaceship stages in order.",
			"Requires the Apollo Program wonder to be built first.",
			"",
			"Cultural",
			"Bring three of your cities to Legendary culture (50,000 points each).",
			"The three cities do not need to reach Legendary simultaneously.",
			"",
			"Diplomatic",
			"Win the United Nations general election with at least 67% of the weighted vote.",
			"The UN wonder must be built for this condition to become available.",
			"",
			"Time",
			"When the turn limit is reached, the alliance with the highest score wins.",
			"Score is a weighted sum of land tiles held, total population, and techs researched.",
		]],
	]

# ── maps tab ────────────────────────────────────────────────────────────────

func _add_maps_tab(tabs: TabContainer, db) -> void:
	var items = []
	for id in db.map_types:
		items.append(db.map_types[id])
	items.sort_custom(self, "_sort_by_name")

	var panel = _make_split_panel(tabs, "Maps")
	var list = panel.list
	var detail = panel.detail
	_tab_state["Maps"] = {items = items, detail = detail}

	for item in items:
		list.add_item(_fmt_name(item))

	list.connect("item_selected", self, "_on_item_selected", ["Maps"])

	if not items.empty():
		list.select(0)
		_on_item_selected(0, "Maps")

# ── reference tab (world sizes + keyboard) ──────────────────────────────────

func _add_reference_tab(tabs: TabContainer, db) -> void:
	var outer = VBoxContainer.new()
	outer.name = "Reference"
	outer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	outer.size_flags_vertical = Control.SIZE_EXPAND_FILL
	tabs.add_child(outer)

	var scroll = ScrollContainer.new()
	scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	outer.add_child(scroll)

	var vbox = VBoxContainer.new()
	vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(vbox)

	_lbl(vbox, "World Sizes")
	_sep(vbox)
	var size_order = ["duel", "tiny", "small", "standard", "large", "huge"]
	for id in size_order:
		if not db.world_sizes.has(id):
			continue
		var ws = db.world_sizes[id]
		_lbl(vbox, "%-12s %d × %d  (suggested players: %d)" % [
			_fmt_name(ws), ws.get("width", 0), ws.get("height", 0),
			ws.get("players_suggested", 0)
		])
	_spacer(vbox)

	_lbl(vbox, "Victory Conditions")
	_sep(vbox)
	for id in db.win_conditions:
		var wc = db.win_conditions[id]
		var name_str = _fmt_name(wc)
		var note = str(wc.get("notes", ""))
		if note != "":
			_lbl(vbox, name_str + " — " + note, true)
		else:
			_lbl(vbox, name_str)
	_spacer(vbox)

	_lbl(vbox, "Keyboard Reference")
	_sep(vbox)
	var keys = [
		["E",       "End Turn"],
		["N",       "Next idle unit"],
		["B",       "Next idle worker"],
		["C",       "Centre camera on selection"],
		["F1",      "Encyclopedia"],
		["F2",      "Technology tree"],
		["F3",      "Civics / Policy screen"],
		["F4",      "Diplomacy screen"],
		["F5",      "Quick Save"],
		["F9",      "Quick Load"],
		["Escape",  "Pause menu"],
	]
	for pair in keys:
		_lbl(vbox, "%-10s — %s" % [pair[0], pair[1]])
