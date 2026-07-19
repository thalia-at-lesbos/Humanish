# Humanish — a turn-based 4X strategy game.
# Copyright (C) 2026 thalia-at-lesbos
# SPDX-License-Identifier: GPL-3.0-or-later
#
# This program is free software: you can redistribute it and/or modify it
# under the terms of the GNU General Public License as published by the Free
# Software Foundation, either version 3 of the License, or (at your option)
# any later version. See the LICENSE file for the full text and warranty
# disclaimer.

class_name TurnEngine

# Implements the §3 turn structure in strict pipeline order.
# Whole-world step runs once after all players have ended their turn.
# Per-player step runs for each active player.
# Per-settlement step runs inside per-player.

# Structure-effect key prefix for resource-conditional happiness (§15, e.g. the
# Hippodrome's `happiness_with_horse`); the suffix names the resource id.
const RES_HAPPINESS_PREFIX := "happiness_with_"

# ── Whole-world step ──────────────────────────────────────────────────────────

static func world_step(gs: GameState, hooks: Hooks) -> void:
	# 1. Resolve and expire pending trades
	if not hooks.run(IDs.Phase.WORLD_RESOLVE_TRADES, gs):
		_resolve_trades(gs)

	# 2. Advance shared alliance progress
	if not hooks.run(IDs.Phase.WORLD_ADVANCE_ALLIANCES, gs):
		_advance_alliances(gs)

	# First contact (§7): a player "meets" another once either side's unit or city
	# sees the other's unit, city, or border tile. Contact is mutual and permanent
	# (it is only ever appended to alliance.contacts), so a met player stays known
	# even if they later move out of view. Runs each world step alongside alliance
	# bookkeeping, independent of the per-phase hook.
	_detect_sight_contact(gs)

	# Economic organizations spread across settlements (§8). Cheap; runs each
	# world step independent of the per-phase hooks.
	EconOrgs.spread_all(gs, gs.rng)

	# Tributaries pay tribute to their overlords (§7).
	_collect_tribute(gs)

	# Vassalage maintenance (§7, Phase 8): drag each vassal into the overlord's wars
	# and out of any war the overlord has left (shared war/peace), then free any
	# vassal whose military has recovered past the liberation threshold. No RNG.
	Vassalage.world_tick(gs, gs.db)

	# Diplomatic memory decays toward zero once per world step (§7): old grievances
	# and favours fade, so attitude drifts back to neutral absent fresh acts.
	Diplomacy.decay(gs, gs.db)

	# War weariness decays in peace (§15.8): once a war is over, the weariness
	# accumulated against that enemy fades each world step. Runs alongside the
	# diplomatic-memory decay, independent of the per-phase hooks.
	_decay_war_fatigue(gs)

	# 3. Per-tile upkeep across the whole map
	if not hooks.run(IDs.Phase.WORLD_TILE_UPKEEP, gs):
		_tile_upkeep(gs)

	# 4. Spawn wild/raider settlements and units, then let them act (§9 scouts,
	#    camp alerts, mustered waves — provisional).
	if not hooks.run(IDs.Phase.WORLD_SPAWN_WILD, gs):
		WildForces.spawn_animals(gs, gs.rng)
		WildForces.spawn_turn(gs, gs.rng)
		WildForces.spawn_naval(gs, gs.rng)
		WildForces.spawn_raider_settlement(gs, gs.rng)
		WildAI.run(gs, gs.rng)

	# 5. Environmental degradation
	if not hooks.run(IDs.Phase.WORLD_ENVIRONMENTAL, gs):
		# Nuclear Plant meltdowns spread fallout around their settlement (§5.7)
		# and feed the global-warming nuke tally — run before the GW pass so a
		# fresh meltdown counts this turn.
		Nuclear.meltdown_tick(gs, gs.rng)
		# §11 global warming: building unhealthiness + nukes degrade random tiles.
		GlobalWarming.tick(gs, gs.rng)

	# 6. Assign/reassign special institutional sites (stub)
	if not hooks.run(IDs.Phase.WORLD_ASSIGN_SITES, gs):
		pass

	# 7. Resolve the §7.2 world-assembly lifecycle (sessions, elections,
	#    resolutions) — gated on a founding wonder. Diplomatic victory now flows
	#    solely from its UN election (Assembly.apply_effect "diplomatic_victory");
	#    the old standalone population poll was removed (see WinConditions).
	if not hooks.run(IDs.Phase.WORLD_ASSEMBLY, gs):
		Assembly.world_tick(gs, gs.rng)

	# 8. Increment turn counter
	if not hooks.run(IDs.Phase.WORLD_INCREMENT_TURN, gs):
		gs.turn_number += 1

	# 9. Activate next player(s)
	if not hooks.run(IDs.Phase.WORLD_ACTIVATE_PLAYER, gs):
		_set_next_active_player(gs)

	# 10. Test win conditions
	if not hooks.run(IDs.Phase.WORLD_CHECK_WIN, gs):
		var winner: int = WinConditions.check_all(gs)
		if winner >= 0:
			gs.winning_alliance_id = winner

# War-weariness peace decay (§15.8): for every alliance, each per-enemy fatigue
# entry whose war is over (neither side lists the other as at war) drops by the
# flat `war_weariness_decay_rate` (reference −1) and then keeps only
# `war_weariness_decay_peace_percent` (99%) of the remainder. Wars still hot do
# not decay. Integer math; entries reaching zero are erased so the dictionary
# (and the state hash) stays clean. No RNG.
static func _decay_war_fatigue(gs: GameState) -> void:
	var rate: int = gs.db.get_constant("war_weariness_decay_rate", -1)
	var keep_pct: int = gs.db.get_constant("war_weariness_decay_peace_percent", 99)
	for a in gs.alliances:
		for k in a.war_fatigue.keys():
			var eid: int = int(k)
			var enemy: Alliance = gs.get_alliance(eid)
			if a.is_at_war_with(eid) \
					or (enemy != null and enemy.is_at_war_with(a.id)):
				continue
			var v: int = int(a.war_fatigue[k]) + rate
			if v > 0:
				v = v * keep_pct / 100
			if v <= 0:
				a.war_fatigue.erase(k)
			else:
				a.war_fatigue[k] = v

# ── Per-player step ───────────────────────────────────────────────────────────

static func player_step(gs: GameState, player_id: int, hooks: Hooks) -> void:
	var player: Player = gs.get_player(player_id)
	if player == null or player.is_eliminated:
		return

	# Guarantee a capital before any maintenance/bureaucracy reads it: if the old
	# capital was lost, the Palace is rebuilt in the new capital (§6.1).
	_ensure_capital_palace(gs, player_id)

	# 1. Pre-turn bookkeeping
	if not hooks.run(IDs.Phase.PLAYER_BOOKKEEPING, gs, {"player_id": player_id}):
		pass  # AI planning would go here

	# 2. Assign workers to tiles (auto-assign if not overridden by command)
	if not hooks.run(IDs.Phase.PLAYER_ASSIGN_WORKERS, gs, {"player_id": player_id}):
		_auto_assign_workers(gs, player)

	# 3. Update treasury
	if not hooks.run(IDs.Phase.PLAYER_TREASURY, gs, {"player_id": player_id}):
		_update_treasury(gs, player)

	# 4. Apply research progress; then The Internet's tech-share (§15.7): the
	# project owner absorbs any tech already known widely enough, checked every
	# research phase (after normal completion, same hook — overriding
	# PLAYER_RESEARCH suppresses both).
	if not hooks.run(IDs.Phase.PLAYER_RESEARCH, gs, {"player_id": player_id}):
		_apply_research(gs, player)
		_apply_tech_share(gs, player)

	# 5. Intelligence accumulation
	if not hooks.run(IDs.Phase.PLAYER_INTELLIGENCE, gs, {"player_id": player_id}):
		_apply_intelligence(gs, player)

	# 6. Run per-settlement steps
	if not hooks.run(IDs.Phase.PLAYER_SETTLEMENTS, gs, {"player_id": player_id}):
		for s in gs.settlements:
			if s.owner_player_id == player_id:
				settlement_step(gs, s, player, hooks)

	# 6b. Cultural revolt / city flipping (§4.9). Tested after the owner's cities
	# have spread their culture this turn; flips are queued for the facade to
	# surface (notification + city_flipped signal).
	if not hooks.run(IDs.Phase.PLAYER_CULTURE_REVOLT, gs, {"player_id": player_id}):
		for f in CultureRevolt.process_player(gs, player_id, gs.rng, gs.db):
			gs.pending_flips.append(f)

	# 7. Tick down timed states
	if not hooks.run(IDs.Phase.PLAYER_TICK_STATES, gs, {"player_id": player_id}):
		_tick_states(gs, player)

	# 8. Re-validate policies; refresh trade routes; update war-fatigue
	if not hooks.run(IDs.Phase.PLAYER_VALIDATE_POLICIES, gs, {"player_id": player_id}):
		_validate_policies(gs, player)

	# 9. Process scripted/random events (skipped when the random-event system is
	# switched off for this game via the new-game menu, §9).
	if gs.events_enabled and not hooks.run(IDs.Phase.PLAYER_EVENTS, gs, {"player_id": player_id}):
		Events.process_player_events(player, gs, gs.rng)

	# 9b. Multi-turn quest tracking (§4): re-evaluate the player's active quests
	# (complete → queue reward; constraint violated → drop) and arm one new eligible
	# quest. Runs right after the random-event phase; rewards reuse the event verbs and
	# a 3-choice reward reuses the event pending-choice machinery.
	if gs.events_enabled and not hooks.run(IDs.Phase.PLAYER_QUESTS, gs, {"player_id": player_id}):
		Quests.process_player_quests(player, gs, gs.rng)

	# Found a belief if this player has newly become eligible for one (§8). No-op
	# (and no RNG draw) once every eligible belief is founded.
	Beliefs.try_found(player_id, gs, gs.rng)

	# Worked cottage-line tiles mature toward town (§8).
	_grow_cottages(gs, player)

	# Units that held position grow entrenchment and heal (§5.3, §5.6); a unit
	# does neither on a turn it moves or fights. Moving/attacking resets
	# entrenchment to 0 at the command site. Then reset flags for next turn.
	var ent_cap: int = gs.db.get_constant("entrenchment_cap", 25)
	var ent_per: int = gs.db.get_constant("entrenchment_per_turn", 5)
	for u in gs.units:
		if u.owner_player_id != player_id:
			continue
		# Heal-until-recovered stances hold position each turn: treat them as
		# stationary for entrenchment and healing, even though the player issued
		# no explicit move order. has_moved stays false so the heal path runs.
		var in_heal_stance: bool = u.is_sleep_until_healed or u.is_fortify_until_healed
		if not u.has_moved and not u.has_attacked:
			u.stationary_turns += 1
			var ent: int = u.stationary_turns * ent_per
			u.entrenchment = ent_cap if ent > ent_cap else ent
			_heal_unit(gs, u, player)
			# A worker that held its tile this turn advances its build order; on
			# completion the improvement is placed on the tile (§5). The build was
			# started by SimFacade._cmd_build_improvement on an earlier turn (which
			# set has_moved, so no progress is made on the issuing turn).
			if u.building_improvement != "":
				_advance_worker_build(gs, u)
			# Likewise a standalone chop/clear order advances and, on completion,
			# fells the feature and delivers any chop yield (§4.11).
			elif u.clearing_feature != "":
				_advance_worker_chop(gs, u)
		# Auto-wake when a heal-stance unit reaches full health (after healing above).
		if in_heal_stance and u.health >= 100:
			# Unit is now fully healed: drop the stance so it wakes idle next turn.
			u.is_sleep_until_healed = false
			if u.is_fortify_until_healed:
				u.is_fortify_until_healed = false
				u.is_fortified = false
		u.movement_left = u.movement_total
		u.has_moved = false
		u.has_attacked = false
		u.has_intercepted = false  # §15.14: one interception per interceptor per turn
		# Timed event states (§9 UNIT_STATE): tick the immobile / no-attack counters
		# down one per owner turn. While immobile the unit has no movement this turn.
		_tick_unit_event_states(u)

	# Era advancement (§1): recompute the player's era after every tech gained this
	# step (research in phase 4, a Great Scientist's instant tech in phase 6). Queues
	# a record for the facade to surface when the player crosses into a new era.
	Eras.refresh(player, gs.db, gs)

	# Persistent fog memory (§fog): commit "what this player saw this turn" — snapshot
	# every tile in their CURRENT visibility into gs.seen_memory. Deterministic and
	# render-independent (computed here in the pipeline, not from the scene), so the
	# serialized state stays on the determinism gate. Only players that render fog
	# need memory; AIs read full state, so skip them to bound save size.
	if not player.is_ai:
		SeenMemory.commit_visible(gs, player_id, player_visible_set(gs, player_id))

# Authoritative CURRENT-visibility set for a player as map-normalized "x,y" keys:
# unit sight ∪ city sight ∪ owned territory ∪ a territory_vision_ring fringe. Pure
# (no scene/facade refs) so both the turn pipeline (fog memory commit) and the
# facade's player_visible_tiles read one source of truth. Mirrors the sight model
# used by _detect_sight_contact and the fog renderer.
static func player_visible_set(gs: GameState, player_id: int) -> Dictionary:
	var db: DataDB = gs.db
	var seen: Dictionary = {}
	if db == null or gs.map == null:
		return seen
	var su: int = db.get_constant("unit_sight", 2)
	var sc: int = db.get_constant("city_sight", 3)
	for un in gs.units:
		if un.owner_player_id == player_id:
			for k in Visibility.visible_tiles(gs.map, db, un.x, un.y, su):
				seen[k] = true
	for s in gs.settlements:
		if s.owner_player_id == player_id:
			for k in Visibility.visible_tiles(gs.map, db, s.x, s.y, sc):
				seen[k] = true
	var ring: int = db.get_constant("territory_vision_ring", 1)
	if ring < 0:
		ring = 0
	for tile in gs.map.all_tiles():
		if tile.owner_player_id != player_id:
			continue
		seen["%d,%d" % [tile.x, tile.y]] = true
		if ring == 0:
			continue
		for nb in gs.map.tiles_in_range(tile.x, tile.y, ring):
			seen["%d,%d" % [nb.x, nb.y]] = true
	return seen

# ── Per-settlement step ───────────────────────────────────────────────────────

static func settlement_step(gs: GameState, s: Settlement,
		player: Player, hooks: Hooks) -> void:
	# A conquered city in revolt (§4.8) produces nothing — no growth, output,
	# culture, borders, or specialists — until order is restored. It still heals
	# its siege HP, and the occupation counter ticks down.
	if s.revolt_turns > 0:
		s.revolt_turns -= 1
		s.output_food = 0
		s.output_production = 0
		s.output_commerce = 0
		s.in_disorder = true
		_city_health_regen(gs, s)
		return

	# Growth
	if not hooks.run(IDs.Phase.SETTLEMENT_GROWTH, gs, {"settlement_id": s.id}):
		_settlement_growth(gs, s, player)

	# Production
	if not hooks.run(IDs.Phase.SETTLEMENT_PRODUCTION, gs, {"settlement_id": s.id}):
		_settlement_production(gs, s, player)

	# Culture accumulation + spread
	if not hooks.run(IDs.Phase.SETTLEMENT_CULTURE, gs, {"settlement_id": s.id}):
		_settlement_culture(gs, s, player)

	# Belief/affiliation processing
	if not hooks.run(IDs.Phase.SETTLEMENT_BELIEFS, gs, {"settlement_id": s.id}):
		Beliefs.spread_all(gs, gs.rng)

	# Decay/upkeep
	if not hooks.run(IDs.Phase.SETTLEMENT_DECAY, gs, {"settlement_id": s.id}):
		_settlement_upkeep(gs, s, player)

	# Special-person progress
	if not hooks.run(IDs.Phase.SETTLEMENT_SPECIALISTS, gs, {"settlement_id": s.id}):
		_special_person_progress(gs, s)

	# Siege HP recovers between assaults (§4.8).
	_city_health_regen(gs, s)

# ── Internal helpers ──────────────────────────────────────────────────────────

static func _settlement_growth(gs: GameState, s: Settlement, player: Player) -> void:
	var db: DataDB = gs.db

	# Compute output from worked tiles
	var total_food: int = 0
	var total_prod: int = 0
	var total_commerce: int = 0

	# Per-improvement civic output bonuses (§8): Universal Suffrage (town
	# production), Free Speech (town commerce), Caste System (workshop production),
	# State Property (watermill/farm production), Environmentalism (windmill
	# commerce). Summed once, applied per matching worked tile below.
	var town_prod: int = PolicyEffects.sum_int(player, db, "town_production")
	var town_comm: int = PolicyEffects.sum_int(player, db, "town_commerce")
	var workshop_prod: int = PolicyEffects.sum_int(player, db, "workshop_production")
	var watermill_farm_prod: int = PolicyEffects.sum_int(player, db, "watermill_farm_production")
	var windmill_comm: int = PolicyEffects.sum_int(player, db, "windmill_commerce")

	for wt in s.worked_tiles:
		var tile: Tile = gs.map.get_tile(int(wt[0]), int(wt[1]))
		if tile == null:
			continue
		var out: Array = TileOutput.compute(tile, db, player.technologies,
			gs.map.tile_has_river(tile.x, tile.y))
		total_food     += out[IDs.Output.FOOD]
		total_prod     += out[IDs.Output.PRODUCTION]
		total_commerce += out[IDs.Output.COMMERCE]
		match tile.improvement_id:
			"town":
				total_prod     += town_prod
				total_commerce += town_comm
			"workshop":
				total_prod     += workshop_prod
			"watermill", "farm":
				total_prod     += watermill_farm_prod
			"windmill":
				total_commerce += windmill_comm

	# Structures bonus (an obsolete structure yields nothing, §15.17)
	for struct_id in s.structures:
		if player != null and player.structure_obsolete(db, struct_id):
			continue
		var struct: Dictionary = db.get_structure(struct_id)
		total_food     += int(struct.get("output_delta", {}).get("food", 0))
		total_prod     += int(struct.get("output_delta", {}).get("production", 0))
		total_commerce += int(struct.get("output_delta", {}).get("commerce", 0))

	# Econ org bonus
	var org_delta: Array = EconOrgs.get_output_delta(gs, s)
	total_food     += org_delta[0]
	total_prod     += org_delta[1]
	total_commerce += org_delta[2]

	# Specialist economic output (§6.5): each assigned specialist yields its
	# per-head output vector from data/specialists.json. Food/production/commerce
	# fold into the city output here; science/culture/espionage route into their
	# own pipelines (_apply_research / _settlement_culture / _apply_intelligence).
	var spec_out: Dictionary = Specialists.settlement_output(db, s)
	total_food     += int(spec_out["food"])
	total_prod     += int(spec_out["production"])
	total_commerce += int(spec_out["commerce"])

	# Persistent per-structure event yield bonuses (§9 STRUCT_YIELD): each applies
	# only while its structure is present (Settlement.structure_yield filters on that).
	total_food     += s.structure_yield("food")
	total_prod     += s.structure_yield("production")
	total_commerce += s.structure_yield("commerce")
	# Mercantilism grants a free, population-free specialist per city; it is not an
	# assigned type, so it yields the generic specialist commerce directly (§8).
	total_commerce += PolicyEffects.sum_int(player, db, "free_specialist_per_city") \
		* db.get_constant("specialist_commerce", 3)

	# Golden Age: every worked tile yields +1 food/production/commerce (§14.4).
	var ga_bonus: int = GreatPeople.golden_age_tile_bonus(gs, player)
	if ga_bonus > 0:
		var worked: int = s.worked_tiles.size()
		total_food     += worked * ga_bonus
		total_prod     += worked * ga_bonus
		total_commerce += worked * ga_bonus

	# Bureaucracy boosts the capital's commerce and production (§8). The capital is
	# the player's earliest-founded surviving settlement.
	if _find_capital(gs, player.id) == s:
		total_commerce += Fixed.scale(total_commerce,
			PolicyEffects.sum_int(player, db, "capital_commerce"))
		total_prod += Fixed.scale(total_prod,
			PolicyEffects.sum_int(player, db, "capital_production"))

	# Trade routes (§8): each city runs a number of routes (granted by civics such
	# as Free Market) to other cities, each adding commerce. Added before blockade so
	# an enemy fleet chokes route income too.
	total_commerce += _trade_route_commerce(gs, s, player)

	# Naval blockade (§5.6): an enemy fleet sitting off a coastal city throttles its
	# trade, cutting its commerce while the blockade holds.
	var blockade: int = _blockade_penalty(gs, s, player)
	if blockade > 0:
		total_commerce -= Fixed.scale(total_commerce, blockade)

	# Anarchy (§8): during the interregnum after switching an established civic or
	# state religion the economy seizes up — settlements yield no commerce, so no
	# gold, research, culture, or intelligence accrues. Food and production hold.
	if player != null and player.transition_turns > 0:
		total_commerce = 0

	s.output_food       = total_food
	s.output_production = total_prod
	s.output_commerce   = total_commerce

	# Food box (§4.2): consumption is over non-angry citizens only, plus net
	# unhealthiness as a drain. _update_wellbeing populates the health figures read
	# via Settlement.health_rate(); the discontented count is last turn's value
	# (refreshed at the end of this step by _update_contentment).
	_update_wellbeing(gs, s, player, db)
	var fpc: int = db.get_constant("food_per_citizen", 2)
	var eaters: int = s.population - s.discontented
	if eaters < 0:
		eaters = 0
	var consumed: int = eaters * fpc
	var net_health: int = s.health_rate()
	if net_health < 0:
		consumed -= net_health  # net unhealthiness (negative) drains the food box
	var surplus: int = total_food - consumed

	s.food_store += surplus

	# Growth threshold (§4.2): the reference's pop-and-speed curve — an affine base +
	# per-pop term (not strictly proportional), scaled by the game pace and the
	# owner's era (later eras raise the food needed per growth; ages.json).
	var t_base: int = db.get_constant("growth_threshold_base", 20)
	var t_per_pop: int = db.get_constant("growth_threshold_per_pop", 2)
	var pace: Dictionary = db.get_pace(gs.pace_id)
	var pace_scale: int = int(pace.get("growth_scale", 100))
	var era_scale: int = Eras.growth_threshold_scale(Eras.player_era(player, db), db)
	var threshold: int = Fixed.scale(Fixed.scale(
		t_base + t_per_pop * s.population, pace_scale), era_scale)
	# Difficulty growth handicap (§2): a positive growth_bonus (easier levels) lowers
	# the food-to-grow threshold; a negative one (harder levels) raises it. Read from
	# data/difficulties.json. growth_bonus is bounded so (100 - it) stays positive. The
	# handicap is a player aid — applied to human players only (the AI's separate
	# ai_bonus is its handicap); see §2.2.
	if player != null and not player.is_ai:
		var diff_growth: int = int(db.get_difficulty(gs.difficulty_id).get("growth_bonus", 0))
		if diff_growth != 0:
			threshold = Fixed.scale(threshold, 100 - diff_growth)
			if threshold < 1:
				threshold = 1

	if s.food_store >= threshold:
		s.population += 1
		if s.population > s.peak_population:
			s.peak_population = s.population   # tracks the largest size ever (§4.8)
		var carry_frac: int = 50  # carry 50% of threshold
		if s.has_structure("granary") \
				and not (player != null and player.structure_obsolete(db, "granary")):
			carry_frac = int(db.get_structure("granary").get("effects", {}).get("food_carry_over", 50))
		var kept: int = Fixed.scale(threshold, carry_frac)
		# Cap granary carry-over at threshold × max_food_kept_percent/100 (§4.2): no
		# structure can let a city bank more than this fraction of its next threshold.
		var max_kept: int = Fixed.scale(threshold, db.get_constant("max_food_kept_percent", 75))
		s.food_store = kept if kept < max_kept else max_kept
		gs.pending_growth.append({
			"player_id": s.owner_player_id,
			"settlement_name": s.name,
			"population": s.population
		})
	elif s.food_store < 0:
		s.food_store = 0
		if s.population > 1:
			s.population -= 1

	# Contentment update
	_update_contentment(gs, s, player, db)

static func _update_wellbeing(gs: GameState, s: Settlement, player: Player, db: DataDB) -> void:
	var pos: int = 0
	var neg: int = s.population  # base negative from population
	for struct_id in s.structures:
		if player != null and player.structure_obsolete(db, struct_id):
			continue  # an obsolete structure's health effects stop (§15.17)
		var struct: Dictionary = db.get_structure(struct_id)
		pos += int(struct.get("health_bonus", 0))
		neg += int(struct.get("health_penalty", 0))
	# Owner-wide standing-structure unhealthiness (§15: `unhealthy_global`, Three
	# Gorges Dam +2): a structure anywhere in the owner's empire adds its amount
	# to EVERY city of that owner — this one included, other players unaffected.
	if player != null:
		for owner_s in gs.settlements:
			if owner_s.owner_player_id != player.id:
				continue
			for g_struct_id in owner_s.structures:
				if player.structure_obsolete(db, g_struct_id):
					continue
				neg += int(db.get_structure(g_struct_id).get("effects", {}) \
					.get("unhealthy_global", 0))
	# Adopted belief wellbeing (§8)
	if s.belief_id != "":
		pos += int(db.beliefs.get(s.belief_id, {}).get("health_bonus", 0))
	# Empire-wide civic health (Environmentalism, §8).
	pos += PolicyEffects.sum_int(player, db, "health_empire")
	# Leader/society trait wellbeing (§4.6): e.g. Expansive grants +2 health per city
	# (the original-reference value). Summed across the player's traits.
	if player != null:
		for trait_id in player.traits:
			pos += int(db.get_trait(trait_id).get("health_bonus", 0))
	# Difficulty wellbeing handicap (§2): per-level health bonus (easier levels) or
	# penalty (harder levels). A negative value lowers `pos`, widening the deficit. Read
	# from data/difficulties.json; a player aid applied to human players only (§2.2).
	if player != null and not player.is_ai:
		pos += int(db.get_difficulty(gs.difficulty_id).get("health_bonus", 0))
	# Fresh water from an adjacent water body or a river/oasis feature (§4.6)
	if _has_fresh_water(gs, s, db):
		pos += db.get_constant("fresh_water_health", 2)
	# Worked-tile feature wellbeing (§4.6): healthful features (forest, oasis) add to
	# positive; unhealthful ones (jungle, flood plains, fallout) add to negative. Mirrors
	# the worked-tile scan the happiness model uses for forests (§4.5).
	for wt in s.worked_tiles:
		var tile: Tile = gs.map.get_tile(int(wt[0]), int(wt[1]))
		if tile == null or tile.feature_id == "":
			continue
		var feat: Dictionary = db.get_feature(tile.feature_id)
		pos += int(feat.get("health_bonus", 0))
		neg += int(feat.get("health_penalty", 0))
	# Timed event wellbeing modifiers (§9 HEALTH_TIMED): a positive amount is a
	# temporary +health face (folded into pos), a negative one extra unhealthiness.
	for th in s.timed_health:
		var ha: int = int(th.get("amount", 0))
		if ha >= 0:
			pos += ha
		else:
			neg += -ha
	# Persistent per-structure event health bonuses (§9 STRUCT_YIELD, e.g. +1 health
	# for the drydock) — a flat wellbeing face while the structure stands.
	pos += s.structure_yield("health")
	s.wellbeing_positive = pos
	s.wellbeing_negative = neg
	s.wellbeing_deficit = max(0, neg - pos)

# A settlement has fresh water if its tile borders a river, carries an oasis, or
# any neighbour is a water tile (§4.6).
static func _has_fresh_water(gs: GameState, s: Settlement, db: DataDB) -> bool:
	var tile: Tile = gs.map.get_tile(s.x, s.y)
	if tile != null and tile.feature_id == "oasis":
		return true
	if gs.map.tile_has_river(s.x, s.y):
		return true
	for nb in gs.map.neighbours8(s.x, s.y):
		if db.get_terrain(nb.terrain_id).get("domain", "land") != "land":
			return true
	return false

static func _update_contentment(gs: GameState, s: Settlement, player: Player, db: DataDB) -> void:
	var pos: int = 0
	var neg_anger: int = 0  # anger percentage points

	# Size-related comfort (base 3 for first city)
	pos += max(0, 3 - (s.population / 4))

	# Difficulty comfort handicap (§2): per-level happiness bonus (easier levels) or
	# penalty (harder levels). Read from data/difficulties.json; a player aid applied to
	# human players only (§2.2).
	if player != null and not player.is_ai:
		pos += int(db.get_difficulty(gs.difficulty_id).get("happiness_bonus", 0))

	# Structures. A structure that requires the state religion (e.g. Cathedrals)
	# only comforts the city while that religion is the player's adopted one and is
	# present here (§8).
	var have_res: Dictionary = {}
	var have_res_known: bool = false
	var culture_rate_carriers: int = 0  # Σ standing `culture_rate_happiness` (§15.13, M2)
	for struct_id in s.structures:
		var struct: Dictionary = db.get_structure(struct_id)
		if not _structure_effect_active(db, struct_id, s, player):
			continue
		pos += int(struct.get("happiness_bonus", 0))
		culture_rate_carriers += int(struct.get("effects", {}).get("culture_rate_happiness", 0))
		# Resource-conditional comfort (§15: `happiness_with_<resource>`, e.g. the
		# Hippodrome's +1 while Horse is accessible): counts only while the owner
		# can access the named resource — the same availability rule units use
		# (EconOrgs.accessible_resources), so losing the resource loses the face.
		for fx_key in struct.get("effects", {}):
			if not str(fx_key).begins_with(RES_HAPPINESS_PREFIX):
				continue
			if not have_res_known:
				have_res = EconOrgs.accessible_resources(gs, player.id)
				have_res_known = true
			if have_res.has(str(fx_key).substr(RES_HAPPINESS_PREFIX.length())):
				pos += int(struct["effects"][fx_key])

	# Culture-rate building happiness (§15.13, wiring item M2): entertainment-tier
	# carriers grant happiness scaled by the owner's culture allocation rate —
	# Σ(standing carrier values) × culture% / 100, truncated ONCE over the per-city
	# sum (not per building); no cap. Obsolete/inactive carriers were already
	# filtered out of the sum by _structure_effect_active above.
	if culture_rate_carriers != 0 and player != null:
		pos += culture_rate_carriers * player.slider_culture / 100

	# Adopted belief comfort (§8)
	if s.belief_id != "":
		pos += int(db.beliefs.get(s.belief_id, {}).get("happiness_bonus", 0))

	# Garrison comfort: stationed military units reassure the populace (§4.5)
	var garrison: int = 0
	for u in gs.units:
		if u.owner_player_id == player.id and u.x == s.x and u.y == s.y:
			if db.get_unit(u.unit_type_id).get("classification", "") != "civilian":
				garrison += 1
	if garrison > 0:
		var g_bonus: int = garrison * db.get_constant("garrison_happiness_per_unit", 1)
		var g_cap: int = db.get_constant("garrison_happiness_cap", 3)
		pos += g_cap if g_bonus > g_cap else g_bonus
		# Hereditary Rule adds further, uncapped happiness per garrisoned unit (§8).
		pos += garrison * PolicyEffects.sum_int(player, db, "happiness_per_garrison")

	# Civic happiness effects (§8). Barracks comfort (Nationhood), per-religion
	# comfort (Free Religion; the model carries one belief per city), happiness per
	# worked forest/jungle tile (Environmentalism), and a flat bonus in the empire's
	# largest cities (Representation).
	if s.has_structure("barracks") \
			and not (player != null and player.structure_obsolete(db, "barracks")):
		pos += PolicyEffects.sum_int(player, db, "barracks_happiness")
	if s.belief_id != "":
		pos += PolicyEffects.sum_int(player, db, "happiness_per_religion")
	var forest_bonus: int = PolicyEffects.sum_int(player, db, "happiness_per_forest")
	if forest_bonus > 0:
		var forested: int = 0
		for wt in s.worked_tiles:
			var ft: Tile = gs.map.get_tile(int(wt[0]), int(wt[1]))
			if ft != null and (ft.feature_id == "forest" or ft.feature_id == "jungle"):
				forested += 1
		pos += forested * forest_bonus
	var largest_bonus: int = PolicyEffects.sum_int(player, db, "happiness_largest_cities")
	if largest_bonus > 0:
		var top_n: int = db.get_constant("policy_largest_cities_count", 5)
		if s.id in PolicyEffects.largest_city_ids(gs, player.id, top_n):
			pos += largest_bonus

	# Overcrowding anger above a comfortable size (§4.5)
	var crowd_thresh: int = db.get_constant("overcrowding_threshold", 6)
	if s.population > crowd_thresh:
		neg_anger += (s.population - crowd_thresh) * db.get_constant("overcrowding_anger_per_pop", 3)

	# Policy anger
	for cat in player.policies:
		var pol_id: String = player.policies[cat]
		var pol: Dictionary = db.policies.get("policies", {}).get(pol_id, {})
		neg_anger += int(pol.get("anger_modifier", 0))

	# Civic-pressure anger (§15.9): rivals running a `civic_percent_anger` civic
	# (Emancipation) anger this player's cities while the player does not run it,
	# scaled by the adopter share. No RNG; see PolicyEffects.civic_pressure_anger.
	neg_anger += PolicyEffects.civic_pressure_anger(gs, player, db)

	# Rush penalty
	if s.rush_anger_turns > 0:
		neg_anger += 20

	# War-fatigue anger from the player's alliance (§4.5, §7)
	var fa: Alliance = gs.get_player_alliance(player.id)
	if fa != null:
		var fatigue_total: int = 0
		for k in fa.war_fatigue:
			fatigue_total += int(fa.war_fatigue[k])
		var war_anger: int = fatigue_total / max(1, db.get_constant("war_fatigue_anger_divisor", 4))
		# Police State suppresses a share of war anger (§8).
		var war_reduction: int = PolicyEffects.sum_int(player, db, "war_anger_reduction")
		if war_reduction > 0:
			war_anger -= Fixed.scale(war_anger, war_reduction)
		neg_anger += war_anger

	# Timed event happiness modifiers (§9): a positive amount is a temporary happy
	# face (folded into pos), a negative one a temporary angry face contributing
	# |amount| flat discontented citizens (added after the percentage conversion).
	var timed_neg: int = 0
	for tm in s.timed_happiness:
		var a: int = int(tm.get("amount", 0))
		if a >= 0:
			pos += a
		else:
			timed_neg += -a

	# Persistent per-structure event happiness bonuses (§9 STRUCT_YIELD, e.g. +1 happy
	# for the hospital) — a flat comfort face while the structure stands.
	pos += s.structure_yield("happiness")

	# Convert anger percentage to negative sentiment citizens
	var anger_div: int = db.get_constant("anger_divisor", 100)
	var neg_citizens: int = Fixed.scale(s.population, neg_anger) + timed_neg

	s.positive_sentiment = pos
	s.negative_sentiment = neg_citizens
	s.discontented = max(0, min(s.population, neg_citizens - pos))
	s.in_disorder = (s.discontented >= s.population)

static func _settlement_production(gs: GameState, s: Settlement,
		player: Player) -> void:
	if s.in_disorder or s.production_queue.empty():
		return

	var db: DataDB = gs.db
	var pace: Dictionary = db.get_pace(gs.pace_id)
	var pace_scale: int = int(pace.get("build_scale", 100))
	var prod: int = Fixed.scale(s.output_production, pace_scale)

	# AI production handicap (§2.2): higher difficulties give AI extra hammers.
	# Mirrors the human-only growth handicap block; gated is_ai so the two aids
	# stay symmetric and never cross-apply.
	if player != null and player.is_ai:
		var ai_bonus: int = int(db.get_difficulty(gs.difficulty_id).get("ai_bonus", 0))
		if ai_bonus != 0:
			prod = Fixed.scale(prod, 100 + ai_bonus)

	var item: Dictionary = s.production_queue[0]
	# Percentage yield chain (§4.3): structure and civic +% production modifiers
	# stack additively and apply once (multiplicatively on the base) via
	# Fixed.apply_stacked_bonus — distinct from the flat deltas below.
	var pct_mods: int = _production_percent_mods(gs, s, player, db, item)
	if pct_mods < -100:
		pct_mods = -100  # base × max(0, 100 + Σmods)/100
	prod = Fixed.apply_stacked_bonus(prod, pct_mods)
	# Flat civic production deltas depend on what is being built (§8).
	prod += _policy_production_delta(gs, s, player, db, item)
	if prod < 0:
		prod = 0
	s.production_store += prod

	var cost: int = _item_cost(item, db, player, pace)
	if cost <= 0:
		return

	if s.production_store >= cost:
		s.production_store -= cost
		_complete_item(gs, s, player, item)
		s.production_queue.remove(0)

# Sum of percentage production modifiers active in a settlement for the item at
# the head of its queue (§4.3). Structure bonuses apply to all production — Forge
# / Factory / Assembly Plant `production_bonus`, a power plant's own
# `power_production_bonus`, and the Factory's `powered_production_bonus` once the
# city has power. Military builds additionally collect the structure
# `military_production_city` (Heroic Epic / Military Academy) and the civic
# `military_production` (Police State). Leader traits add their build-speed
# modifiers for the item (B4: `double_production_structures` /
# `unit_production_modifiers` via TraitEffects — Aggressive doubles barracks,
# Imperialistic trains settlers +50%, …). All are summed so they stack
# additively and the caller applies them once via Fixed.apply_stacked_bonus.
static func _production_percent_mods(gs: GameState, s: Settlement,
		player: Player, db: DataDB, item: Dictionary) -> int:
	var pct: int = TraitEffects.production_pct(player, db, item)
	var powered: bool = _settlement_has_power(s, db, player)
	for sid in s.structures:
		if not _structure_effect_active(db, sid, s, player):
			continue
		var st: Dictionary = db.get_structure(sid)
		pct += int(st.get("production_bonus", 0))
		var eff: Dictionary = st.get("effects", {})
		pct += int(eff.get("power_production_bonus", 0))
		if powered:
			pct += int(eff.get("powered_production_bonus", 0))
	if item.get("type", "unit") == "unit" and _is_military_unit(db, item.get("id", "")):
		for sid in s.structures:
			if not _structure_effect_active(db, sid, s, player):
				continue
			pct += int(db.get_structure(sid).get("effects", {}).get("military_production_city", 0))
		pct += PolicyEffects.sum_int(player, db, "military_production")
	return pct

# Whether any built, active structure supplies power to the city (§4.3) — the gate
# for the Factory's powered production bonus. An obsolete plant powers nothing.
static func _settlement_has_power(s: Settlement, db: DataDB, player: Player = null) -> bool:
	for sid in s.structures:
		if player != null and player.structure_obsolete(db, sid):
			continue
		if bool(db.get_structure(sid).get("effects", {}).get("provides_power", false)):
			return true
	return false

# Per-turn FLAT production adjustments from active civics for the item at the head
# of the queue (§8): Organized Religion's flat bonus for religious buildings, and
# Pacifism's drain per garrisoned military unit. Percentage modifiers are handled
# separately by _production_percent_mods (§4.3).
static func _policy_production_delta(gs: GameState, s: Settlement,
		player: Player, db: DataDB, item: Dictionary) -> int:
	var delta: int = 0
	var itype: String = item.get("type", "unit")
	var iid: String = item.get("id", "")
	if itype == "structure":
		if PolicyEffects.is_religious_structure(db, iid):
			delta += PolicyEffects.sum_int(player, db, "religious_building_production")
	# Pacifism: each garrisoned military unit drains production (effect is negative).
	var drain: int = PolicyEffects.sum_int(player, db, "production_per_military_unit")
	if drain != 0:
		var mil: int = 0
		for u in gs.units:
			if u.owner_player_id == player.id and u.x == s.x and u.y == s.y \
					and _is_military_unit(db, u.unit_type_id):
				mil += 1
		delta += mil * drain
	return delta

# A unit type that counts as "military" for civic effects: anything that is not a
# civilian or a Great Person.
static func _is_military_unit(db: DataDB, unit_id: String) -> bool:
	var cls: String = db.get_unit(unit_id).get("classification", "")
	return cls != "" and cls != "civilian" and cls != "great_person"

# Whether a structure's gameplay effects are live in this settlement (§8, §15.17).
# An obsolete structure (owner researched its `obsoleted_by` tech) never is; a
# structure flagged `requires_state_religion` (the Cathedral tier) only takes
# effect while the city follows the player's adopted state religion; everything
# else is always active.
static func _structure_effect_active(db: DataDB, struct_id: String,
		s: Settlement, player: Player) -> bool:
	if player != null and player.structure_obsolete(db, struct_id):
		return false
	var st: Dictionary = db.get_structure(struct_id)
	if not bool(st.get("effects", {}).get("requires_state_religion", false)):
		return true
	if player == null or player.state_religion == "":
		return false
	return s.belief_id == player.state_religion

static func _item_cost(item: Dictionary, db: DataDB, player: Player,
		pace: Dictionary) -> int:
	var pace_scale: int = int(pace.get("build_scale", 100))
	var itype: String = item.get("type", "unit")
	var iid: String = item.get("id", "")
	var base: int = 0
	match itype:
		"unit":
			base = int(db.get_unit(iid).get("cost", 60))
		"structure":
			base = int(db.get_structure(iid).get("cost", 60))
		"project":
			base = int(db.projects.get(iid, {}).get("cost", 500))
	return Fixed.scale(base, pace_scale)

# ── Population rush ("whipping", §15.2) ──────────────────────────────────────
# Hammers one sacrificed citizen buys: `rush_production_per_pop` (reference 30)
# scaled by the pace's `hurry_scale` (reference hurry percent 67/100/150/300),
# so whip pop counts stay constant across paces (item costs scale the same way).
static func rush_hammers_per_pop(db: DataDB, pace: Dictionary) -> int:
	var per: int = Fixed.scale(db.get_constant("rush_production_per_pop", 30),
		int(pace.get("hurry_scale", 100)))
	return per if per > 0 else 1

# Hammers a population rush must still cover for the head queue item. An item
# queued this very turn costs `new_hurry_modifier` % extra (reference
# NEW_HURRY_MODIFIER 50) — the surcharge for whipping a just-queued order.
static func rush_remaining_cost(gs: GameState, s: Settlement,
		player: Player) -> int:
	if s.production_queue.empty():
		return 0
	var item: Dictionary = s.production_queue[0]
	var pace: Dictionary = gs.db.get_pace(gs.pace_id)
	var cost: int = _item_cost(item, gs.db, player, pace)
	var remaining: int = cost - s.production_store
	if remaining <= 0:
		return 0
	if int(item.get("queued_turn", -1)) == gs.turn_number:
		remaining = Fixed.scale_up(remaining,
			gs.db.get_constant("new_hurry_modifier", 50))
	return remaining

# Population a whip of the head queue item sacrifices: ceil(remaining/per_pop),
# never more than the remaining cost requires (§15.2). 0 = nothing to rush.
static func rush_pop_cost(gs: GameState, s: Settlement, player: Player) -> int:
	var remaining: int = rush_remaining_cost(gs, s, player)
	if remaining <= 0:
		return 0
	var per: int = rush_hammers_per_pop(gs.db, gs.db.get_pace(gs.pace_id))
	return (remaining + per - 1) / per

static func _complete_item(gs: GameState, s: Settlement,
		player: Player, item: Dictionary) -> void:
	var itype: String = item.get("type", "unit")
	var iid: String = item.get("id", "")
	match itype:
		"unit":
			var u := Unit.new()
			u.id = gs.next_unit_id()
			u.unit_type_id = iid
			u.owner_player_id = player.id
			u.x = s.x; u.y = s.y
			var udata: Dictionary = gs.db.get_unit(iid)
			u.base_strength = int(udata.get("base_strength", 5))
			u.movement_total = int(udata.get("movement", 120))
			u.movement_left = u.movement_total
			# Civic starting experience for newly trained military units (§8):
			# Vassalage's flat bonus, plus Theocracy's bonus when the unit is raised
			# in a city that follows the player's adopted state religion.
			if _is_military_unit(gs.db, iid):
				var xp: int = PolicyEffects.sum_int(player, gs.db, "new_unit_xp")
				if player.state_religion != "" and s.belief_id == player.state_religion:
					xp += PolicyEffects.sum_int(player, gs.db, "state_religion_unit_xp")
				# Building-XP: barracks/stable/drydock/airport/West Point/Pentagon and
				# the unique replacements grant starting experience by unit category (§5.5).
				xp += _structure_unit_xp(gs, s, player, iid)
				u.experience = xp
				# Earned XP may already cross a promotion threshold; then layer on any
				# building-granted free promotions (Dun, Ikhanda, Trading Post, …).
				CombatApply.award_promotions(gs, u)
				_grant_free_promotions(gs, u, s)
			gs.units.append(u)
		"structure":
			if iid == "palace":
				# The Palace is the single seat of government: building it in a
				# city moves the capital there, so strip it from the player's
				# other cities (§6.1). _find_capital then reports this city.
				for other in gs.settlements:
					if other.owner_player_id == player.id and other != s:
						other.structures.erase("palace")
				if not s.has_structure("palace"):
					s.structures.append("palace")
			elif not s.has_structure(iid):
				s.structures.append(iid)
			var sdata: Dictionary = gs.db.get_structure(iid)
			if sdata.get("is_wonder", false) or sdata.get("is_national_wonder", false):
				gs.pending_productions.append({
					"player_id": player.id,
					"settlement_name": s.name,
					"item_type": "structure",
					"item_id": iid,
					"item_name": str(sdata.get("name", iid))
				})
		"project":
			var proj: Dictionary = gs.db.projects.get(iid, {})
			if Projects.is_endgame(proj):
				var alliance_id: int = player.alliance_id
				if not gs.endgame_project_stages.has(alliance_id):
					gs.endgame_project_stages[alliance_id] = 0
				gs.endgame_project_stages[alliance_id] += 1
			elif not proj.empty() and Projects.grantable(gs, player, iid):
				# §15.7 effects project (SDI / The Internet): record it on the
				# player so Projects.effect_int sees it. A world-unique project
				# already claimed by a rival grants nothing (hammers lost).
				player.projects.append(iid)
			gs.pending_productions.append({
				"player_id": player.id,
				"settlement_name": s.name,
				"item_type": "project",
				"item_id": iid,
				"item_name": str(proj.get("name", iid))
			})

# Starting experience a newly built military unit draws from its city's (and the
# empire's) buildings, by unit category (§5.5). Per-settlement keys come from the
# structures in `s`; `unit_xp_all_cities` (Pentagon) is empire-wide.
static func _structure_unit_xp(gs: GameState, s: Settlement,
		player: Player, iid: String) -> int:
	var db: DataDB = gs.db
	if not _is_military_unit(db, iid):
		return 0
	var ud: Dictionary = db.get_unit(iid)
	var dom: String = str(ud.get("domain", "land"))
	var cls: String = str(ud.get("classification", ""))
	var total: int = 0
	for sid in s.structures:
		if player != null and player.structure_obsolete(db, sid):
			continue  # an obsolete structure trains no one (§15.17: Stable → Advanced Flight)
		var fx: Dictionary = db.get_structure(sid).get("effects", {})
		total += int(fx.get("military_xp", 0))
		total += int(fx.get("military_xp_city", 0))
		if dom == "land":
			total += int(fx.get("land_xp", 0))
		elif dom == "sea":
			total += int(fx.get("naval_xp", 0))
		elif dom == "air":
			total += int(fx.get("air_xp", 0))
		if cls == "mounted" or cls == "armor":
			total += int(fx.get("mounted_xp", 0))
		if cls == "ranged":
			total += int(fx.get("archery_xp", 0))
		if cls == "siege":
			total += int(fx.get("siege_xp", 0))
	# Empire-wide unit XP (Pentagon's unit_xp_all_cities) from any owned city.
	for other in gs.settlements:
		if other.owner_player_id != player.id:
			continue
		for sid in other.structures:
			if player != null and player.structure_obsolete(db, sid):
				continue
			total += int(db.get_structure(sid).get("effects", {}).get("unit_xp_all_cities", 0))
	return total

# Grant building-conferred free promotions to a freshly built unit (§5.5): a named
# `free_promotion` (Dun→guerrilla1, Trading Post→navigation1, Red Cross→medic1)
# that suits the unit's class/domain, and `free_promotion_all` (Ikhanda) which
# grants one otherwise-eligible promotion. A named free promotion bypasses prereqs.
static func _grant_free_promotions(gs: GameState, u: Unit, s: Settlement) -> void:
	var db: DataDB = gs.db
	var ud: Dictionary = db.get_unit(u.unit_type_id)
	var cls: String = str(ud.get("classification", ""))
	var dom: String = str(ud.get("domain", "land"))
	var owner: Player = gs.get_player(s.owner_player_id)
	for sid in s.structures:
		if owner != null and owner.structure_obsolete(db, sid):
			continue  # an obsolete structure confers nothing (§15.17: Dun → Rifling)
		var fx: Dictionary = db.get_structure(sid).get("effects", {})
		var fp: String = str(fx.get("free_promotion", ""))
		if fp != "" and not (fp in u.promotions):
			if CombatApply.promo_applies(db.get_promotion(fp), cls, dom):
				u.promotions.append(fp)
		if bool(fx.get("free_promotion_all", false)):
			var pick: String = CombatApply.pick_promotion(gs, u)
			if pick != "":
				u.promotions.append(pick)

# Cottage-line maturation (§8, §15.9): each worked tile carrying an improvement
# with an `upgrades_to` ages one step per turn; on reaching the (modifier-scaled)
# `upgrade_turns` it advances to the next stage (cottage → hamlet → village →
# town). A civic `improvement_upgrade_rate_modifier` percentage (Emancipation
# +100, the reference value) shortens the threshold: turns × 100 / (100 + mod),
# truncating, never below 1. Only worked tiles grow, mirroring the reference
# model. Pure age bookkeeping on the tile; output is gated by tech in TileOutput
# as usual.
# Trade-route commerce for a city (§8). A city runs `trade_routes_base` plus the
# civic `trade_route_per_city` (Free Market) routes, each to a distinct other city;
# Mercantilism's `no_foreign_trade_routes` restricts them to the player's own
# cities, and routes never run to a city the player is at war with. Each route's
# yield is a base plus a share of the two cities' combined size, with a bonus for
# foreign partners. Partners are chosen highest-yield first, deterministically.
static func _trade_route_commerce(gs: GameState, s: Settlement, player: Player) -> int:
	var db: DataDB = gs.db
	var routes: int = db.get_constant("trade_routes_base", 0) \
		+ PolicyEffects.sum_int(player, db, "trade_route_per_city")
	if routes <= 0:
		return 0
	var no_foreign: bool = PolicyEffects.has_flag(player, db, "no_foreign_trade_routes")
	var cands: Array = []  # [{yield, id}]
	for o in gs.settlements:
		if o.id == s.id:
			continue
		if o.owner_player_id != player.id:
			if no_foreign:
				continue
			if gs.are_at_war(player.id, o.owner_player_id):
				continue
		var dist: int = gs.map.distance(s.x, s.y, o.x, o.y)
		cands.append({"y": _route_yield(db, s, o, dist, player), "id": o.id})
	# Selection-pick the highest-yield routes (ties broken by lower settlement id).
	var total: int = 0
	var taken: int = 0
	var n: int = cands.size()
	var used: Dictionary = {}
	while taken < routes and taken < n:
		var best: int = -1
		for i in range(n):
			if used.has(i):
				continue
			if best == -1:
				best = i
			elif cands[i]["y"] > cands[best]["y"] \
					or (cands[i]["y"] == cands[best]["y"] and cands[i]["id"] < cands[best]["id"]):
				best = i
		if best == -1:
			break
		used[best] = true
		total += int(cands[best]["y"])
		taken += 1
	return total

# Commerce a single trade route yields between cities `s` and `o` at `dist` tiles.
static func _route_yield(db: DataDB, s: Settlement, o: Settlement,
		dist: int, player: Player) -> int:
	var y: int = db.get_constant("trade_route_base_yield", 1)
	y += ((s.population + o.population) * db.get_constant("trade_route_pop_pct", 25)) / 100
	if o.owner_player_id != player.id:
		y += db.get_constant("trade_route_foreign_bonus", 2)
	return y if y >= 0 else 0

# Naval-blockade commerce penalty (§5.6): a coastal city with a hostile naval unit
# (wild, or an enemy at war) sitting within `blockade_range` has its trade choked,
# returning `blockade_commerce_penalty` percent. 0 for inland cities or when no
# hostile fleet is in range.
static func _blockade_penalty(gs: GameState, s: Settlement, player: Player) -> int:
	var db: DataDB = gs.db
	if not _is_coastal(gs, s.x, s.y):
		return 0
	var reach: int = db.get_constant("blockade_range", 2)
	for u in gs.units:
		if u.owner_player_id == player.id:
			continue
		if db.get_unit(u.unit_type_id).get("domain", "") != "sea":
			continue
		if u.owner_player_id != -2 and not gs.are_at_war(player.id, u.owner_player_id):
			continue
		if gs.map.distance(s.x, s.y, u.x, u.y) <= reach:
			return db.get_constant("blockade_commerce_penalty", 50)
	return 0

# True when a tile borders water (a settlement on it is coastal).
static func _is_coastal(gs: GameState, x: int, y: int) -> bool:
	for nb in gs.map.neighbours8(x, y):
		var lf: String = str(gs.db.get_terrain(nb.terrain_id).get("landform", ""))
		if lf == "water" or lf == "deep_water":
			return true
	return false

static func _grow_cottages(gs: GameState, player: Player) -> void:
	var db: DataDB = gs.db
	var rate: int = 100 + PolicyEffects.sum_int(player, db, "improvement_upgrade_rate_modifier")
	if rate < 1:
		rate = 1
	for s in gs.settlements:
		if s.owner_player_id != player.id:
			continue
		for cell in s.worked_tiles:
			var t: Tile = gs.map.get_tile(cell[0], cell[1])
			if t == null or t.improvement_id == "":
				continue
			var imp: Dictionary = db.get_improvement(t.improvement_id)
			var next_id: String = str(imp.get("upgrades_to", ""))
			if next_id == "":
				continue
			t.improvement_age += 1
			var need: int = int(imp.get("upgrade_turns", 0))
			if need > 0:
				var scaled: int = (need * 100) / rate
				if scaled < 1:
					scaled = 1
				if t.improvement_age >= scaled:
					t.improvement_id = next_id
					t.improvement_age = 0

# Worker-speed percentage modifiers (§15.9): the number of turns a worker order
# (improvement, road, chop/clear) takes is the base turns scaled by the summed
# percentage bonus, truncating, never below 1: turns × 100 / (100 + Σmod).
# Sources (all reference-confirmed values):
#   • civics carrying `worker_speed_modifier` in `effects` (Serfdom +50),
#   • the player's standing structures carrying `worker_speed_modifier` in
#     `effects` (Hagia Sophia +50; summed per instance like every structure
#     effect — a world wonder exists once, so it never stacks in practice),
#   • the unit's `work_rate` (default 100; the reference Fast Worker is ALSO
#     100 — its edge is movement — so the key ships as pure mechanism).
# The reference has NO golden-age worker effect, so none is applied here. The
# reference Steam Power tech (+50, which obsoletes Hagia Sophia) is not wired:
# structure obsolescence is unmodelled, and adding the tech without it would
# double up. This helper is the single site of the math; every place that seeds
# `build_turns_left` (SimFacade improvement/road/clear handlers) calls it.
static func worker_build_turns(gs: GameState, u: Unit, base_turns: int) -> int:
	var db: DataDB = gs.db
	var mod: int = int(db.get_unit(u.unit_type_id).get("work_rate", 100)) - 100
	var player: Player = gs.get_player(u.owner_player_id)
	if player != null:
		mod += PolicyEffects.sum_int(player, db, "worker_speed_modifier")
		for s in gs.settlements:
			if s.owner_player_id != player.id:
				continue
			for sid in s.structures:
				if player.structure_obsolete(db, sid):
					continue  # Hagia Sophia's +50 stops at Steam Power (§15.17)
				mod += int(db.get_structure(sid).get("effects", {}) \
					.get("worker_speed_modifier", 0))
		# Researched techs carrying `worker_speed_modifier` (§15.9: Steam Power
		# +50 — the tech that obsoletes Hagia Sophia, so the two never stack).
		for tid in player.technologies:
			mod += int(db.get_technology(str(tid)).get("worker_speed_modifier", 0))
	if mod < -99:
		mod = -99  # keep the divisor positive; a build never stalls forever
	var turns: int = (base_turns * 100) / (100 + mod)
	return turns if turns >= 1 else 1

# Advance a worker's in-progress improvement build by one turn. When the build
# completes, the improvement is placed on the worker's tile and the build state
# is cleared; a record is queued for SimFacade to surface as a notification.
# Called once per turn for a worker that held its tile (see player_step).
static func _advance_worker_build(gs: GameState, u: Unit) -> void:
	if u.build_turns_left > 0:
		u.build_turns_left -= 1
	if u.build_turns_left > 0:
		return
	complete_worker_build(gs, u)

# Finalize an in-progress improvement build: place the improvement on the worker's
# tile (applying any feature clearing), clear the build state, queue a completion
# record for SimFacade to surface, and — for a single-use builder (work boat,
# data flag `consumed_on_use`, §5) — remove the unit. Shared by the multi-turn
# worker path (_advance_worker_build, on completion) and the instant work-boat
# path (SimFacade._cmd_build_improvement, fired the moment the command is issued).
# Returns true when the build was consumed (a single-use builder removed itself),
# so the caller can clear any UI selection of that unit.
static func complete_worker_build(gs: GameState, u: Unit) -> bool:
	var consumed: bool = false
	var tile: Tile = gs.map.get_tile(u.x, u.y)
	if tile != null:
		var imp_id: String = u.building_improvement
		var entry: Dictionary = {
			"player_id": u.owner_player_id,
			"improvement_id": imp_id,
			"x": u.x, "y": u.y
		}
		# Clearing (§5): a removable vegetation feature (forest/jungle) is stripped
		# when the new improvement does not preserve it. A felled forest delivers its
		# chop_yield as production to the nearest owned city, scaled down by distance.
		_apply_feature_clearing(gs, u, tile, imp_id, entry)
		tile.improvement_id = imp_id
		# Reset cottage-line maturation so a freshly placed improvement starts fresh.
		tile.improvement_age = 0
		gs.pending_improvements.append(entry)
	u.building_improvement = ""
	u.build_turns_left = 0
	# Single-use builders (work boats) are consumed when their improvement
	# completes (data flag `consumed_on_use` on the unit, §5): the unit is removed
	# from state, unlike a land worker which persists. Only fires when a build
	# actually completed on a tile (tile != null), so it happens exactly once.
	if tile != null and "consumed_on_use" in gs.db.get_unit(u.unit_type_id).get("tags", []):
		Stack.remove_unit(gs.units, u.id)
		consumed = true
	return consumed

# When an improvement completes on a tile carrying a removable feature (forest,
# jungle), the feature is cleared unless the improvement preserves it — camps,
# lumbermills, forest preserves and forts keep their forest (flagged
# preserves_feature in data/improvements.json), as does any improvement that
# requires that feature. Clearing a forest delivers its chop_yield to the nearest
# owned city as production: the researched chop tech (Mathematics) raises the
# yield by chop_yield_tech_bonus_pct, and the full amount lands when the chopped
# tile is inside the player's borders, scaled to chop_outside_borders_pct when it
# is not. Jungle has no chop_yield and clears for nothing. Records the outcome on
# `entry` for the facade to surface.
static func _apply_feature_clearing(gs: GameState, u: Unit, tile: Tile,
		imp_id: String, entry: Dictionary) -> void:
	var feat_id: String = tile.feature_id
	if feat_id == "":
		return
	var feat: Dictionary = gs.db.get_feature(feat_id)
	if not bool(feat.get("removable", false)):
		return
	var imp: Dictionary = gs.db.get_improvement(imp_id)
	if bool(imp.get("preserves_feature", false)) \
			or str(imp.get("requires_feature", "")) == feat_id:
		return
	_chop_tile(gs, u, tile, entry)

# Fell the removable feature on `tile`: clear it, and (for a forest) deliver its
# chop_yield to the nearest owned city as production. The researched chop tech
# (Mathematics) raises the yield by chop_yield_tech_bonus_pct, and the full amount
# lands when the chopped tile is inside the player's borders, scaled to
# chop_outside_borders_pct when it is not. Jungle has no chop_yield and clears for
# nothing. Records the outcome on `entry` for the facade to surface. Assumes the
# caller has decided the feature should be cleared (no preserve checks here), so it
# is shared by improvement completion (§5) and the standalone chop order (§4.11).
static func _chop_tile(gs: GameState, u: Unit, tile: Tile, entry: Dictionary) -> void:
	var feat_id: String = tile.feature_id
	if feat_id == "":
		return
	var feat: Dictionary = gs.db.get_feature(feat_id)
	tile.feature_id = ""
	entry["cleared_feature"] = feat_id
	var chop: int = int(feat.get("chop_yield", 0))
	if chop <= 0:
		return
	var city: Settlement = _nearest_owned_city(gs, u.owner_player_id, u.x, u.y)
	if city == null:
		return
	var player: Player = gs.get_player(u.owner_player_id)
	# Tech bonus: a researched chop tech (Mathematics) raises the yield.
	var tech_id: String = str(gs.db.constants.get("chop_yield_tech", ""))
	if tech_id != "" and player != null and player.has_tech(tech_id):
		chop = Fixed.scale_up(chop, gs.db.get_constant("chop_yield_tech_bonus_pct", 50))
	# Border scaling: full inside the player's own borders, reduced outside.
	if tile.owner_player_id != u.owner_player_id:
		chop = Fixed.scale(chop, gs.db.get_constant("chop_outside_borders_pct", 50))
	if chop <= 0:
		return
	city.production_store += chop
	entry["chop_yield"] = chop
	entry["chop_city_id"] = city.id

# Advance a standalone chop/clear order one turn; on completion fell the feature
# (no improvement is placed) and deliver any chop yield, queuing an entry the
# facade surfaces as a notification (§4.11). Mirrors _advance_worker_build.
static func _advance_worker_chop(gs: GameState, u: Unit) -> void:
	if u.build_turns_left > 0:
		u.build_turns_left -= 1
	if u.build_turns_left > 0:
		return
	var tile: Tile = gs.map.get_tile(u.x, u.y)
	# Only clear if the ordered feature is still the one on the tile (it cannot have
	# changed without cancelling the order, but guard defensively).
	if tile != null and tile.feature_id != "" and tile.feature_id == u.clearing_feature:
		var entry: Dictionary = {
			"player_id": u.owner_player_id,
			"improvement_id": "",
			"x": u.x, "y": u.y
		}
		_chop_tile(gs, u, tile, entry)
		gs.pending_improvements.append(entry)
	u.clearing_feature = ""
	u.build_turns_left = 0

# Nearest settlement owned by `player_id` to (x, y), by map distance; null if the
# player holds no city. Deterministic (settlement order, integer distance, no RNG).
static func _nearest_owned_city(gs: GameState, player_id: int, x: int, y: int) -> Settlement:
	var best: Settlement = null
	var best_d: int = 0
	for s in gs.settlements:
		if s.owner_player_id != player_id:
			continue
		var d: int = gs.map.distance(x, y, s.x, s.y)
		if best == null or d < best_d:
			best = s
			best_d = d
	return best

static func _settlement_culture(gs: GameState, s: Settlement, player: Player) -> void:
	var db: DataDB = gs.db

	# Culture is the culture slice of the economic split, not raw commerce (§4.7,
	# §6.2). Players with no settlement owner default to the whole commerce value.
	var culture_out: int = s.output_commerce
	if player != null:
		culture_out = player.split_commerce(s.output_commerce)[2]
		# Free Speech amplifies culture output in every city (§8).
		culture_out += Fixed.scale(culture_out,
			PolicyEffects.sum_int(player, db, "culture_all_cities"))
	# Artist/priest specialists add culture directly (§6.5), outside the commerce
	# split (it is yield, not taxed commerce).
	culture_out += Specialists.settlement_channel(db, s, "culture")
	# Persistent per-structure event culture bonuses (§9 STRUCT_YIELD, e.g. +2 culture
	# for the colosseum) — direct yield, applied only while the structure stands.
	culture_out += s.structure_yield("culture")
	# Corporation culture channel (§15.10): per-resource rate × accessible input
	# instances — direct yield, outside the commerce split, like specialists.
	culture_out += EconOrgs.settlement_channel(gs, s, "culture")
	s.culture_total += culture_out

	# Border-ring expansion (§15.4 / D2): the reference geometric culture-level
	# curve, per pace — ring = culture level + 1 (a fresh "poor" city is ring 1;
	# a legendary city reaches ring 6).
	var ring: int = CultureLevels.level_for(db, gs.pace_id, s.culture_total) + 1
	s.culture_ring = ring

	# Spread cultural influence using the culture output.
	Influence.spread(gs.map, s.x, s.y, culture_out, ring, s.owner_player_id, db)
	Influence.resolve_ownership(gs.map, db)

static func _settlement_upkeep(gs: GameState, s: Settlement,
		player: Player) -> void:
	for struct_id in s.structures:
		var struct: Dictionary = gs.db.get_structure(struct_id)
		player.treasury -= int(struct.get("upkeep", 0))
	# Bombardment damage to the culture-level defence heals a flat
	# `city_defence_heal_rate` (5) points per owner turn (§15.4 / C4).
	if s.defence_damage > 0:
		var heal: int = gs.db.get_constant("city_defence_heal_rate", 5)
		s.defence_damage = s.defence_damage - heal if s.defence_damage > heal else 0

static func _special_person_progress(gs: GameState, s: Settlement) -> void:
	# Accumulate special person points from specialists, weighted by each type's
	# gp_points from data/specialists.json (§14.3).
	var points: int = Specialists.settlement_gp_points(gs.db, s)
	# Pacifism accelerates Great Person birth (§8, §14).
	var player: Player = gs.get_player(s.owner_player_id)
	if player != null:
		points += Fixed.scale(points,
			PolicyEffects.sum_int(player, gs.db, "great_person_rate"))
	s.special_person_points += points

	# When the rising threshold is crossed, produce a special person and apply
	# its effect. The threshold then grows for the next one on the reference
	# progression (§6.5/§14.3): each birth adds `gp_threshold_increase_percent`
	# of the base threshold, and the increment itself accelerates — it is
	# multiplied by (births/10 + 1), i.e. births 1–9 add +50, 10–19 add +100,
	# and so on (reference GREAT_PEOPLE_THRESHOLD_INCREASE semantics; kept
	# per-settlement where the reference counter is per-player).
	if s.special_person_points >= s.special_person_threshold:
		s.special_person_points -= s.special_person_threshold
		s.special_persons_produced += 1
		var base: int = gs.db.get_constant("gp_threshold_base", 100)
		var inc_pct: int = gs.db.get_constant("gp_threshold_increase_percent", 50)
		var accel: int = s.special_persons_produced / 10 + 1
		s.special_person_threshold += base * inc_pct * accel / 100
		_apply_special_person(gs, s)

# A produced special person becomes a Great Person unit of the city's dominant
# specialist type when one applies (§14.1/§14.3) — the player then directs it via
# a GP action. With no typed specialists it falls back to the abstract bonus:
# an instant technology if researching, else a seeded org, else gold (§6.5).
static func _apply_special_person(gs: GameState, s: Settlement) -> void:
	var player: Player = gs.get_player(s.owner_player_id)
	if player == null:
		return
	# Typed specialists yield an actual Great Person unit at the city.
	var gen_type: String = GreatPeople.dominant_specialist(s)
	if gen_type != "" and GreatPeople.gp_unit_for_type(gs.db, gen_type) != "":
		GreatPeople.birth_from_settlement(gs, s)
		return
	if player.current_research_id != "" and not player.has_tech(player.current_research_id):
		var gifted_tech: String = player.current_research_id
		player.technologies.append(gifted_tech)
		player.current_research_id = ""
		player.research_store = 0
		gs.pending_tech_completions.append({"player_id": player.id, "tech_id": gifted_tech})
		return
	# Seed an economic organization if one is unfounded and this settlement is free.
	if s.econ_org_id == "":
		for org_id in gs.db.econ_orgs:
			if not gs.founded_econ_orgs.has(org_id):
				EconOrgs.found(org_id, s, gs)
				return
	player.treasury += gs.db.get_constant("special_person_settle_gold", 100)

# Per-turn healing for a stationary unit, by location and healing promotions
# (§5.6). Caps at full health; never heals on a turn the unit moved or fought
# (the caller already gates on that).
static func _heal_unit(gs: GameState, u: Unit, player: Player) -> void:
	if u.health >= 100:
		return
	var db: DataDB = gs.db
	var rate: int = _healing_rate(gs, u, player)
	for promo_id in u.promotions:
		rate += int(db.get_promotion(promo_id).get("healing_bonus", 0))
	rate += _medic_bonus(gs, u)
	if rate <= 0:
		return
	u.health = 100 if u.health + rate > 100 else u.health + rate

# Medic/woodsman stack-healing bonus (W6, §29.16): a healing unit gains a
# SINGLE BEST bonus — the maximum across same-tile friendly units'
# `same_tile_heal` (the healing unit's own value competes) and
# same-landmass-adjacent-tile friendly units' `adjacent_tile_heal` — never
# summed across sources, and not best-of-each-category either. Promotion values
# DO sum on one carrier unit (Medic I + Medic III = 25 same-tile). "Friendly"
# is the same owner or the same alliance. The landmass labels (4-neighbour land
# components, Quests.landmass_labels) are computed lazily, only when an
# adjacent candidate could actually raise the bonus; sea tiles carry no
# landmass, so no adjacent bonus reaches or leaves a water tile.
static func _medic_bonus(gs: GameState, u: Unit) -> int:
	var best: int = 0
	for o in Stack.at(gs.units, u.x, u.y):
		if not _heal_friendly(gs, u, o):
			continue
		var same: int = _promo_sum(gs.db, o, "same_tile_heal")
		if same > best:
			best = same
	var labels: Dictionary = {}
	var labels_ready: bool = false
	for nt in gs.map.neighbours8(u.x, u.y):
		if nt == null:
			continue
		for o in Stack.at(gs.units, nt.x, nt.y):
			if not _heal_friendly(gs, u, o):
				continue
			var adj: int = _promo_sum(gs.db, o, "adjacent_tile_heal")
			if adj <= best:
				continue
			if not labels_ready:
				labels = Quests.landmass_labels(gs)
				labels_ready = true
			var uk: int = int(labels.get(Quests.tile_key(u.x, u.y, gs), -1))
			var ok: int = int(labels.get(Quests.tile_key(nt.x, nt.y, gs), -2))
			if uk == ok:
				best = adj
	return best

# Sum of one promotion key across a unit's promotions (heal-phase helper).
static func _promo_sum(db: DataDB, u: Unit, key: String) -> int:
	var total: int = 0
	for pid in u.promotions:
		total += int(db.get_promotion(pid).get(key, 0))
	return total

# Whether `o` counts as friendly to `u` for stack healing: same owner, or both
# owners are players sharing an alliance (wild forces have no player entry).
static func _heal_friendly(gs: GameState, u: Unit, o: Unit) -> bool:
	if o.owner_player_id == u.owner_player_id:
		return true
	var up: Player = gs.get_player(u.owner_player_id)
	var op: Player = gs.get_player(o.owner_player_id)
	return up != null and op != null and up.alliance_id == op.alliance_id

static func _healing_rate(gs: GameState, u: Unit, player: Player) -> int:
	var db: DataDB = gs.db
	# Garrisoned inside one of the player's own settlements heals fastest.
	var settlement = gs.get_settlement_at(u.x, u.y)
	if settlement != null and settlement.owner_player_id == player.id:
		# A structure with `heals_units` (Ikhanda) fully restores its garrison (§5.5).
		for sid in settlement.structures:
			if player.structure_obsolete(db, sid):
				continue
			if db.get_structure(sid).get("effects", {}).get("heals_units", false):
				return 100
		return db.get_constant("healing_in_settlement", 20)
	var tile: Tile = gs.map.get_tile(u.x, u.y)
	if tile == null:
		return db.get_constant("healing_neutral_territory", 10)
	var owner: int = tile.owner_player_id
	if owner == player.id:
		return db.get_constant("healing_friendly_territory", 15)
	if owner < 0:
		return db.get_constant("healing_neutral_territory", 10)
	if gs.are_at_war(player.id, owner):
		return db.get_constant("healing_hostile_territory", 5)
	var other: Player = gs.get_player(owner)
	if other != null and other.alliance_id == player.alliance_id:
		return db.get_constant("healing_friendly_territory", 15)
	# Met but not hostile: peaceful/allied territory.
	return db.get_constant("healing_allied_territory", 15)

# Gross gold income for a player this turn (finance commerce + corporation HQ
# share). Pure read — no state mutation — so the HUD/AI can preview the rate.
static func gold_income(gs: GameState, player: Player) -> int:
	var db: DataDB = gs.db
	var income: int = 0
	# Sum finance output from all settlements
	for s in gs.settlements:
		if s.owner_player_id != player.id:
			continue
		var split: Array = player.split_commerce(s.output_commerce)
		income += split[0]  # finance
		# Corporation gold channel (§15.10): per-resource rate × accessible input
		# instances — raw gold, outside the commerce split (like the reference's
		# commerce-gold, untouched by the sliders).
		income += EconOrgs.settlement_channel(gs, s, "gold")

	# Corporation HQ gold: the founder earns gold per member city (franchise)
	# worldwide (§14.6, §15.10).
	income += EconOrgs.hq_gold_for(gs, db, player)
	return income

# Inflation rate in percent for the current game turn (§15.1). Grows linearly
# once the turn passes the pace's onset point (the negative `inflation_offset`
# delays it), scaled by the difficulty's `inflation_percent` handicap:
#   effective_turn = turn + offset (clamped at 0)
#   rate % = effective_turn × pace % / 100 × handicap % / 100   (integer math)
# Pace/difficulty columns are the reference values (game-data §29.5 / §29.10).
# Pure read of the game turn — no serialized state, no RNG.
static func inflation_rate(gs: GameState) -> int:
	var db: DataDB = gs.db
	var pace_pct: int = int(db.get_pace(gs.pace_id).get("inflation_percent", 0))
	if pace_pct <= 0:
		return 0
	var eff_turn: int = gs.turn_number \
		+ int(db.get_pace(gs.pace_id).get("inflation_offset", 0))
	if eff_turn <= 0:
		return 0
	var handicap: int = int(db.get_difficulty(gs.difficulty_id).get(
		"inflation_percent", 100))
	return eff_turn * pace_pct / 100 * handicap / 100

# Gross gold upkeep for a player this turn (unit + settlement + corporation
# maintenance, after the policy upkeep modifier, then turn-based inflation).
# Pure read — mirrors the cost side of _update_treasury so the HUD rate never
# diverges from the applied delta.
static func gold_upkeep(gs: GameState, player: Player) -> int:
	var db: DataDB = gs.db
	# Vassalage waives unit upkeep for a number of units per city (§8). Count the
	# player's cities, then exempt that many units below.
	var city_count: int = 0
	for s in gs.settlements:
		if s.owner_player_id == player.id:
			city_count += 1
	var free_units: int = city_count * PolicyEffects.sum_int(player, db, "free_units_per_city")
	# Event unit-support relief (§9 UNIT_SUPPORT) waives upkeep on this many more units.
	free_units += player.unit_support_relief

	# Upkeep for units (the first `free_units`, in id order, are free).
	var upkeep: int = 0
	for u in gs.units:
		if u.owner_player_id != player.id:
			continue
		if free_units > 0:
			free_units -= 1
			continue
		var udata: Dictionary = db.get_unit(u.unit_type_id)
		upkeep += int(udata.get("upkeep", 0))

	# Settlement upkeep scales with distance from the capital and settlement size
	# (§6.1). The capital is the player's earliest-founded settlement. State
	# Property removes the distance term entirely (§8).
	var capital: Settlement = _find_capital(gs, player.id)
	var no_distance: bool = PolicyEffects.has_flag(player, db, "no_distance_maintenance")
	var dist_scale: int = db.get_constant("upkeep_distance_scale", 1)
	var size_scale: int = db.get_constant("upkeep_size_scale", 1)
	for s in gs.settlements:
		if s.owner_player_id != player.id:
			continue
		var dist: int = 0
		if capital != null and not no_distance:
			dist = gs.map.distance(capital.x, capital.y, s.x, s.y)
		upkeep += dist * dist_scale + (s.population * size_scale) / 4

	# Corporation maintenance: each member city the player owns charges its
	# corporation's per-city maintenance (Free Market halves it; §14.6).
	upkeep += EconOrgs.maintenance_for(gs, db, player)

	# Policy upkeep modifier (percentage; negative = administrative discount).
	var policy_mod: int = 0
	for cat in player.policies:
		var pol: Dictionary = db.policies.get("policies", {}).get(player.policies[cat], {})
		policy_mod += int(pol.get("upkeep_modifier", 0))
	if policy_mod != 0:
		upkeep += Fixed.scale(upkeep, policy_mod)
	# Turn-based inflation (§15.1): expenses × (100 + rate) / 100. The rate grows
	# with the game turn per pace/difficulty — see inflation_rate() above.
	var infl: int = inflation_rate(gs)
	if infl != 0:
		upkeep += Fixed.scale(upkeep, infl)
	# Inflation modifier (§9 INFLATION): a signed percent on gross maintenance (e.g.
	# the Federal Reserve event trims it with a negative value).
	if player.inflation_pct != 0:
		upkeep += Fixed.scale(upkeep, player.inflation_pct)
	if upkeep < 0:
		upkeep = 0
	return upkeep

# Net gold per turn (income - upkeep) before insolvency clamping. The HUD reads
# this as the signed gold rate; _update_treasury applies the identical value.
static func net_gold(gs: GameState, player: Player) -> int:
	return gold_income(gs, player) - gold_upkeep(gs, player)

static func _update_treasury(gs: GameState, player: Player) -> void:
	var db: DataDB = gs.db
	player.treasury += net_gold(gs, player)

	# Insolvency (§6.1): force research down immediately; only disband units as an
	# extreme measure once the player stays broke past the grace period. Structures
	# are never sold — buildings and their invested costs are always retained.
	if player.treasury < 0:
		if player.slider_research > 0:
			player.slider_research = max(0, player.slider_research - 10)
			player.slider_finance += 10
		player.insolvent_turns += 1
		if player.insolvent_turns > db.get_constant("insolvency_grace_turns", 1):
			var guard: int = 0
			while player.treasury < 0 and guard < 100 and _disband_for_insolvency(gs, player):
				guard += 1
		if player.treasury < 0:
			player.treasury = 0
	else:
		player.insolvent_turns = 0

# The player's capital: the city holding the Palace. The Palace is the single
# seat of government, so it *defines* the capital — building it in another city
# moves the capital there. Falls back to the earliest-founded surviving city when
# none holds the Palace (the brief window after the old capital is lost, before
# _ensure_capital_palace re-seeds it — which targets that same fallback). Null if
# the player has no settlements.
static func _find_capital(gs: GameState, player_id: int) -> Settlement:
	var fallback: Settlement = null
	for s in gs.settlements:
		if s.owner_player_id != player_id:
			continue
		if s.has_structure("palace"):
			return s
		if fallback == null or s.id < fallback.id:
			fallback = s
	return fallback

# A player always has exactly one capital. If the capital was lost (no surviving
# city holds the Palace) the Palace is rebuilt for free in the new capital — the
# earliest-founded surviving city — so a player who still has cities is never
# left capital-less. No-op when the capital is intact, when the player has no
# cities, or when the data tables define no Palace.
# A city's maximum siege health (§4.8): a base, plus a slice for its size, plus a
# slice of its defensive structures' bonuses (walls, castle, …). Public so the
# conquest code in SimFacade shares the exact formula. Pass the owning player so
# obsolete defences (§15.17: Walls/Castle stop at Rifling/Economics) drop out;
# a null owner (wild camps) never obsoletes anything.
static func city_max_health(s: Settlement, db: DataDB, owner: Player = null) -> int:
	var maxh: int = db.get_constant("city_base_health", 20)
	maxh += s.population * db.get_constant("city_health_per_pop", 3)
	var divisor: int = db.get_constant("city_defence_structure_divisor", 10)
	if divisor > 0:
		for struct_id in s.structures:
			if owner != null and owner.structure_obsolete(db, struct_id):
				continue
			maxh += int(db.get_structure(struct_id).get("defence_bonus", 0)) / divisor
	return maxh

# Heal a city's siege HP toward its maximum (and normalise the -1 "full"
# sentinel / any over-cap value left by a shrunk city).
static func _city_health_regen(gs: GameState, s: Settlement) -> void:
	var maxh: int = city_max_health(s, gs.db, gs.get_player(s.owner_player_id))
	if s.health < 0 or s.health > maxh:
		s.health = maxh
		return
	if s.health < maxh:
		var regen: int = s.health + gs.db.get_constant("city_health_regen", 15)
		s.health = maxh if regen > maxh else regen

static func _ensure_capital_palace(gs: GameState, player_id: int) -> void:
	if gs.db.get_structure("palace").empty():
		return
	var fallback: Settlement = null
	for s in gs.settlements:
		if s.owner_player_id != player_id:
			continue
		if s.has_structure("palace"):
			return   # capital intact
		if fallback == null or s.id < fallback.id:
			fallback = s
	if fallback != null:
		fallback.structures.append("palace")

# Disband a unit to relieve insolvency (§6.1). Structures are never sold —
# buildings and their invested costs are always retained; when no units remain
# the caller's clamp keeps the treasury at 0. Returns true if a unit was
# disbanded.
static func _disband_for_insolvency(gs: GameState, player: Player) -> bool:
	for u in gs.units:
		if u.owner_player_id == player.id:
			Stack.remove_unit(gs.units, u.id)
			return true
	return false

static func _apply_research(gs: GameState, player: Player) -> void:
	if player.current_research_id == "":
		return
	var db: DataDB = gs.db
	# Compute total research output from all settlements
	var research_income: int = 0
	var scientists: int = 0
	for s in gs.settlements:
		if s.owner_player_id != player.id:
			continue
		var split: Array = player.split_commerce(s.output_commerce)
		var beakers: int = split[1]  # research commerce share
		# Standing-structure research multiplier (§15: `science_bonus` — library/
		# university/observatory/laboratory 25, academy 50, seowon 35, …): the
		# structures' percentages sum and scale the city's research commerce share
		# only, truncating. Specialist, event and corporation science below are
		# direct yields outside the multiplier.
		var sci_pct: int = 0
		for sci_struct_id in s.structures:
			if player.structure_obsolete(db, sci_struct_id):
				continue  # e.g. the Monastery's 10 stops at Scientific Method (§15.17)
			sci_pct += int(db.get_structure(sci_struct_id).get("science_bonus", 0))
		if sci_pct > 0:
			beakers += Fixed.scale(beakers, sci_pct)
		research_income += beakers
		# Scientist specialists yield science directly (§6.5), outside the commerce
		# split (it is yield, not taxed commerce).
		research_income += Specialists.settlement_channel(db, s, "science")
		# Persistent per-structure event research bonuses (§9 STRUCT_YIELD, e.g. +1
		# research for the library) — direct science yield while the structure stands.
		research_income += s.structure_yield("research")
		# Corporation research channel (§15.10): per-resource rate × accessible
		# input instances — direct science yield, outside the commerce split.
		research_income += EconOrgs.settlement_channel(gs, s, "research")
		scientists += int(s.specialists.get("scientist", 0))

	# Representation: scientist specialists yield extra science directly (§8).
	research_income += scientists * PolicyEffects.sum_int(player, db, "science_per_scientist")
	# Free Religion: a percentage boost to total science output (§8).
	research_income += Fixed.scale(research_income,
		PolicyEffects.sum_int(player, db, "science_output"))

	# §6.3: when research is not independently funded (research slider at 0), net
	# finance supplements it — a fraction of the player's finance income spills over
	# into the current project so a fully commerce-funded empire still advances.
	if player.slider_research == 0:
		var fin_income: int = 0
		for s in gs.settlements:
			if s.owner_player_id == player.id:
				fin_income += player.split_commerce(s.output_commerce)[0]
		if fin_income > 0:
			research_income += Fixed.scale(fin_income,
				db.get_constant("finance_research_supplement_pct", 50))

	# AI research handicap (§2.2): higher difficulties give AI extra beakers.
	# Same is_ai gate as the production bonus; one data column controls both.
	if player.is_ai:
		var ai_bonus: int = int(db.get_difficulty(gs.difficulty_id).get("ai_bonus", 0))
		if ai_bonus != 0:
			research_income = Fixed.scale(research_income, 100 + ai_bonus)

	player.research_store += research_income

	# Alliance shared research (§6.3): draw this member's per-capita share of the
	# pool its allies contributed during the previous world step. Solo alliances
	# pool nothing (see _advance_alliances), so their behavior is unchanged.
	var alliance: Alliance = gs.get_player_alliance(player.id)
	if alliance != null and alliance.member_player_ids.size() >= 2 \
			and alliance.shared_research_store > 0:
		var members: int = alliance.member_player_ids.size()
		var share: int = alliance.shared_research_store / members
		player.research_store += share
		alliance.shared_research_store -= share

	# Known by others count for discount
	var known_by_others: Dictionary = {}
	var tech_id: String = player.current_research_id
	for other in gs.players:
		if other.id == player.id:
			continue
		if other.has_tech(tech_id):
			known_by_others[tech_id] = known_by_others.get(tech_id, 0) + 1

	# §6.3 cost chain: the player's difficulty handicap, world size, pace, era and
	# team size (alliance members share research, so each extra member adds cost).
	var team_members: int = 1
	if alliance != null and alliance.member_player_ids.size() > 1:
		team_members = alliance.member_player_ids.size()
	var cost: int = Research._effective_cost(tech_id, player, db, known_by_others,
		gs.pace_id, gs.difficulty_id, gs.world_size_id, team_members)
	if player.research_store >= cost:
		player.research_store -= cost
		player.technologies.append(tech_id)
		player.current_research_id = ""
		gs.pending_tech_completions.append({"player_id": player.id, "tech_id": tech_id})

# The Internet's tech-share (§15.7, C5): the owner of a `tech_share: K` effects
# project automatically acquires every technology already known by at least K
# other (non-eliminated) players. Runs in the PLAYER_RESEARCH phase right after
# _apply_research; no RNG. Techs are scanned in data order (JSON insertion
# order), so grants are deterministic. A shared tech that was the player's
# current research is completed for free (accumulated beakers are kept for the
# next choice, like any completion overflow).
static func _apply_tech_share(gs: GameState, player: Player) -> void:
	var k: int = Projects.effect_int(player, gs.db, "tech_share")
	if k <= 0:
		return
	for tech_id in gs.db.technologies:
		if player.has_tech(tech_id):
			continue
		var known: int = 0
		for other in gs.players:
			if other.id == player.id or other.is_eliminated:
				continue
			if other.has_tech(tech_id):
				known += 1
		if known >= k:
			player.technologies.append(tech_id)
			if player.current_research_id == tech_id:
				player.current_research_id = ""
			gs.pending_tech_completions.append(
				{"player_id": player.id, "tech_id": tech_id})

static func _apply_intelligence(gs: GameState, player: Player) -> void:
	# Each turn a player's espionage output is accumulated as intel points,
	# spread evenly across every alliance it has met (§7, §15.5 — provisional).
	# Per city the output is the intel slice of its commerce plus the flat
	# `espionage` of its structures (Palace, Courthouse, Jail, …), the whole
	# scaled up by that city's `espionage_output` percent (Intelligence Agency,
	# Scotland Yard, the Castle line). Empire-wide civic espionage (Nationhood)
	# is added on top.
	var alliance: Alliance = gs.get_player_alliance(player.id)
	if alliance == null or alliance.contacts.empty():
		return

	var total: int = 0
	for s in gs.settlements:
		if s.owner_player_id != player.id:
			continue
		var city_out: int = player.split_commerce(s.output_commerce)[3] \
			+ _settlement_espionage_flat(s, gs.db, player) \
			+ Specialists.settlement_channel(gs.db, s, "espionage")
		city_out += Fixed.scale(city_out, _settlement_espionage_output(s, gs.db, player))
		total += city_out

	# Nationhood and other civics add a flat empire-wide espionage yield (§8).
	total += PolicyEffects.sum_int(player, gs.db, "espionage")
	if total <= 0:
		return

	var share: int = total / alliance.contacts.size()
	for target_aid in alliance.contacts:
		if not player.intel_points.has(target_aid):
			player.intel_points[target_aid] = 0
		player.intel_points[target_aid] += share

# Sum of the flat `espionage` points contributed by a settlement's structures.
static func _settlement_espionage_flat(s: Settlement, db: DataDB,
		player: Player = null) -> int:
	var flat: int = 0
	for struct_id in s.structures:
		if player != null and player.structure_obsolete(db, struct_id):
			continue
		flat += int(db.get_structure(struct_id).get("effects", {}).get("espionage", 0))
	return flat

# Sum of the `espionage_output` percent modifiers a settlement's structures grant
# (they stack additively, e.g. Intelligence Agency +50% with Scotland Yard +100%).
# An obsolete structure's modifier stops (§15.17: the Castle's 25 at Economics).
static func _settlement_espionage_output(s: Settlement, db: DataDB,
		player: Player = null) -> int:
	var pct: int = 0
	for struct_id in s.structures:
		if player != null and player.structure_obsolete(db, struct_id):
			continue
		pct += int(db.get_structure(struct_id).get("effects", {}).get("espionage_output", 0))
	return pct

# Tick a unit's timed event states (§9 UNIT_STATE) down one turn. While immobile the
# unit has no movement this turn (movement was already reset; zero it again here).
static func _tick_unit_event_states(u: Unit) -> void:
	if u.event_immobile_turns > 0:
		u.event_immobile_turns -= 1
		u.movement_left = 0
	if u.event_no_attack_turns > 0:
		u.event_no_attack_turns -= 1

static func _tick_states(gs: GameState, player: Player) -> void:
	if player.transition_turns > 0:
		player.transition_turns -= 1
	if player.celebration_turns > 0:
		player.celebration_turns -= 1
	# Tick down any active counterespionage cover (§7.1), dropping spent entries.
	for aid in player.counter_espionage.keys():
		var left: int = int(player.counter_espionage[aid]) - 1
		if left > 0:
			player.counter_espionage[aid] = left
		else:
			player.counter_espionage.erase(aid)
	# A running Golden Age counts down one turn (§14.4).
	GreatPeople.tick_golden_age(player)
	for s in gs.settlements:
		if s.owner_player_id != player.id:
			continue
		if s.rush_anger_turns > 0:
			s.rush_anger_turns -= 1
		# Count down timed event happiness modifiers; drop the expired ones (§9).
		if not s.timed_happiness.empty():
			var kept: Array = []
			for tm in s.timed_happiness:
				var left: int = int(tm.get("turns_left", 0)) - 1
				if left > 0:
					tm["turns_left"] = left
					kept.append(tm)
			s.timed_happiness = kept
		# Count down timed event wellbeing modifiers; drop the expired ones (§9).
		if not s.timed_health.empty():
			var kept_h: Array = []
			for th in s.timed_health:
				var hleft: int = int(th.get("turns_left", 0)) - 1
				if hleft > 0:
					th["turns_left"] = hleft
					kept_h.append(th)
			s.timed_health = kept_h

static func _validate_policies(gs: GameState, player: Player) -> void:
	var db: DataDB = gs.db
	var policies_data: Dictionary = db.policies.get("policies", {})
	for cat in player.policies:
		var pol_id: String = player.policies[cat]
		var pol: Dictionary = policies_data.get(pol_id, {})
		var tech_req = pol.get("tech_required", null)
		if tech_req != null and tech_req != "" and not player.has_tech(tech_req):
			# Revert to default (despotism/slavery etc.)
			player.policies.erase(cat)

static func _auto_assign_workers(gs: GameState, player: Player) -> void:
	var db: DataDB = gs.db
	for s in gs.settlements:
		if s.owner_player_id != player.id:
			continue
		# Citizens working as specialists are not available to work tiles.
		var spec_count: int = 0
		for spec_type in s.specialists:
			spec_count += int(s.specialists[spec_type])
		var workers_needed: int = s.effective_workers() - spec_count
		if workers_needed < 0:
			workers_needed = 0
		s.worked_tiles = []
		# The city centre tile is always worked for free (§4.1): a settlement
		# "immediately claims its own tile" and draws its yield regardless of size,
		# so it does not consume a population worker slot. Seeding it here is what
		# lets a fresh size-1 city run a positive food surplus and grow — without
		# it the lone citizen works a single off-centre tile and the centre's yield
		# is lost (net surplus 0). Excluded from the locked-set and candidate pool
		# below so it is never double-counted or charged against the budget.
		var center_key := str(s.x) + "," + str(s.y)
		if gs.map.is_valid(s.x, s.y):
			s.worked_tiles.append([s.x, s.y])
		# Honour manual locks first: a player-locked tile is always worked, as
		# long as it is in range, ownable, and within the worker budget.
		var assigned: int = 0
		var locked_set := {center_key: true}
		for lt in s.locked_tiles:
			if assigned >= workers_needed:
				break
			var lx: int = int(lt[0]); var ly: int = int(lt[1])
			if lx == s.x and ly == s.y:
				continue  # centre is already worked for free
			if not gs.map.is_valid(lx, ly):
				continue
			var ltile = gs.map.get_tile(lx, ly)
			if ltile == null:
				continue
			if not TileOutput.workable(ltile, db):
				continue  # unworkable terrain (mountain peaks) never takes a citizen
			if not (ltile.owner_player_id == player.id or ltile.owner_player_id == -1):
				continue
			s.worked_tiles.append([lx, ly])
			locked_set[str(lx) + "," + str(ly)] = true
			assigned += 1
		# When citizen management is manual, stop here — only the centre and the
		# player's locked tiles are worked.
		if not s.manage_citizens_auto:
			continue
		# Gather candidate tiles owned by this player (excluding the centre, which
		# is already worked above, and any tiles already locked-in).
		var candidates := []
		for tile in gs.map.tiles_in_range(s.x, s.y, s.culture_ring):
			if locked_set.has(str(tile.x) + "," + str(tile.y)):
				continue
			if not TileOutput.workable(tile, db):
				continue  # unworkable terrain (mountain peaks) never takes a citizen
			if tile.owner_player_id == player.id or tile.owner_player_id == -1:
				var out: Array = TileOutput.compute(tile, db, player.technologies,
					gs.map.tile_has_river(tile.x, tile.y))
				var score: int = out[0] * 3 + out[1] * 2 + out[2]
				candidates.append([score, tile.x, tile.y])
		# Repeatedly take the best candidate. A plain candidates.sort() would
		# compare [score, x, y] sub-arrays, which Godot cannot order consistently
		# ("bad comparison function; sorting will be broken").
		while assigned < workers_needed and not candidates.empty():
			var best_i: int = 0
			for i in range(1, candidates.size()):
				if _worker_candidate_better(candidates[i], candidates[best_i]):
					best_i = i
			var c: Array = candidates[best_i]
			candidates.remove(best_i)
			s.worked_tiles.append([c[1], c[2]])
			assigned += 1

# True if candidate `a` should be preferred over `b`: higher score first, ties
# broken by larger x then larger y (matching the previous sort/invert ordering).
static func _worker_candidate_better(a: Array, b: Array) -> bool:
	if a[0] != b[0]:
		return a[0] > b[0]
	if a[1] != b[1]:
		return a[1] > b[1]
	return a[2] > b[2]

static func _resolve_trades(gs: GameState) -> void:
	for alliance in gs.alliances:
		var expired := []
		for i in range(alliance.pending_trades.size()):
			var trade: Dictionary = alliance.pending_trades[i]
			if int(trade.get("expires_turn", 0)) <= gs.turn_number:
				expired.append(i)
		for i in range(expired.size() - 1, -1, -1):
			alliance.pending_trades.remove(expired[i])
	_execute_deals(gs)

# Deliver every active persistent deal's recurring items (§7), once per whole-world
# step, in fixed deal order. A deal lapses (and surfaces a pending_deal_events
# notice) when either party's alliance is gone or the two alliances are now at war
# — declaring war on a deal partner tears up the standing agreement.
static func _execute_deals(gs: GameState) -> void:
	var dead := []
	for i in range(gs.deals.size()):
		var d: Dictionary = gs.deals[i]
		var a: Alliance = gs.get_alliance(int(d.get("a_alliance", -1)))
		var b: Alliance = gs.get_alliance(int(d.get("b_alliance", -1)))
		if a == null or b == null or a.is_at_war_with(b.id) or b.is_at_war_with(a.id):
			dead.append(i)
			gs.pending_deal_events.append({"kind": "deal_expired", "deal_id": int(d.get("id", -1))})
			continue
		var proposer: Player = gs.get_player(int(d.get("proposer_player_id", -1)))
		var accepter: Player = gs.get_player(int(d.get("accepter_player_id", -1)))
		if proposer == null or accepter == null:
			dead.append(i)
			gs.pending_deal_events.append({"kind": "deal_expired", "deal_id": int(d.get("id", -1))})
			continue
		var recurring: Dictionary = d.get("recurring", {})
		# give = proposer→accepter; receive = accepter→proposer.
		var gpt_give: int = int(recurring.get("give", {}).get("gold_per_turn", 0))
		var gpt_recv: int = int(recurring.get("receive", {}).get("gold_per_turn", 0))
		if gpt_give > 0:
			proposer.treasury -= gpt_give
			accepter.treasury += gpt_give
		if gpt_recv > 0:
			accepter.treasury -= gpt_recv
			proposer.treasury += gpt_recv
		# Resource items grant ongoing access; they are read where resource access is
		# evaluated, so there is nothing to transfer here.
	for i in range(dead.size() - 1, -1, -1):
		gs.deals.remove(dead[i])

# Tributary alliances pay a share of their treasury to their overlord (§7).
static func _collect_tribute(gs: GameState) -> void:
	var pct: int = gs.db.get_constant("tribute_pct", 10)
	for sub in gs.alliances:
		if sub.is_subordinate_to < 0:
			continue
		var overlord: Alliance = gs.get_alliance(sub.is_subordinate_to)
		if overlord == null or overlord.member_player_ids.empty():
			continue
		var recipient: Player = gs.get_player(overlord.member_player_ids[0])
		for pid in sub.member_player_ids:
			var p: Player = gs.get_player(pid)
			if p == null:
				continue
			var tribute: int = Fixed.scale(p.treasury, pct)
			if tribute <= 0:
				continue
			p.treasury -= tribute
			if recipient != null:
				recipient.treasury += tribute

static func _advance_alliances(gs: GameState) -> void:
	for alliance in gs.alliances:
		# Nothing to share in an alliance of one; this also keeps solo players
		# (the default) on the pure per-player research path with no double count.
		if alliance.member_player_ids.size() < 2:
			continue
		var share_pct: int = gs.db.get_constant("alliance_research_share_pct", 50)
		for pid in alliance.member_player_ids:
			var p: Player = gs.get_player(pid)
			if p == null:
				continue
			# Each member donates a configurable share of its research output to
			# the alliance pool; members draw their per-capita share next turn.
			var research_contrib: int = 0
			for s in gs.settlements:
				if s.owner_player_id != pid:
					continue
				var split: Array = p.split_commerce(s.output_commerce)
				research_contrib += split[1]
			alliance.shared_research_store += Fixed.scale(research_contrib, share_pct)

# §7 first contact: establish mutual, permanent contact between any two players
# when one's sight (unit_sight around a unit, city_sight around a city) covers a
# tile where the other is present — a unit, a city, or an owned border tile. This
# is what populates the diplomacy roster: a player only appears to another once
# they have met. Contact is only appended (never removed) so it is sticky.
static func _detect_sight_contact(gs: GameState) -> void:
	var db: DataDB = gs.db
	if db == null or gs.map == null:
		return
	var unit_sight: int = db.get_constant("unit_sight", 2)
	var city_sight: int = db.get_constant("city_sight", 3)

	# Presence map: tile key -> { player_id: true } for every player present on
	# that tile via a unit, a city, or border ownership. Wild forces (owner < 0)
	# are excluded — they are not diplomatic players.
	var presence: Dictionary = {}
	for u in gs.units:
		if u.owner_player_id >= 0:
			_add_presence(presence, u.x, u.y, u.owner_player_id)
	for s in gs.settlements:
		if s.owner_player_id >= 0:
			_add_presence(presence, s.x, s.y, s.owner_player_id)
	for tile in gs.map.all_tiles():
		if tile.owner_player_id >= 0:
			_add_presence(presence, tile.x, tile.y, tile.owner_player_id)

	# Each sight source reveals who is present within its radius; everyone seen
	# meets the seer (mutually).
	for u in gs.units:
		if u.owner_player_id >= 0:
			_scan_sight_contact(gs, presence, u.x, u.y, unit_sight, u.owner_player_id)
	for s in gs.settlements:
		if s.owner_player_id >= 0:
			_scan_sight_contact(gs, presence, s.x, s.y, city_sight, s.owner_player_id)
	# Cultural-border vision: a player also sees their own territory and a one-ring
	# fringe just beyond it (width = territory_vision_ring), so a rival standing on
	# (or whose unit/city/border lies on) a tile you own or border meets you, even
	# with no unit or city of yours nearby. Each owned tile acts as a radius-`ring`
	# sight source (plain Chebyshev disc — owned ground watches itself with no LOS
	# gate; the fringe is what the ring adds).
	var ring: int = db.get_constant("territory_vision_ring", 1)
	if ring < 0:
		ring = 0
	for tile in gs.map.all_tiles():
		var owner: int = tile.owner_player_id
		if owner < 0:
			continue
		_scan_presence_contact(gs, presence, tile.x, tile.y, ring, owner)

static func _add_presence(presence: Dictionary, x: int, y: int, player_id: int) -> void:
	var key: String = "%d,%d" % [x, y]
	if not presence.has(key):
		presence[key] = {}
	presence[key][player_id] = true

# For one sight source at (cx, cy) belonging to seer_id, walk the visible tiles
# (terrain-aware sight: source sight_bonus + LOS blocking, via the shared
# Visibility helper, matching the fog/wild sight model) and record contact with
# every other player present on any of them. The helper returns map-normalized
# "x,y" keys, the same canonical form the presence map is built with.
static func _scan_sight_contact(gs: GameState, presence: Dictionary,
		cx: int, cy: int, radius: int, seer_id: int) -> void:
	var seen: Dictionary = Visibility.visible_tiles(gs.map, gs.db, cx, cy, radius)
	for key in seen:
		var here: Dictionary = presence.get(key, {})
		for other_id in here:
			if int(other_id) != seer_id:
				_ensure_mutual_contact(gs, seer_id, int(other_id))

# Cultural-border vision contact: every tile within Chebyshev radius `ring` of an
# owned tile at (cx, cy) is watched by its owner with no line-of-sight gate (your
# own ground, plus the one-ring fringe, is always watched). Records contact with
# every other player present on any of those tiles. The disc includes the owned
# tile itself (ring 0), so a rival standing directly on your border meets you.
static func _scan_presence_contact(gs: GameState, presence: Dictionary,
		cx: int, cy: int, ring: int, seer_id: int) -> void:
	for tile in gs.map.tiles_in_range(cx, cy, ring):
		var key: String = "%d,%d" % [tile.x, tile.y]
		var here: Dictionary = presence.get(key, {})
		for other_id in here:
			if int(other_id) != seer_id:
				_ensure_mutual_contact(gs, seer_id, int(other_id))

static func _ensure_mutual_contact(gs: GameState, pid_a: int, pid_b: int) -> void:
	var a: Alliance = gs.get_player_alliance(pid_a)
	var b: Alliance = gs.get_player_alliance(pid_b)
	if a == null or b == null or a.id == b.id:
		return
	# Detect the not-met → met transition: record a first-contact event the first
	# time these two alliances meet (contacts only ever appends, so a fresh append
	# is a genuine first meeting). One record per direction so each player's
	# notification can name the other.
	if not a.has_contact_with(b.id):
		a.contacts.append(b.id)
		gs.pending_first_contacts.append(
			{"player_id": pid_a, "other_player_id": pid_b})
		gs.pending_first_contacts.append(
			{"player_id": pid_b, "other_player_id": pid_a})
	if not b.has_contact_with(a.id):
		b.contacts.append(a.id)

static func _tile_upkeep(gs: GameState) -> void:
	# Improvement maintenance (§3.3): each owned, improved tile charges its owner
	# the improvement's upkeep.
	var db: DataDB = gs.db
	for tile in gs.map.all_tiles():
		if tile.owner_player_id < 0 or tile.improvement_id == "":
			continue
		var cost: int = int(db.get_improvement(tile.improvement_id).get("upkeep", 0))
		if cost <= 0:
			continue
		var p: Player = gs.get_player(tile.owner_player_id)
		if p != null:
			p.treasury -= cost

static func _set_next_active_player(gs: GameState) -> void:
	if gs.players.empty():
		return
	var current_idx: int = -1
	for i in range(gs.players.size()):
		if gs.players[i].id == gs.current_player_id:
			current_idx = i
			break
	var next_idx: int = (current_idx + 1) % gs.players.size()
	gs.current_player_id = gs.players[next_idx].id
