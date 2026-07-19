# Humanish — a turn-based 4X strategy game.
# Copyright (C) 2026 thalia-at-lesbos
# SPDX-License-Identifier: GPL-3.0-or-later
#
# This program is free software: you can redistribute it and/or modify it
# under the terms of the GNU General Public License as published by the Free
# Software Foundation, either version 3 of the License, or (at your option)
# any later version. See the LICENSE file for the full text and warranty
# disclaimer.

class_name Assembly

# §7.2 Diplomatic assemblies, elections & resolutions (PROVISIONAL).
#
# A world voting body, founded by a world wonder, that elects a presiding resident
# and passes binding empire-wide resolutions. Two bodies exist: the religious
# assembly (Apostolic Palace, organised around one belief) and the secular United
# Nations (organised around all players); the secular body supersedes the religious.
#
# Pure static, like the rest of sim/. The lifecycle is driven once per whole-world
# step (§3.7) from TurnEngine via world_tick():
#   • a session OPENS on a fixed cadence, recording one proposal (a leadership
#     election while there is no resident, otherwise a random eligible resolution);
#   • every member then has one player-turn to cast a weighted Yea/Nay/Abstain
#     (humans through SimFacade.cast_assembly_vote / the CHOOSE_ELECTION popup,
#     computer players through PlayerAI.manage_assembly → ai_vote);
#   • the proposal RESOLVES on the next world step: non-voters abstain, votes are
#     tallied by weight, and a passing proposal's effect is applied.
# Every random draw goes through the shared gs.rng so sessions are reproducible and
# captured by save/load. All magnitudes live in data/constants.json and
# data/resolutions.json.

const VOTE_YEA := "yea"
const VOTE_NAY := "nay"
const VOTE_ABSTAIN := "abstain"

# ── Active body / gating ───────────────────────────────────────────────────────

# Which assembly currently exists, gated on its founding wonder. The secular United
# Nations supersedes the religious Apostolic Palace. "" when neither wonder is built.
# An obsolete founding wonder (§15.17: the Apostolic Palace once its owner has
# Mass Media) counts as absent — its assembly-hosting effect has stopped.
static func active_body(gs) -> String:
	var has_religious: bool = false
	for s in gs.settlements:
		if s.has_structure("united_nations") \
				and _wonder_active(gs, s, "united_nations"):
			return "secular"
		if s.has_structure("apostolic_palace") \
				and _wonder_active(gs, s, "apostolic_palace"):
			has_religious = true
	return "religious" if has_religious else ""

# Whether a founding wonder in `s` is still active — i.e. its owner has not
# researched its `obsoleted_by` tech (§15.17).
static func _wonder_active(gs, s, struct_id: String) -> bool:
	var owner = gs.get_player(s.owner_player_id)
	return owner == null or not owner.structure_obsolete(gs.db, struct_id)

# The belief the religious assembly organises around: the faith of the city holding
# the Apostolic Palace. "" for the secular body (or an unfaithful Palace).
static func _religious_belief(gs) -> String:
	for s in gs.settlements:
		if s.has_structure("apostolic_palace") \
				and _wonder_active(gs, s, "apostolic_palace"):
			return str(s.belief_id)
	return ""

# ── Membership & vote weight ───────────────────────────────────────────────────

# Religious members weight by population of their cities holding the assembly belief;
# secular members (the United Nations guarantees eligibility for all) weight by total
# governed population. A religious member running the assembly belief as its state
# religion (§8.1) votes at double weight (§7.2 Apostolic Palace adherence bonus).
static func vote_weight(gs, player, body: String) -> int:
	if player == null or player.is_eliminated:
		return 0
	var belief: String = _religious_belief(gs)
	var w: int = 0
	for s in gs.settlements:
		if s.owner_player_id != player.id:
			continue
		if body == "religious":
			if belief != "" and s.belief_id == belief:
				w += s.population
		else:
			w += s.population
	if body == "religious" and belief != "" and str(player.state_religion) == belief:
		w *= 2
	return w

static func is_member(gs, player, body: String) -> bool:
	if player == null or player.is_eliminated:
		return false
	if body == "secular":
		return true
	if body == "religious":
		return vote_weight(gs, player, body) > 0
	return false

# Every eligible member, in player order (deterministic).
static func _members(gs, body: String) -> Array:
	var out: Array = []
	for p in gs.players:
		if is_member(gs, p, body):
			out.append(p)
	return out

# ── Lifecycle (called from the world step) ─────────────────────────────────────

static func world_tick(gs, rng) -> void:
	var body: String = active_body(gs)
	if body == "":
		# No founding wonder (or it was razed): no assembly.
		if not gs.assembly.empty():
			gs.assembly = {}
		return

	# Establish or re-establish the record when the body first appears or changes.
	if gs.assembly.empty() or str(gs.assembly.get("kind", "")) != body:
		_establish(gs, body)
	else:
		gs.assembly["belief_id"] = _religious_belief(gs) if body == "religious" else ""

	# One action per world tick. A proposal opened last session has now had a full
	# round of player turns to gather votes, so resolve it before opening another.
	if not gs.assembly.get("pending", {}).empty():
		_resolve_pending(gs)
		return

	# §7.2 Apostolic Palace diplomatic-victory cadence: the supreme-leadership motion
	# appears automatically every ap_diplo_victory_interval turns for the religious
	# body (independent of the resident agenda), provided every living civ holds the
	# AP belief. It takes priority over the ordinary random session this turn.
	if _ap_victory_due(gs):
		_open_diplo_session(gs)
		return

	var interval: int = gs.db.get_constant("assembly_session_interval", 12)
	if interval > 0 and gs.turn_number > 0 and gs.turn_number % interval == 0:
		_open_session(gs, rng)

static func _establish(gs, body: String) -> void:
	gs.assembly = {
		"kind": body,
		"belief_id": _religious_belief(gs) if body == "religious" else "",
		"resident_player_id": -1,
		"last_session_turn": -1,
		"standing": {},
		# Player ids currently in defiance of the assembly's rulings (§4.5): a member
		# that voted against a binding mandate it was bound by. Such a member is not a
		# "full member" and cannot stand in a supreme-leadership runoff (§7.3).
		"defiant": [],
		"pending": {}
	}

static func _open_session(gs, rng) -> void:
	var body: String = str(gs.assembly.get("kind", ""))
	var members: Array = _members(gs, body)
	if members.empty():
		return
	var resident: int = int(gs.assembly.get("resident_player_id", -1))
	var pending: Dictionary = {}

	if resident < 0 or gs.get_player(resident) == null:
		# No sitting resident → the chamber must first elect one.
		pending = _make_proposal(gs, "elect_resident", _front_runner(gs, members), -1)
	else:
		var pool: Array = _eligible_resolutions(gs, body)
		if pool.empty():
			return
		var res_id: String = pool[rng.randi_range(0, pool.size() - 1)]
		var candidate: int = resident
		var target_aid: int = -1
		var eff: String = str(gs.db.get_resolution(res_id).get("effect", ""))
		if str(gs.db.get_resolution(res_id).get("kind", "resolution")) == "election":
			candidate = _front_runner(gs, members)
		if eff == "diplomatic_victory":
			# Secular (UN) supreme-leadership runs the strongest Mass-Media holder;
			# with no eligible candidate the motion cannot be put forward.
			candidate = _diplo_candidate(gs, body, members)
			if candidate < 0:
				return
		if eff == "trade_embargo":
			target_aid = _embargo_target(gs, resident)
			if target_aid < 0:
				return
		pending = _make_proposal(gs, res_id, candidate, target_aid)

	if pending.empty():
		return
	gs.assembly["pending"] = pending
	gs.assembly["last_session_turn"] = gs.turn_number
	gs.pending_assembly_events.append({
		"kind": "session_opened",
		"resolution_id": pending["resolution_id"],
		"name": pending["name"],
		"text": pending["text"]
	})

# Build the pending-proposal record (with an empty vote map) and its read-out text.
static func _make_proposal(gs, res_id: String, candidate_pid: int, target_aid: int) -> Dictionary:
	var res: Dictionary = gs.db.get_resolution(res_id)
	if res.empty():
		return {}
	var belief: String = str(gs.assembly.get("belief_id", ""))
	var pending: Dictionary = {
		"resolution_id": res_id,
		"name": str(res.get("name", res_id)),
		"candidate_player_id": candidate_pid,
		# The candidate slate. A single entry for ordinary elections; a supreme-
		# leadership motion may carry a two-candidate runoff (set by the opener).
		"candidates": ([candidate_pid] if candidate_pid >= 0 else []),
		"target_alliance_id": target_aid,
		"belief_id": belief,
		"pass_share": int(res.get("pass_share", gs.db.get_constant("resolution_pass_share", 50))),
		"text": _fill_text(gs, str(res.get("text", "")), candidate_pid, target_aid, belief),
		"votes": {}
	}
	return pending

# ── Resolution ─────────────────────────────────────────────────────────────────

static func _resolve_pending(gs) -> void:
	var pending: Dictionary = gs.assembly.get("pending", {})
	var body: String = str(gs.assembly.get("kind", ""))
	if _is_diplo_motion(gs, pending):
		_resolve_diplo_victory(gs, pending, body)
	else:
		_resolve_simple(gs, pending, body)
	gs.assembly["pending"] = {}

# An ordinary Yea/Nay/Abstain proposal: passes when the Yea share of the whole
# chamber's weight reaches the threshold (abstentions count present but not for, so
# they make passage harder — as in a real quorum body).
static func _resolve_simple(gs, pending: Dictionary, body: String) -> void:
	var votes: Dictionary = pending.get("votes", {})
	var yea: int = 0
	var nay: int = 0
	var total: int = 0
	for member in _members(gs, body):
		var w: int = vote_weight(gs, member, body)
		if w <= 0:
			continue
		total += w
		var choice: String = str(votes.get(str(member.id), VOTE_ABSTAIN))
		if choice == VOTE_YEA:
			yea += w
		elif choice == VOTE_NAY:
			nay += w
	var pass_share: int = _pass_share_for(gs, pending)
	var passed: bool = total > 0 and (yea * 100) / total >= pass_share
	var res_id: String = str(pending["resolution_id"])
	if passed:
		apply_effect(gs, res_id, pending)
	gs.pending_assembly_events.append({
		"kind": "resolution_resolved",
		"resolution_id": res_id,
		"name": str(pending.get("name", res_id)),
		"passed": passed,
		"yea": yea, "nay": nay, "total": total
	})

# A supreme-leadership election: members cast their weight for one candidate (or
# abstain). The leading candidate (ties → lowest id) wins if its share of the whole
# chamber's weight reaches the body-dependent threshold (UN 60% / Apostolic Palace
# 75%) and clears the eligibility / "too big" gate in apply_effect.
static func _resolve_diplo_victory(gs, pending: Dictionary, body: String) -> void:
	var votes: Dictionary = pending.get("votes", {})
	var tally: Dictionary = {}   # candidate id (int) -> weight cast for it
	for c in pending.get("candidates", []):
		tally[int(c)] = 0
	var total: int = 0
	for member in _members(gs, body):
		var w: int = vote_weight(gs, member, body)
		if w <= 0:
			continue
		total += w
		var choice: String = str(votes.get(str(member.id), VOTE_ABSTAIN))
		if choice == VOTE_ABSTAIN:
			continue
		var cid: int = int(choice)
		if tally.has(cid):
			tally[cid] += w
	var lead_id: int = -1
	var lead_w: int = -1
	for cid in tally:
		var w: int = int(tally[cid])
		if w > lead_w or (w == lead_w and (lead_id < 0 or int(cid) < lead_id)):
			lead_w = w
			lead_id = int(cid)
	var pass_share: int = _pass_share_for(gs, pending)
	var passed: bool = total > 0 and lead_id >= 0 and (lead_w * 100) / total >= pass_share
	if passed:
		# Run the shared award/eligibility/too-big gate for the winning candidate.
		var resolved: Dictionary = pending.duplicate(true)
		resolved["candidate_player_id"] = lead_id
		apply_effect(gs, str(pending["resolution_id"]), resolved)
	gs.pending_assembly_events.append({
		"kind": "resolution_resolved",
		"resolution_id": str(pending["resolution_id"]),
		"name": str(pending.get("name", "")),
		"passed": passed,
		"winner_player_id": lead_id,
		"yea": (lead_w if lead_w > 0 else 0),
		"nay": (total - lead_w if total > lead_w else 0),
		"total": total
	})

# Apply a passed proposal's binding effect. Provisional: elect_resident,
# diplomatic_victory, force_peace, civic_mandate, religion_mandate and resident_aid
# act immediately; trade_embargo/free_religion_spread/no_nuclear are recorded as
# standing effects (enforcement partial — see game-data.md §18).
static func apply_effect(gs, res_id: String, pending: Dictionary) -> void:
	var eff: String = str(gs.db.get_resolution(res_id).get("effect", res_id))
	match eff:
		"elect_resident":
			gs.assembly["resident_player_id"] = int(pending.get("candidate_player_id", -1))
		"diplomatic_victory":
			if "diplomatic" in gs.enabled_win_conditions:
				var cand = gs.get_player(int(pending.get("candidate_player_id", -1)))
				if cand != null and _diplo_win_allowed(gs, cand):
					gs.winning_alliance_id = cand.alliance_id
				elif cand != null:
					# The motion passed but the win is barred (AP eligibility, the
					# UN Mass-Media requirement, or the alliance "too big" rule).
					gs.pending_assembly_events.append({
						"kind": "victory_blocked",
						"candidate_player_id": cand.id,
						"name": str(pending.get("name", "diplomatic_victory"))
					})
		"force_peace":
			_force_peace(gs)
		"trade_embargo":
			gs.assembly["standing"]["trade_embargo"] = int(pending.get("target_alliance_id", -1))
		"civic_mandate":
			_civic_mandate(gs)
			_mark_defiance(gs, pending)
		"religion_mandate":
			_religion_mandate(gs, str(pending.get("belief_id", "")))
			_mark_defiance(gs, pending)
		"free_religion_spread":
			gs.assembly["standing"]["free_religion_spread"] = true
		"no_nuclear":
			gs.assembly["standing"]["no_nuclear"] = true
		"resident_aid":
			var r = gs.get_player(int(gs.assembly.get("resident_player_id", -1)))
			if r != null:
				r.treasury += gs.db.get_constant("resident_aid_gold", 100)

static func _force_peace(gs) -> void:
	for a in gs.alliances:
		a.at_war_with = []
		a.war_fatigue = {}
		a.forced_wars = []

# Mandate the resident's government civic onto every member that has its enabling
# technology. Defiance anger (the §4.5 "assembly rulings" source) is left to a
# future contentment hook; the mandate itself is applied here.
static func _civic_mandate(gs) -> void:
	var resident = gs.get_player(int(gs.assembly.get("resident_player_id", -1)))
	if resident == null:
		return
	var civic: String = str(resident.policies.get("government", ""))
	if civic == "":
		return
	var pol: Dictionary = gs.db.policies.get("policies", {}).get(civic, {})
	var tech_req = pol.get("tech_required", null)
	for member in _members(gs, str(gs.assembly.get("kind", ""))):
		if tech_req == null or str(tech_req) == "" or member.has_tech(str(tech_req)):
			member.policies["government"] = civic

# Proclaim the assembly belief the state religion of every member that harbours it.
# The mandate is compelled, so it bypasses the §8.1 switching anarchy.
static func _religion_mandate(gs, belief: String) -> void:
	if belief == "":
		return
	for member in _members(gs, str(gs.assembly.get("kind", ""))):
		for s in gs.settlements:
			if s.owner_player_id == member.id and s.belief_id == belief:
				member.state_religion = belief
				break

# ── Voting (called from the facade / AI) ───────────────────────────────────────

static func has_open_session(gs) -> bool:
	if gs.assembly.empty():
		return false
	return not gs.assembly.get("pending", {}).empty()

static func pending_proposal(gs) -> Dictionary:
	if gs.assembly.empty():
		return {}
	return gs.assembly.get("pending", {})

static func has_voted(gs, player_id: int) -> bool:
	var pending: Dictionary = pending_proposal(gs)
	if pending.empty():
		return false
	return pending.get("votes", {}).has(str(player_id))

# Record one member's vote on the open proposal. Returns false if there is no open
# session, the player is not an eligible member, or the choice is not recognised. A
# supreme-leadership motion takes a candidate id (as a string) or VOTE_ABSTAIN; every
# other proposal takes VOTE_YEA / VOTE_NAY / VOTE_ABSTAIN.
static func cast_vote(gs, player_id: int, choice: String) -> bool:
	if not has_open_session(gs):
		return false
	var pending: Dictionary = gs.assembly["pending"]
	var valid: bool
	if _is_diplo_motion(gs, pending):
		valid = choice == VOTE_ABSTAIN or choice in _candidate_choices(pending)
	else:
		valid = choice == VOTE_YEA or choice == VOTE_NAY or choice == VOTE_ABSTAIN
	if not valid:
		return false
	var body: String = str(gs.assembly.get("kind", ""))
	var p = gs.get_player(player_id)
	if not is_member(gs, p, body):
		return false
	gs.assembly["pending"]["votes"][str(player_id)] = choice
	return true

# Whether the open proposal is a supreme-leadership election (candidate-id ballot).
static func _is_diplo_motion(gs, pending: Dictionary) -> bool:
	if pending.empty():
		return false
	return str(gs.db.get_resolution(str(pending.get("resolution_id", ""))).get("effect", "")) == "diplomatic_victory"

# The valid vote tokens for a runoff: each candidate id rendered as a string.
static func _candidate_choices(pending: Dictionary) -> Array:
	var out: Array = []
	for c in pending.get("candidates", []):
		out.append(str(int(c)))
	return out

# Deterministic computer vote: self-interest, no RNG. Defaults to abstain.
static func ai_vote(gs, player_id: int) -> String:
	var pending: Dictionary = pending_proposal(gs)
	if pending.empty():
		return VOTE_ABSTAIN
	var me = gs.get_player(player_id)
	if me == null:
		return VOTE_ABSTAIN
	var eff: String = str(gs.db.get_resolution(str(pending["resolution_id"])).get("effect", ""))
	var cand = gs.get_player(int(pending.get("candidate_player_id", -1)))
	var cand_friendly: bool = cand != null and cand.alliance_id == me.alliance_id
	match eff:
		"elect_resident":
			# Back your own bloc or your overlord; otherwise support a candidate you
			# have come to like (attitude Pleased or better, §7). A disliked rival is
			# voted down.
			if cand_friendly or _is_vassal_of(gs, player_id, cand):
				return VOTE_YEA
			if cand != null and Diplomacy.attitude_level(gs, gs.db, player_id, cand.id) >= Diplomacy.PLEASED:
				return VOTE_YEA
			return VOTE_NAY
		"diplomatic_victory":
			# Cast for a candidate from your own bloc (your own id first, then a
			# bloc-mate, then your overlord if you are its vassal); otherwise abstain
			# — never hand the game to a rival (AI rivals will not vote you in).
			return _ai_diplo_vote(gs, player_id, pending, me)
		"force_peace":
			var at_war: bool = false
			var a = gs.get_player_alliance(player_id)
			if a != null and not a.at_war_with.empty():
				at_war = true
			return VOTE_YEA if at_war else VOTE_ABSTAIN
		"trade_embargo":
			# Resist an embargo aimed at yourself, or at an alliance you favour
			# (a member you regard as Pleased or better, §7); otherwise back it.
			var tgt: int = int(pending.get("target_alliance_id", -1))
			if tgt == me.alliance_id:
				return VOTE_NAY
			var tgt_alliance = gs.get_alliance(tgt)
			if tgt_alliance != null:
				for tm in tgt_alliance.member_player_ids:
					if Diplomacy.attitude_level(gs, gs.db, player_id, int(tm)) >= Diplomacy.PLEASED:
						return VOTE_NAY
			return VOTE_YEA
		"religion_mandate":
			return VOTE_YEA if me.state_religion == str(pending.get("belief_id", "")) else VOTE_NAY
		"civic_mandate":
			return VOTE_YEA
		"resident_aid":
			var r = gs.get_player(int(gs.assembly.get("resident_player_id", -1)))
			return VOTE_YEA if (r != null and r.alliance_id == me.alliance_id) else VOTE_NAY
		_:
			return VOTE_ABSTAIN

# Pick the candidate a computer member backs in a supreme-leadership runoff: itself
# if it stands, then a bloc-mate, then its overlord (vassal loyalty). With no friendly
# candidate it abstains rather than help a rival reach the threshold.
static func _ai_diplo_vote(gs, player_id: int, pending: Dictionary, me) -> String:
	var candidates: Array = pending.get("candidates", [])
	for c in candidates:
		if int(c) == player_id:
			return str(player_id)
	for c in candidates:
		var cp = gs.get_player(int(c))
		if cp != null and me != null and cp.alliance_id == me.alliance_id:
			return str(int(c))
	var my_alliance = gs.get_player_alliance(player_id)
	if my_alliance != null and my_alliance.is_subordinate_to >= 0:
		for c in candidates:
			var cp = gs.get_player(int(c))
			if cp != null and cp.alliance_id == my_alliance.is_subordinate_to:
				return str(int(c))
	return VOTE_ABSTAIN

# ── Diplomatic victory (§7.2 / §10) ─────────────────────────────────────────────

# True on a turn the Apostolic Palace must put forward the supreme-leadership motion:
# the religious body exists, the win condition is enabled, every living civ holds the
# AP belief (the AP eligibility rule), and the dedicated cadence falls due this turn.
static func _ap_victory_due(gs) -> bool:
	if str(gs.assembly.get("kind", "")) != "religious":
		return false
	if not ("diplomatic" in gs.enabled_win_conditions):
		return false
	if not _ap_all_eligible(gs):
		return false
	var interval: int = gs.db.get_constant("ap_diplo_victory_interval", 50)
	return interval > 0 and gs.turn_number > 0 and gs.turn_number % interval == 0

# Open the Apostolic Palace supreme-leadership motion (its own cadence, not the
# random pool). The candidate is the strongest religious member (the wonder owner is
# also a nominal candidate; with one Yea/Nay ballot we run whichever polls highest,
# two candidates — the wonder owner and the strongest member — when they differ.
static func _open_diplo_session(gs) -> void:
	var body: String = str(gs.assembly.get("kind", ""))
	var members: Array = _members(gs, body)
	if members.empty():
		return
	var slate: Array = _diplo_candidates(gs, body, members)
	if slate.empty():
		return
	var pending: Dictionary = _make_proposal(gs, "diplomatic_victory", int(slate[0]), -1)
	if pending.empty():
		return
	pending["candidates"] = slate
	pending["text"] = _fill_diplo_text(gs, pending, slate)
	gs.assembly["pending"] = pending
	gs.assembly["last_session_turn"] = gs.turn_number
	gs.pending_assembly_events.append({
		"kind": "session_opened",
		"resolution_id": pending["resolution_id"],
		"name": pending["name"],
		"text": pending["text"]
	})

# The Apostolic Palace wonder owner — the natural primary candidate, or -1.
# An obsolete Palace (§15.17) confers no candidacy.
static func _ap_owner(gs) -> int:
	for s in gs.settlements:
		if s.has_structure("apostolic_palace") \
				and _wonder_active(gs, s, "apostolic_palace"):
			return s.owner_player_id
	return -1

# The candidate slate for a supreme-leadership motion (player ids, primary first).
# Secular (UN): the single strongest Mass-Media holder. Religious (Apostolic Palace):
# the wonder owner (who stands by right of the wonder) plus the strongest "full
# member" — a member running the assembly belief as its state religion and not in
# defiance (§7.3) — a two-candidate runoff when they differ, collapsing to one when no
# other full member qualifies. Empty when no one may stand.
static func _diplo_candidates(gs, body: String, members: Array) -> Array:
	if body != "religious":
		var c: int = _diplo_candidate(gs, body, members)
		return [c] if c >= 0 else []
	var owner: int = _ap_owner(gs)
	var slate: Array = []
	if owner >= 0 and gs.get_player(owner) != null:
		slate.append(owner)
	var top: int = _top_full_member(gs, members, owner)
	if top >= 0 and top != owner:
		slate.append(top)
	return slate

# The strongest "full member" eligible to stand as the rival candidate: a religious
# member that runs the assembly belief as its state religion and is not in defiance,
# excluding the wonder owner. Ties → lowest id; -1 when none qualify.
static func _top_full_member(gs, members: Array, exclude_pid: int) -> int:
	var belief: String = _religious_belief(gs)
	if belief == "":
		return -1
	var best_id: int = -1
	var best_w: int = -1
	for p in members:
		if p.id == exclude_pid:
			continue
		if str(p.state_religion) != belief:
			continue
		if _is_defiant(gs, p.id):
			continue
		var w: int = vote_weight(gs, p, "religious")
		if w > best_w or (w == best_w and (best_id < 0 or p.id < best_id)):
			best_w = w
			best_id = p.id
	return best_id

# Whether a player is currently in defiance of the assembly's rulings (§4.5).
static func _is_defiant(gs, player_id: int) -> bool:
	for d in gs.assembly.get("defiant", []):
		if int(d) == player_id:
			return true
	return false

# Record every member that voted against a passed binding mandate as in defiance of
# the assembly (§4.5 / §7.3). Such a member forfeits "full member" standing.
static func _mark_defiance(gs, pending: Dictionary) -> void:
	var votes: Dictionary = pending.get("votes", {})
	var defiant: Array = gs.assembly.get("defiant", [])
	for member in _members(gs, str(gs.assembly.get("kind", ""))):
		if str(votes.get(str(member.id), VOTE_ABSTAIN)) == VOTE_NAY and not _is_defiant(gs, member.id):
			defiant.append(member.id)
	gs.assembly["defiant"] = defiant

# Read-out text naming both candidates of a runoff (single-candidate motions keep the
# resolution's own {candidate} text).
static func _fill_diplo_text(gs, pending: Dictionary, slate: Array) -> String:
	if slate.size() < 2:
		return str(pending.get("text", ""))
	return ("The assembly is called to elect the foremost power of the age. "
		+ _player_name(gs, int(slate[0])) + " and " + _player_name(gs, int(slate[1]))
		+ " stand before the chamber; cast your weight for one, that the world might "
		+ "be settled by acclamation rather than the sword.")

# The candidate run for a supreme-leadership motion: the strongest eligible member
# (ties → lowest id). For the secular UN only a Mass-Media holder may stand (and thus
# win); -1 when no member qualifies, so the motion is not put forward.
static func _diplo_candidate(gs, body: String, members: Array) -> int:
	var best_id: int = -1
	var best_w: int = -1
	for p in members:
		if body == "secular" and not p.has_tech("mass_media"):
			continue
		var w: int = vote_weight(gs, p, body)
		if w > best_w or (w == best_w and (best_id < 0 or p.id < best_id)):
			best_w = w
			best_id = p.id
	return best_id

# AP eligibility: every living civ must hold at least one city following the assembly
# belief (§7.2 "every civilization must have a city with the AP state religion").
static func _ap_all_eligible(gs) -> bool:
	var belief: String = _religious_belief(gs)
	if belief == "":
		return false
	for p in gs.players:
		if p.is_eliminated:
			continue
		var found: bool = false
		for s in gs.settlements:
			if s.owner_player_id == p.id and s.belief_id == belief:
				found = true
				break
		if not found:
			return false
	return true

# Whether a passed supreme-leadership motion may actually award the game to cand:
# the AP eligibility rule (religious), the UN Mass-Media requirement (secular), and
# the alliance-level "too big" rule (no win if the candidate's own alliance already
# casts >= diplo_too_big_share of the total vote weight) must all hold.
static func _diplo_win_allowed(gs, cand) -> bool:
	var body: String = str(gs.assembly.get("kind", ""))
	if body == "religious" and not _ap_all_eligible(gs):
		return false
	if body == "secular" and not cand.has_tech("mass_media"):
		return false
	var total: int = 0
	var ally: int = 0
	for m in _members(gs, body):
		var w: int = vote_weight(gs, m, body)
		total += w
		if m.alliance_id == cand.alliance_id:
			ally += w
	var too_big: int = gs.db.get_constant("diplo_too_big_share", 75)
	if total > 0 and (ally * 100) / total >= too_big:
		return false
	return true

# The pass threshold for a proposal: body-dependent for the supreme-leadership motion
# (UN un_diplo_pass_share / Apostolic Palace ap_diplo_pass_share), else the per-
# resolution pass_share (or the global resolution_pass_share default).
static func _pass_share_for(gs, pending: Dictionary) -> int:
	var res_id: String = str(pending.get("resolution_id", ""))
	if str(gs.db.get_resolution(res_id).get("effect", "")) == "diplomatic_victory":
		if str(gs.assembly.get("kind", "")) == "secular":
			return gs.db.get_constant("un_diplo_pass_share", 60)
		return gs.db.get_constant("ap_diplo_pass_share", 75)
	return int(pending.get("pass_share", gs.db.get_constant("resolution_pass_share", 50)))

# Whether the voting player's alliance is a subordinate (vassal) of the candidate's
# alliance — such a member automatically backs its overlord's candidate (§7.2).
static func _is_vassal_of(gs, player_id: int, cand) -> bool:
	if cand == null:
		return false
	var my_alliance = gs.get_player_alliance(player_id)
	if my_alliance == null:
		return false
	return my_alliance.is_subordinate_to >= 0 and my_alliance.is_subordinate_to == cand.alliance_id

# ── Helpers ────────────────────────────────────────────────────────────────────

# The member with the greatest vote weight (ties → lowest player id) — the natural
# candidate for a leadership election.
static func _front_runner(gs, members: Array) -> int:
	var body: String = str(gs.assembly.get("kind", ""))
	var best_id: int = -1
	var best_w: int = -1
	for p in members:
		var w: int = vote_weight(gs, p, body)
		if w > best_w or (w == best_w and (best_id < 0 or p.id < best_id)):
			best_w = w
			best_id = p.id
	return best_id

# The strongest alliance other than the resident's — the natural embargo target.
static func _embargo_target(gs, resident_pid: int) -> int:
	var resident = gs.get_player(resident_pid)
	var own_aid: int = resident.alliance_id if resident != null else -1
	var weight: Dictionary = {}
	for p in gs.players:
		if p.is_eliminated or p.alliance_id == own_aid:
			continue
		weight[p.alliance_id] = int(weight.get(p.alliance_id, 0)) + _player_population(gs, p.id)
	var best_aid: int = -1
	var best_w: int = -1
	for aid in weight:
		var w: int = int(weight[aid])
		if w > best_w or (w == best_w and (best_aid < 0 or int(aid) < best_aid)):
			best_w = w
			best_aid = int(aid)
	return best_aid

static func _player_population(gs, player_id: int) -> int:
	var pop: int = 0
	for s in gs.settlements:
		if s.owner_player_id == player_id:
			pop += s.population
	return pop

# Resolution ids the active body may put forward this session (excludes the
# resident election, which is auto-proposed only when the chair is vacant).
static func _eligible_resolutions(gs, body: String) -> Array:
	var out: Array = []
	for res_id in gs.db.resolutions:
		if res_id == "_comment" or res_id == "elect_resident":
			continue
		var res: Dictionary = gs.db.resolutions[res_id]
		var rb: String = str(res.get("body", "any"))
		if rb != "any" and rb != body:
			continue
		var eff: String = str(res.get("effect", ""))
		if eff == "diplomatic_victory":
			# The religious (Apostolic Palace) body proposes the supreme-leadership
			# motion only on its dedicated ap_diplo_victory_interval cadence, never
			# from the random pool; the secular (UN) body proposes it freely once a
			# Secretary-General is seated, gated on the win condition being enabled.
			if body == "religious" or not ("diplomatic" in gs.enabled_win_conditions):
				continue
		if eff == "religion_mandate" and str(gs.assembly.get("belief_id", "")) == "":
			continue
		out.append(res_id)
	return out

# Substitute the {candidate} {proposer} {target} {belief} tokens in a proposal's
# read-out text with the names involved.
static func _fill_text(gs, raw: String, candidate_pid: int, target_aid: int, belief: String) -> String:
	var cand_name: String = _player_name(gs, candidate_pid)
	var t: String = raw
	t = t.replace("{candidate}", cand_name)
	t = t.replace("{proposer}", cand_name)
	t = t.replace("{target}", _alliance_name(gs, target_aid))
	t = t.replace("{belief}", _belief_name(gs, belief))
	return t

static func _player_name(gs, player_id: int) -> String:
	var p = gs.get_player(player_id)
	return p.name if (p != null and p.name != "") else "an unnamed power"

static func _alliance_name(gs, alliance_id: int) -> String:
	var a = gs.get_alliance(alliance_id)
	if a == null or a.member_player_ids.empty():
		return "a foreign power"
	return _player_name(gs, int(a.member_player_ids[0]))

static func _belief_name(gs, belief: String) -> String:
	if belief == "":
		return "the faith"
	var b: Dictionary = gs.db.beliefs.get(belief, {})
	return str(b.get("name", belief))
