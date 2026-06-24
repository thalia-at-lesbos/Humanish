# Humanish — a turn-based 4X strategy game.
# Copyright (C) 2026 thalia-at-lesbos
# SPDX-License-Identifier: GPL-3.0-or-later
#
# This program is free software: you can redistribute it and/or modify it
# under the terms of the GNU General Public License as published by the Free
# Software Foundation, either version 3 of the License, or (at your option)
# any later version. See the LICENSE file for the full text and warranty
# disclaimer.

class_name Quests

# Multi-turn quest tracking subsystem (§4 of the event-subsystem plan). A quest is a
# multi-turn goal: a per-player step ARMS an eligible quest (its prereq holds, it is in
# this game's roster, it is not already active/completed for the player), the player
# works toward an AIM over many turns without violating a CONSTRAINT, and on success a
# REWARD is queued (reusing the §9 event effect verbs). Violating the constraint DROPS
# the quest.
#
# This module is a pure static sim module read by TurnEngine (a Quest player-step phase
# mirroring the Events phase). It REUSES, never duplicates:
#   * the event prereq vocabulary — quest `prereq` is evaluated via Events.prereq_holds;
#   * the event effect verbs — quest rewards are applied via Events.apply_effects; and
#   * the event pending-choice machinery — a 3-choice reward is parked into
#     gs.pending_event_choices with a synthetic "quest:<id>" event_id, so the existing
#     SimFacade popup/resolve path surfaces and resolves it unchanged.
#
# Determinism: every stochastic draw goes through gs.rng in fixed (sorted-id) order,
# exactly like Events. Arming draws the per-game `active` roll + a weighted pick;
# evaluation and reward application draw no RNG (aims/constraints are pure reads).
#
# State: GameState.active_quests, each a record:
#   {quest_id:String, player_id:int, start_turn:int, progress:int,
#    snapshot:{<int key>:<int>...}}
# `progress` is a cheap cached count for the current aim; `snapshot` captures a baseline
# the aim/constraint may diff against ("cities that did NOT have the structure when the
# quest armed", "the state religion held at arming", a trigger settlement id, ...). Both
# are coerced back to int on deserialize (the JSON float/string-key gotcha) — see
# GameState.deserialize.

# ── Aim / constraint kind registry ─────────────────────────────────────────────────
#
# Aim kinds (dispatched in _aim_progress / _aim_complete) the full §4 catalogue needs:
#   build_count            — build N of a structure (some count as >1, e.g. cathedral=4)
#                            [IMPLEMENTED — the Classic Literature slice]
#   build_units            — own N standing units of one or more unit types (chariots,
#                            swordsmen, musketmen, …)                       [IMPLEMENTED]
#   build_fleet            — own a specific fleet composition: each named unit type at
#                            its own threshold, ALL required (Overwhelm)    [IMPLEMENTED]
#   cities_on_landmasses   — own cities spread over N distinct landmasses (Blessed Sea):
#                            land tiles flood-filled into connected masses  [IMPLEMENTED]
#   conquer_resource       — control a tile carrying one of the named resources (Greed)
#                                                                           [IMPLEMENTED]
#   own_corp_resources     — access every input resource of the player's corporation
#                            (Hostile Takeover)                            [IMPLEMENTED]
#   spread_corp            — spread the player's corporation to N new member cities
#                            since arming (Corporate Expansion)            [IMPLEMENTED]
#   control_named_tile     — own a settlement on a tile matching a spec (generic;
#                            no shipped quest uses it but the kind is live) [IMPLEMENTED]
#   conquer_holy_city      — hold the holy city of a religion (Crusade). The engine has
#                            no holy-city *settlement* model (founded_beliefs records
#                            only the founder player, holy_site_structure is never
#                            placed), so this returns no progress and Crusade ships
#                            disabled (active:0), matching how unbuildable events ship.
#
# Constraint kinds (dispatched in _constraint_violated):
#   never_switch_state_religion — fail if the player changes state religion after arming
#                                 [IMPLEMENTED]
#   keep_trigger_city           — fail if the trigger settlement (the player's capital at
#                                 arming) is lost (Master Blacksmith)      [IMPLEMENTED]
#
# A new aim/constraint kind is a single `match` case below plus, if it needs a baseline,
# a snapshot key written in _make_snapshot. Nothing else changes.

# ── Per-game roster (active inclusion) ───────────────────────────────────────────────

# Roll each quest's `active` inclusion percent ONCE, in sorted quest-id order, to decide
# whether it is in this game at all (mirrors Events.roll_active_events). Called once after
# setup; the roster is serialized so it is stable across save/load and on the determinism
# gate. An empty roster means "not rolled yet" — quest_eligible treats every quest as in.
static func roll_active_quests(game_state) -> void:
	var db: DataDB = game_state.db
	var roster: Array = []
	for qid in _quest_ids(db):
		var active: int = int(db.get_quest(qid).get("active", 100))
		if active >= 100 or game_state.rng.randi_range(1, 100) <= active:
			roster.append(qid)
	game_state.active_quest_ids = roster

# ── Per-player quest step ───────────────────────────────────────────────────────────

# Run the per-player quest step (mirrors Events.process_player_events): re-evaluate every
# active quest this player owns (complete → queue reward; constraint violated → drop),
# then try to arm one new eligible quest. Returns the produced descriptors (also appended
# to gs.pending_quest_events for the facade to drain).
static func process_player_quests(player: Player, game_state, rng: RNG) -> Array:
	var produced: Array = _evaluate_active(player, game_state)
	var armed: Dictionary = _arm_one(player, game_state, rng)
	if not armed.empty():
		produced.append(armed)
	for d in produced:
		game_state.pending_quest_events.append(d)
	return produced

# Re-evaluate the player's active quests. A completed quest queues its reward and is
# removed; a quest whose constraint is violated is dropped. Returns descriptors.
static func _evaluate_active(player: Player, game_state) -> Array:
	var db: DataDB = game_state.db
	var produced: Array = []
	var kept: Array = []
	for q in game_state.active_quests:
		if int(q.get("player_id", -1)) != player.id:
			kept.append(q)
			continue
		var quest: Dictionary = db.get_quest(str(q.get("quest_id", "")))
		if quest.empty():
			# The quest left the catalogue — drop it silently rather than wedge.
			continue
		if _constraint_violated(quest.get("constraint", {}), q, player, game_state):
			produced.append({
				"kind": "quest_failed", "player_id": player.id,
				"quest_id": str(q.get("quest_id", "")),
				"name": str(quest.get("name", q.get("quest_id", "")))
			})
			continue
		q["progress"] = _aim_progress(quest.get("aim", {}), q, player, game_state)
		if _aim_complete(quest.get("aim", {}), q, player, game_state):
			produced.append(_complete_quest(quest, q, player, game_state))
			continue
		kept.append(q)
	game_state.active_quests = kept
	return produced

# Arm at most one eligible quest for the player this turn. Eligible = in the per-game
# roster (active roll succeeds), prereq holds, and not already active or completed for
# this player. Among the eligible quests, one is drawn weighted by `weight` (gs.rng,
# fixed sorted-id order) — exactly the Events weighted pick. Returns a descriptor.
static func _arm_one(player: Player, game_state, rng: RNG) -> Dictionary:
	var db: DataDB = game_state.db
	var eligible: Array = []
	var weights: Array = []
	for qid in _quest_ids(db):
		if not quest_eligible(qid, player, game_state):
			continue
		eligible.append(qid)
		var w: int = int(db.get_quest(qid).get("weight", 1))
		weights.append(w if w > 0 else 1)
	if eligible.empty():
		return {}
	var idx: int = rng.rand_weighted(weights)
	if idx < 0 or idx >= eligible.size():
		idx = 0
	return arm_quest(eligible[idx], player, game_state)

# Whether a quest may be armed for this player right now: it is in the per-game roster
# (or the roster is empty — "not rolled yet", so direct unit tests still arm), its
# `prereq` holds (via the shared event vocabulary), and it is neither already active nor
# already completed for the player.
static func quest_eligible(quest_id: String, player: Player, game_state) -> bool:
	var db: DataDB = game_state.db
	var quest: Dictionary = db.get_quest(quest_id)
	if quest.empty():
		return false
	if not game_state.active_quest_ids.empty() and not (quest_id in game_state.active_quest_ids):
		return false
	if _quest_active_for(quest_id, player.id, game_state):
		return false
	if quest_id in player.quests_completed:
		return false
	return Events.prereq_holds(quest.get("prereq", {}), player, game_state)

# Arm a quest: append the tracking record (with its baseline snapshot) to
# gs.active_quests. Returns the "quest_armed" descriptor.
static func arm_quest(quest_id: String, player: Player, game_state) -> Dictionary:
	var db: DataDB = game_state.db
	var quest: Dictionary = db.get_quest(quest_id)
	var rec: Dictionary = {
		"quest_id": quest_id,
		"player_id": player.id,
		"start_turn": int(game_state.turn_number),
		"progress": 0,
		"snapshot": _make_snapshot(quest, player, game_state)
	}
	rec["progress"] = _aim_progress(quest.get("aim", {}), rec, player, game_state)
	game_state.active_quests.append(rec)
	return {
		"kind": "quest_armed", "player_id": player.id, "quest_id": quest_id,
		"name": str(quest.get("name", quest_id)), "text": str(quest.get("text", "")),
		"objective": str(quest.get("objective", ""))
	}

# ── Reward dispatch ──────────────────────────────────────────────────────────────────

# Complete a quest: record it on the player, then apply its reward. A reward with begin
# `effects` applies immediately (REUSING Events.apply_effects). A reward with `choices`
# parks a NON-SKIPPABLE choice into gs.pending_event_choices under a synthetic
# "quest:<id>" event_id — the AI auto-resolves the preferred (or first) branch; a human's
# pick is surfaced and resolved by the existing SimFacade event-choice path. The branch
# effects are fixed-value (quest aims/rewards draw no RNG), so the parked branches are
# applied verbatim. Returns the descriptor.
static func _complete_quest(quest: Dictionary, rec: Dictionary, player: Player, game_state) -> Dictionary:
	var quest_id: String = str(quest.get("id", ""))
	if not (quest_id in player.quests_completed):
		player.quests_completed.append(quest_id)
	var reward: Dictionary = quest.get("reward", {})
	var choices: Array = reward.get("choices", [])
	var pending: bool = false
	if choices.empty():
		Events.apply_effects(reward.get("effects", []), player, game_state)
	else:
		var resolved: Array = []
		for ch in choices:
			resolved.append({
				"id": str(ch.get("id", "")),
				"text": str(ch.get("text", "")),
				"effects": (ch.get("effects", [])).duplicate(true)
			})
		var ev_id: String = "quest:" + quest_id
		if player.is_ai:
			_apply_branch(resolved, _ai_choice_id(reward), player, game_state)
		else:
			game_state.pending_event_choices.append({
				"event_id": ev_id, "player_id": player.id, "trigger_id": "",
				"name": str(quest.get("name", quest_id)),
				"text": str(reward.get("text", quest.get("text", ""))),
				"resolved_choices": resolved
			})
			pending = true
	return {
		"kind": ("quest_reward_pending" if pending else "quest_completed"),
		"player_id": player.id, "quest_id": quest_id,
		"name": str(quest.get("name", quest_id))
	}

# Apply the named branch from a parked resolved_choices list (the AI path). Mirrors
# Events._apply_resolved_branch — the human path goes through Events.apply_choice.
static func _apply_branch(resolved: Array, choice_id: String, player: Player, game_state) -> bool:
	for ch in resolved:
		if str(ch.get("id", "")) == choice_id:
			Events.apply_effects(ch.get("effects", []), player, game_state)
			return true
	return false

# The AI's deterministic branch pick for a quest reward: the choice flagged ai_prefer,
# else the first. Mirrors Events.ai_choice_id.
static func _ai_choice_id(reward: Dictionary) -> String:
	var choices: Array = reward.get("choices", [])
	if choices.empty():
		return ""
	for ch in choices:
		if bool(ch.get("ai_prefer", false)):
			return str(ch.get("id", ""))
	return str(choices[0].get("id", ""))

# ── Aim dispatcher ───────────────────────────────────────────────────────────────────

# The player's current progress count toward the aim (cached on the record). Pure read.
static func _aim_progress(aim: Dictionary, rec: Dictionary, player: Player, game_state) -> int:
	match str(aim.get("kind", "")):
		"build_count":
			return _build_count(aim, rec, player, game_state)
		"build_units":
			return _build_units(aim, player, game_state)
		"build_fleet":
			return _fleet_met_types(aim, player, game_state)
		"cities_on_landmasses":
			return _cities_on_landmasses(player, game_state)
		"conquer_resource":
			return _conquer_resource(aim, player, game_state)
		"own_corp_resources":
			return _own_corp_resources(player, game_state)
		"spread_corp":
			return _spread_corp(rec, player, game_state)
		"control_named_tile":
			return _control_named_tile(aim, player, game_state)
		"conquer_holy_city":
			# No holy-city settlement model (see header) — Crusade ships disabled.
			return 0
		_:
			return 0

# Whether the aim is satisfied.
static func _aim_complete(aim: Dictionary, rec: Dictionary, player: Player, game_state) -> bool:
	match str(aim.get("kind", "")):
		"build_count":
			return _build_count(aim, rec, player, game_state) >= int(aim.get("count", 1))
		"build_units":
			return _build_units(aim, player, game_state) >= int(aim.get("count", 1))
		"build_fleet":
			# All required: every named type meets its own threshold. An empty
			# composition never completes.
			var comp_size: int = (aim.get("composition", {})).size()
			return comp_size > 0 and _fleet_met_types(aim, player, game_state) >= comp_size
		"cities_on_landmasses":
			return _cities_on_landmasses(player, game_state) >= int(aim.get("count", 1))
		"conquer_resource":
			return _conquer_resource(aim, player, game_state) >= 1
		"own_corp_resources":
			return _own_corp_resources(player, game_state) >= 1
		"spread_corp":
			return _spread_corp(rec, player, game_state) >= int(aim.get("count", 1))
		"control_named_tile":
			return _control_named_tile(aim, player, game_state) >= 1
		"conquer_holy_city":
			return false
		_:
			return false

# build_count aim: count the player's standing copies of `structure_id` across all owned
# cities. Per the catalogue's "cathedral counts as 4" note, an optional `weights` map
# (structure_id -> multiplier) lets a structure count for more than one, and an optional
# `also` array adds further structures that count toward the same goal. Only structures
# built AFTER arming count when `since_arm` is true (the snapshot baseline) — the default
# counts every standing copy, which is what the simple "build ~7 libraries" quests want.
static func _build_count(aim: Dictionary, rec: Dictionary, player: Player, game_state) -> int:
	var targets: Dictionary = {}            # structure_id -> multiplier
	targets[str(aim.get("structure_id", ""))] = int(aim.get("weight_self", 1))
	for sid in aim.get("also", []):
		targets[str(sid)] = 1
	var weights: Dictionary = aim.get("weights", {})
	for sid in weights:
		targets[str(sid)] = int(weights[sid])
	var snapshot: Dictionary = rec.get("snapshot", {})
	var since_arm: bool = bool(aim.get("since_arm", false))
	var total: int = 0
	for s in game_state.settlements:
		if s.owner_player_id != player.id:
			continue
		for sid in targets:
			if sid == "" or not s.has_structure(sid):
				continue
			if since_arm and int(snapshot.get(s.id, 0)) > 0:
				# This city already held the structure at arming — does not count.
				continue
			total += int(targets[sid])
	return total

# build_units aim: count the player's standing units whose type is in `unit_types`
# (the units-built quests — chariots/swordsmen/musketmen/knights/horse archers/
# triremes). Counts current owned copies, the unit-side mirror of build_count's
# default standing-structure tally.
static func _build_units(aim: Dictionary, player: Player, game_state) -> int:
	var types: Array = aim.get("unit_types", [])
	if types.empty():
		var one: String = str(aim.get("unit_type", ""))
		if one != "":
			types = [one]
	var total: int = 0
	for u in game_state.units:
		if u.owner_player_id == player.id and (u.unit_type_id in types):
			total += 1
	return total

# build_fleet aim: a `composition` map (unit_type_id -> required count). Returns how
# many of the named types currently MEET their threshold; the aim completes only when
# that equals the number of named types (every leg satisfied). The Overwhelm quest.
static func _fleet_met_types(aim: Dictionary, player: Player, game_state) -> int:
	var comp: Dictionary = aim.get("composition", {})
	if comp.empty():
		return 0
	# Tally owned units per type in one pass.
	var have: Dictionary = {}
	for u in game_state.units:
		if u.owner_player_id == player.id and comp.has(u.unit_type_id):
			have[u.unit_type_id] = int(have.get(u.unit_type_id, 0)) + 1
	var met: int = 0
	for t in comp:
		if int(have.get(t, 0)) >= int(comp[t]):
			met += 1
	return met

# cities_on_landmasses aim: the number of DISTINCT landmasses on which the player owns
# a settlement. Landmasses are connected components of land tiles (4-neighbour flood
# fill over non-sea terrain); a city's mass is the component of its own tile. Pure
# integer scan, no RNG. (Blessed Sea.)
static func _cities_on_landmasses(player: Player, game_state) -> int:
	var labels: Dictionary = _landmass_labels(game_state)
	var seen: Dictionary = {}
	for s in game_state.settlements:
		if s.owner_player_id != player.id:
			continue
		var key: int = int(labels.get(_tile_key(s.x, s.y, game_state), -1))
		if key >= 0:
			seen[key] = true
	return seen.size()

# Flood-fill every land tile into a connected-component id (4-neighbour adjacency,
# honouring map wrap via WorldMap.neighbours4). Returns tile_key -> component id.
# Sea tiles are omitted. Deterministic scan order (row-major).
static func _landmass_labels(game_state) -> Dictionary:
	var db: DataDB = game_state.db
	var labels: Dictionary = {}
	var next_id: int = 0
	for t in game_state.map.all_tiles():
		if _is_sea(t, db):
			continue
		var k: int = _tile_key(t.x, t.y, game_state)
		if labels.has(k):
			continue
		# New component: BFS from this tile over connected land.
		labels[k] = next_id
		var queue: Array = [t]
		while not queue.empty():
			var cur: Tile = queue.pop_back()
			for nt in game_state.map.neighbours4(cur.x, cur.y):
				if nt == null or _is_sea(nt, db):
					continue
				var nk: int = _tile_key(nt.x, nt.y, game_state)
				if labels.has(nk):
					continue
				labels[nk] = next_id
				queue.append(nt)
		next_id += 1
	return labels

static func _is_sea(t: Tile, db: DataDB) -> bool:
	return str(db.get_terrain(t.terrain_id).get("domain", "land")) == "sea"

# A stable integer key for a tile (row-major); landmass labels are keyed by it.
static func _tile_key(x: int, y: int, game_state) -> int:
	return y * game_state.map.width + x

# conquer_resource aim: 1 if the player owns a tile carrying any of the named
# `resources` (single `resource` also accepted), else 0. (Greed.)
static func _conquer_resource(aim: Dictionary, player: Player, game_state) -> int:
	var wanted: Array = aim.get("resources", [])
	if wanted.empty():
		var one: String = str(aim.get("resource", ""))
		if one != "":
			wanted = [one]
	for t in game_state.map.all_tiles():
		if t.owner_player_id == player.id and t.resource_id != "" and (t.resource_id in wanted):
			return 1
	return 0

# own_corp_resources aim: 1 once the player can access EVERY input resource of the
# corporation they founded (the same access test EconOrgs uses for output/HQ gold).
# Zero if they founded no corporation. (Hostile Takeover.)
static func _own_corp_resources(player: Player, game_state) -> int:
	var org_id: String = EconOrgs.corporation_of_player(game_state, player.id)
	if org_id == "":
		return 0
	var org: Dictionary = game_state.db.econ_orgs.get(org_id, {})
	var inputs: Array = org.get("input_resources", [])
	if inputs.empty():
		return 0
	if EconOrgs.accessible_input_count(game_state, org, player.id) >= inputs.size():
		return 1
	return 0

# spread_corp aim: the number of cities hosting the player's corporation BEYOND the
# count present at arming (the snapshot baseline under CORP_BASELINE_KEY). Counts every
# member city worldwide, mirroring the reference's "spread to N new cities". (Corporate
# Expansion.)
static func _spread_corp(rec: Dictionary, player: Player, game_state) -> int:
	var org_id: String = EconOrgs.corporation_of_player(game_state, player.id)
	if org_id == "":
		return 0
	var current: int = 0
	for s in game_state.settlements:
		if s.econ_org_id == org_id:
			current += 1
	var baseline: int = int(rec.get("snapshot", {}).get(CORP_BASELINE_KEY, 0))
	var delta: int = current - baseline
	return delta if delta > 0 else 0

# control_named_tile aim: 1 if the player owns a settlement standing on a tile matching
# `match` (terrain/feature/improvement/resource). Generic — no shipped quest uses it,
# but the kind is live so a future "settle the named tile" quest is pure data.
static func _control_named_tile(aim: Dictionary, player: Player, game_state) -> int:
	var spec: Dictionary = aim.get("match", {})
	for s in game_state.settlements:
		if s.owner_player_id != player.id:
			continue
		var t: Tile = game_state.map.get_tile(s.x, s.y)
		if t == null:
			continue
		if spec.has("terrain") and t.terrain_id != str(spec["terrain"]):
			continue
		if spec.has("feature") and t.feature_id != str(spec["feature"]):
			continue
		if spec.has("improvement") and t.improvement_id != str(spec["improvement"]):
			continue
		if spec.has("resource") and t.resource_id != str(spec["resource"]):
			continue
		return 1
	return 0

# ── Constraint dispatcher ────────────────────────────────────────────────────────────

# Whether the active quest's constraint is now violated (→ drop the quest). An empty
# constraint never fails.
static func _constraint_violated(constraint: Dictionary, rec: Dictionary, player: Player, game_state) -> bool:
	if constraint.empty():
		return false
	match str(constraint.get("kind", "")):
		"never_switch_state_religion":
			# The state religion held at arming is stashed in the snapshot under the
			# sentinel key STATE_RELIGION_KEY; failing if the player has since changed it.
			var snap: Dictionary = rec.get("snapshot", {})
			return str(snap.get(STATE_RELIGION_KEY, "")) != player.state_religion
		"keep_trigger_city":
			# The trigger settlement id (the player's capital at arming) is stashed under
			# TRIGGER_CITY_KEY; the constraint fails if the player no longer owns it
			# (it was lost / razed / captured). A missing baseline never fails.
			var tsnap: Dictionary = rec.get("snapshot", {})
			var trigger_id: int = int(tsnap.get(TRIGGER_CITY_KEY, -1))
			if trigger_id < 0:
				return false
			for s in game_state.settlements:
				if s.id == trigger_id and s.owner_player_id == player.id:
					return false
			return true
		_:
			return false

# ── Snapshot baseline ────────────────────────────────────────────────────────────────

# A snapshot baseline captured at arming, keyed by aim/constraint kind:
#   * build_count + since_arm — settlement_id (int) -> 1 for every owned city already
#     holding a target structure (so "cities that did NOT have it" can be diffed).
#   * spread_corp — CORP_BASELINE_KEY -> the count of cities hosting the player's
#     corporation at arming (so "spread to N NEW cities" can be diffed).
#   * never_switch_state_religion — the state religion id under STATE_RELIGION_KEY.
#   * keep_trigger_city — the trigger settlement id under TRIGGER_CITY_KEY (the
#     player's capital at arming).
# All shapes serialize cleanly; the int settlement-id keys (and the sentinel keys) are
# coerced back to int on deserialize (the JSON float/string-key gotcha). Sentinel keys
# are negative so they never collide with a real settlement id.
const STATE_RELIGION_KEY: int = -1   # sentinel snapshot key (no settlement has id -1)
const TRIGGER_CITY_KEY: int = -2     # keep_trigger_city baseline
const CORP_BASELINE_KEY: int = -3    # spread_corp baseline member-city count

static func _make_snapshot(quest: Dictionary, player: Player, game_state) -> Dictionary:
	var snap: Dictionary = {}
	var aim: Dictionary = quest.get("aim", {})
	var aim_kind: String = str(aim.get("kind", ""))
	if aim_kind == "build_count" and bool(aim.get("since_arm", false)):
		var sid: String = str(aim.get("structure_id", ""))
		for s in game_state.settlements:
			if s.owner_player_id == player.id and s.has_structure(sid):
				snap[s.id] = 1
	if aim_kind == "spread_corp":
		var org_id: String = EconOrgs.corporation_of_player(game_state, player.id)
		var n: int = 0
		if org_id != "":
			for s in game_state.settlements:
				if s.econ_org_id == org_id:
					n += 1
		snap[CORP_BASELINE_KEY] = n
	var constraint: Dictionary = quest.get("constraint", {})
	var ckind: String = str(constraint.get("kind", ""))
	if ckind == "never_switch_state_religion":
		snap[STATE_RELIGION_KEY] = player.state_religion
	if ckind == "keep_trigger_city":
		var cap: Settlement = Events.capital_of(player.id, game_state)
		snap[TRIGGER_CITY_KEY] = (cap.id if cap != null else -1)
	return snap

# ── Helpers ──────────────────────────────────────────────────────────────────────────

# Sorted list of real quest ids (skips the schema `_comment`).
static func _quest_ids(db: DataDB) -> Array:
	var ids: Array = []
	for qid in db.get_quests():
		if qid != "_comment":
			ids.append(qid)
	ids.sort()
	return ids

# Whether the player already has this quest active.
static func _quest_active_for(quest_id: String, player_id: int, game_state) -> bool:
	for q in game_state.active_quests:
		if str(q.get("quest_id", "")) == quest_id and int(q.get("player_id", -1)) == player_id:
			return true
	return false
