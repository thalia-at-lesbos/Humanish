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
#   cities_on_landmasses   — own cities spread over N distinct landmasses        [STUB]
#   control_named_tile     — control a specific named tile / wonder              [STUB]
#   conquer_resource       — control a tile carrying a named resource (Greed)    [STUB]
#   conquer_holy_city      — hold the holy city of a religion (Crusade)          [STUB]
#   spread_corp            — spread a corporation to N new cities (Corp Expansion)[STUB]
#   own_corp_resources     — own every input resource of a corporation          [STUB]
#   build_fleet            — build a specific fleet composition (Overwhelm)      [STUB]
#
# Constraint kinds (dispatched in _constraint_violated):
#   never_switch_state_religion — fail if the player changes state religion after arming
#                                 [IMPLEMENTED]
#   keep_trigger_city           — fail if the trigger settlement is lost (Master
#                                 Blacksmith) [STUB]
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
		"name": str(quest.get("name", quest_id)), "text": str(quest.get("text", ""))
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
		_:
			# Unimplemented aim kinds (catalogue stubs) never advance — the quest simply
			# stays armed until the next subagent implements its kind.
			return 0

# Whether the aim is satisfied.
static func _aim_complete(aim: Dictionary, rec: Dictionary, player: Player, game_state) -> bool:
	match str(aim.get("kind", "")):
		"build_count":
			return _build_count(aim, rec, player, game_state) >= int(aim.get("count", 1))
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
		_:
			# Unimplemented constraint kinds never fire — the quest is never wrongly
			# dropped before the next subagent implements its kind.
			return false

# ── Snapshot baseline ────────────────────────────────────────────────────────────────

# A snapshot baseline captured at arming, keyed by aim/constraint kind:
#   * build_count + since_arm — settlement_id (int) -> 1 for every owned city already
#     holding a target structure (so "cities that did NOT have it" can be diffed).
#   * never_switch_state_religion — the state religion id under STATE_RELIGION_KEY.
# Both shapes serialize cleanly; the int settlement-id keys are coerced back to int on
# deserialize (the JSON float/string-key gotcha).
const STATE_RELIGION_KEY: int = -1   # sentinel snapshot key (no settlement has id -1)

static func _make_snapshot(quest: Dictionary, player: Player, game_state) -> Dictionary:
	var snap: Dictionary = {}
	var aim: Dictionary = quest.get("aim", {})
	if str(aim.get("kind", "")) == "build_count" and bool(aim.get("since_arm", false)):
		var sid: String = str(aim.get("structure_id", ""))
		for s in game_state.settlements:
			if s.owner_player_id == player.id and s.has_structure(sid):
				snap[s.id] = 1
	var constraint: Dictionary = quest.get("constraint", {})
	if str(constraint.get("kind", "")) == "never_switch_state_religion":
		snap[STATE_RELIGION_KEY] = player.state_religion
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
