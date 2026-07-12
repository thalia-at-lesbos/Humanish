# Humanish — a turn-based 4X strategy game.
# Copyright (C) 2026 thalia-at-lesbos
# SPDX-License-Identifier: GPL-3.0-or-later
#
# This program is free software: you can redistribute it and/or modify it
# under the terms of the GNU General Public License as published by the Free
# Software Foundation, either version 3 of the License, or (at your option)
# any later version. See the LICENSE file for the full text and warranty
# disclaimer.

class_name TextGen
extends Reference

# Centralized tooltip and breakdown text generation (§9 of ui-design).
# All human-readable explanations of game state live here so that displayed
# text always matches actual computation. The host calls SimFacade.widget_help()
# which delegates to this class — nothing in scenes/ computes game text itself.

static func widget_help(widget: Dictionary, gs: GameState, db: DataDB) -> String:
    var wtype: int = int(widget.get("type", -1))
    var d1: int = int(widget.get("data1", -1))
    match wtype:
        IDs.WidgetType.UNIT_MODEL, IDs.WidgetType.UNIT_LIST:
            return _help_unit(d1, gs, db)
        IDs.WidgetType.CITY_SCROLLER:
            return _help_city(d1, gs, db)
        IDs.WidgetType.TECH_NODE, IDs.WidgetType.RESEARCH:
            return _help_tech(str(widget.get("tech_id", "")), gs, db)
        IDs.WidgetType.HELP_FINANCE:
            return _help_finance(d1, gs, db)
        IDs.WidgetType.HELP_PRODUCTION:
            return _help_production(d1, gs, db)
        IDs.WidgetType.HELP_PROMOTION:
            return _help_promotion(str(widget.get("promo_id", "")), db)
        IDs.WidgetType.HELP_CONTENTMENT:
            return _help_contentment(d1, gs, db)
        IDs.WidgetType.HELP_WELLBEING:
            return _help_wellbeing(d1, gs, db)
        IDs.WidgetType.HELP_CULTURE:
            return _help_culture(d1, gs, db)
    return ""

# ── Unit ─────────────────────────────────────────────────────────────────────

static func _help_unit(unit_id: int, gs: GameState, db: DataDB) -> String:
    var u: Unit = gs.get_unit(unit_id)
    if u == null:
        return "(no unit)"
    var udata: Dictionary = db.get_unit(u.unit_type_id)
    var result: String = u.unit_type_id + "\n"
    result += "Strength: " + str(u.base_strength) + "\n"
    result += "Health: " + str(u.health) + "/100\n"
    result += "Movement: " + str(u.movement_left) + "/" + str(u.movement_total) + "\n"
    if not u.promotions.empty():
        result += "Promotions: " + _join(u.promotions) + "\n"
    var domain: String = str(udata.get("domain", "land"))
    result += "Domain: " + domain + "\n"
    result += "State: " + unit_state_text(u) + "\n"
    return result

# A short human-readable description of what a unit is currently doing, for the
# selection / unit-info pane (§7). Reflects standing orders (build, go-to) and
# stances (fortified, sleeping, sentry, healing); falls back to whether the unit
# still has moves this turn.
static func unit_state_text(u) -> String:
    if u == null:
        return ""
    if u.building_improvement != "":
        var t: int = u.build_turns_left
        return "Building " + u.building_improvement.capitalize() \
            + ((" (" + str(t) + " turn(s) left)") if t > 0 else "")
    if u.clearing_feature != "":
        var ct: int = u.build_turns_left
        return "Clearing " + u.clearing_feature.capitalize() \
            + ((" (" + str(ct) + " turn(s) left)") if ct > 0 else "")
    if u.goto_x >= 0:
        return "Moving to (" + str(u.goto_x) + ", " + str(u.goto_y) + ")"
    if u.is_sleep_until_healed:
        return "Sleeping until healed"
    if u.is_fortify_until_healed:
        return "Fortified until healed"
    if u.is_sleeping:
        return "Sleeping"
    if u.is_fortified:
        return "Fortified"
    if u.is_exploring:
        return "Exploring"
    if u.is_sentry:
        return "On sentry"
    if u.is_patrolling:
        return "Patrolling"
    if u.is_healing:
        return "Healing"
    if u.has_moved or u.movement_left <= 0:
        return "Done"
    return "Active"

# ── City ─────────────────────────────────────────────────────────────────────

static func _help_city(city_id: int, gs: GameState, db: DataDB) -> String:
    var s: Settlement = gs.get_settlement(city_id)
    if s == null:
        return "(no city)"
    var result: String = s.name + "\n"
    result += "Population: " + str(s.population) + "\n"
    result += "Food: " + str(s.output_food) + "/turn"
    var surplus: int = s.output_food - s.population
    if surplus >= 0:
        result += " (+" + str(surplus) + " surplus)\n"
    else:
        result += " (" + str(surplus) + " deficit)\n"
    result += "Production: " + str(s.output_production) + "/turn\n"
    result += "Commerce: " + str(s.output_commerce) + "/turn\n"
    if not s.production_queue.empty():
        var item: Dictionary = s.production_queue[0]
        result += "Building: " + str(item.get("id", "?")) + "\n"
    return result

# ── Technology ───────────────────────────────────────────────────────────────

static func _help_tech(tech_id: String, gs: GameState, db: DataDB) -> String:
    if tech_id == "":
        return "(no tech)"
    var tech: Dictionary = db.get_technology(tech_id)
    if tech.empty():
        return "(unknown tech: " + tech_id + ")"
    var result: String = tech_id + "\n"
    result += "Cost: " + str(int(tech.get("cost", 0))) + " research\n"
    var prereqs: Array = tech.get("prereqs_all", [])
    if not prereqs.empty():
        result += "Requires: " + _join(prereqs) + "\n"
    var prereqs_any: Array = tech.get("prereqs_any", [])
    if not prereqs_any.empty():
        result += "Requires any: " + _join(prereqs_any) + "\n"
    var unlocks_u: Array = tech.get("unlocks_units", [])
    var unlocks_s: Array = tech.get("unlocks_structures", [])
    var unlocks_i: Array = tech.get("unlocks_improvements", [])
    if not unlocks_u.empty():
        result += "Unlocks units: " + _join(unlocks_u) + "\n"
    if not unlocks_s.empty():
        result += "Unlocks structures: " + _join(unlocks_s) + "\n"
    if not unlocks_i.empty():
        result += "Unlocks improvements: " + _join(unlocks_i) + "\n"
    return result

# ── Finance breakdown ─────────────────────────────────────────────────────────

static func _help_finance(player_id: int, gs: GameState, db: DataDB) -> String:
    var p: Player = gs.get_player(player_id)
    if p == null:
        return "(no player)"
    var unit_upkeep: int = 0
    for u in gs.units:
        if u.owner_player_id == player_id:
            var udata: Dictionary = db.get_unit(u.unit_type_id)
            unit_upkeep += int(udata.get("upkeep", 0))
    var commerce_income: int = 0
    for s in gs.settlements:
        if s.owner_player_id == player_id:
            commerce_income += Fixed.scale(s.output_commerce, p.slider_finance)
    var result: String = "Finance Breakdown\n"
    result += "Treasury: " + str(p.treasury) + " gold\n"
    result += "Commerce income: +" + str(commerce_income) + "\n"
    result += "Unit upkeep: -" + str(unit_upkeep) + "\n"
    var infl: int = TurnEngine.inflation_rate(gs)
    if infl > 0:
        result += "Inflation: +" + str(infl) + "% on expenses\n"
    result += "Net per turn: " + str(commerce_income - unit_upkeep) + "\n"
    result += "Finance slider: " + str(p.slider_finance) + "%\n"
    return result

# ── Production breakdown ──────────────────────────────────────────────────────

static func _help_production(city_id: int, gs: GameState, db: DataDB) -> String:
    var s: Settlement = gs.get_settlement(city_id)
    if s == null:
        return "(no city)"
    var result: String = "Production: " + s.name + "\n"
    result += str(s.output_production) + " hammers/turn\n"
    result += "Stored: " + str(s.production_store) + " hammers\n"
    if not s.production_queue.empty():
        var item: Dictionary = s.production_queue[0]
        var itype: String = str(item.get("type", ""))
        var iid: String = str(item.get("id", ""))
        var cost: int = 0
        if itype == "unit":
            cost = int(db.get_unit(iid).get("cost", 0))
        elif itype == "structure":
            cost = int(db.get_structure(iid).get("cost", 0))
        result += "Building: " + iid + " (cost " + str(cost) + ")\n"
        var remaining: int = cost - s.production_store if cost > s.production_store else 0
        if s.output_production > 0:
            var turns: int = (remaining + s.output_production - 1) / s.output_production
            result += "Turns remaining: " + str(turns) + "\n"
    return result

# ── Promotion ─────────────────────────────────────────────────────────────────

static func _help_promotion(promo_id: String, db: DataDB) -> String:
    if promo_id == "":
        return "(no promotion)"
    var promo: Dictionary = db.get_promotion(promo_id)
    if promo.empty():
        return "(unknown promotion: " + promo_id + ")"
    var name: String = str(promo.get("name", promo_id))
    var result: String = name + "\n"
    if promo.has("combat_strength_bonus"):
        result += "Strength bonus: +" + str(int(promo.get("combat_strength_bonus"))) + "%\n"
    if promo.has("healing_bonus"):
        result += "Healing bonus: +" + str(int(promo.get("healing_bonus"))) + "\n"
    if promo.has("withdrawal_chance"):
        result += "Withdrawal chance: +" + str(int(promo.get("withdrawal_chance"))) + "%\n"
    var prereqs: Array = promo.get("prereqs", [])
    if not prereqs.empty():
        result += "Requires: " + _join(prereqs) + "\n"
    return result

# ── Contentment breakdown ─────────────────────────────────────────────────────

static func _help_contentment(city_id: int, gs: GameState, db: DataDB) -> String:
    var s: Settlement = gs.get_settlement(city_id)
    if s == null:
        return "(no city)"
    var result: String = "Contentment: " + s.name + "\n"
    result += "Positive sentiment: +" + str(s.positive_sentiment) + "\n"
    result += "Negative sentiment: -" + str(s.negative_sentiment) + "\n"
    result += "Discontented citizens: " + str(s.discontented) + "/" + str(s.population) + "\n"
    if s.in_disorder:
        result += "Status: IN DISORDER\n"
    else:
        result += "Status: content\n"
    return result

# ── Wellbeing breakdown ───────────────────────────────────────────────────────

static func _help_wellbeing(city_id: int, gs: GameState, db: DataDB) -> String:
    var s: Settlement = gs.get_settlement(city_id)
    if s == null:
        return "(no city)"
    var result: String = "Wellbeing: " + s.name + "\n"
    result += "Healthy: +" + str(s.wellbeing_positive) + "\n"
    result += "Unhealthy: -" + str(s.wellbeing_negative) + "\n"
    result += "Deficit: " + str(s.wellbeing_deficit) + "\n"
    return result

# ── Culture breakdown ─────────────────────────────────────────────────────────

static func _help_culture(city_id: int, gs: GameState, db: DataDB) -> String:
    var s: Settlement = gs.get_settlement(city_id)
    if s == null:
        return "(no city)"
    var result: String = "Culture: " + s.name + "\n"
    result += "Accumulated: " + str(s.culture_total) + "\n"
    result += "Border ring: " + str(s.culture_ring) + "\n"
    result += "Rate: " + str(s.output_commerce) + "/turn (via commerce)\n"
    return result

# ── Helpers ───────────────────────────────────────────────────────────────────

static func _join(arr: Array, sep: String = ", ") -> String:
    var parts: PoolStringArray = PoolStringArray()
    for item in arr:
        parts.append(str(item))
    return sep.join(parts)
