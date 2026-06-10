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
		Pollution.accumulate(gs)
		Pollution.degrade(gs, gs.rng)
		# Nuclear Plant meltdowns spread fallout around their settlement (§5.7).
		Nuclear.meltdown_tick(gs, gs.rng)

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

	# 4. Apply research progress
	if not hooks.run(IDs.Phase.PLAYER_RESEARCH, gs, {"player_id": player_id}):
		_apply_research(gs, player)

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

	# 9. Process scripted/random events
	if not hooks.run(IDs.Phase.PLAYER_EVENTS, gs, {"player_id": player_id}):
		Events.process_player_events(player, gs, gs.rng)

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

	# Era advancement (§1): recompute the player's era after every tech gained this
	# step (research in phase 4, a Great Scientist's instant tech in phase 6). Queues
	# a record for the facade to surface when the player crosses into a new era.
	Eras.refresh(player, gs.db, gs)

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
		var out: Array = TileOutput.compute(tile, db, player.technologies)
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

	# Structures bonus
	for struct_id in s.structures:
		var struct: Dictionary = db.get_structure(struct_id)
		total_food     += int(struct.get("output_delta", {}).get("food", 0))
		total_prod     += int(struct.get("output_delta", {}).get("production", 0))
		total_commerce += int(struct.get("output_delta", {}).get("commerce", 0))

	# Econ org bonus
	var org_delta: Array = EconOrgs.get_output_delta(s, db)
	total_food     += org_delta[0]
	total_prod     += org_delta[1]
	total_commerce += org_delta[2]

	# Specialist economic output (§6.5): assigned specialists yield commerce.
	var spec_count: int = 0
	for spec_type in s.specialists:
		spec_count += int(s.specialists[spec_type])
	# Mercantilism grants a free specialist per city — it yields commerce like any
	# specialist but consumes no population (§8).
	spec_count += PolicyEffects.sum_int(player, db, "free_specialist_per_city")
	total_commerce += spec_count * db.get_constant("specialist_commerce", 3)

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

	# Wellbeing: deficit reduces food surplus
	_update_wellbeing(gs, s, player, db)
	var effective_food: int = total_food - s.wellbeing_deficit
	var consumed: int = s.population * db.get_constant("food_per_citizen", 2)
	var surplus: int = effective_food - consumed

	s.food_store += surplus

	# Growth threshold, scaled by both the game pace and the owner's era (§1): later
	# eras raise the food needed per growth (growth_threshold_scale in ages.json).
	var base: int = db.get_constant("growth_base", 20)
	var pace: Dictionary = db.get_pace(gs.pace_id)
	var pace_scale: int = int(pace.get("growth_scale", 100))
	var era_scale: int = Eras.growth_threshold_scale(Eras.player_era(player, db), db)
	var threshold: int = Fixed.scale(Fixed.scale(base * s.population, pace_scale), era_scale)
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
		if s.has_structure("granary"):
			carry_frac = int(db.get_structure("granary").get("effects", {}).get("food_carry_over", 50))
		s.food_store = Fixed.scale(threshold, carry_frac)
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
		var struct: Dictionary = db.get_structure(struct_id)
		pos += int(struct.get("health_bonus", 0))
		neg += int(struct.get("health_penalty", 0))
	# Adopted belief wellbeing (§8)
	if s.belief_id != "":
		pos += int(db.beliefs.get(s.belief_id, {}).get("health_bonus", 0))
	# Empire-wide civic health (Environmentalism, §8).
	pos += PolicyEffects.sum_int(player, db, "health_empire")
	# Leader/society trait wellbeing (§4.6): e.g. Expansive grants +2 health per city
	# (the Beyond the Sword value). Summed across the player's traits.
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
	for struct_id in s.structures:
		var struct: Dictionary = db.get_structure(struct_id)
		if not _structure_effect_active(db, struct_id, s, player):
			continue
		pos += int(struct.get("happiness_bonus", 0))

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
	if s.has_structure("barracks"):
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

	# Convert anger percentage to negative sentiment citizens
	var anger_div: int = db.get_constant("anger_divisor", 100)
	var neg_citizens: int = Fixed.scale(s.population, neg_anger)

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
	# Civic production effects depend on what is currently being built (§8).
	prod += _policy_production_delta(gs, s, player, db, item, prod)
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

# Per-turn production adjustment from active civics for the item at the head of
# the queue (§8): Police State's percentage bonus to military units, Organized
# Religion's flat bonus for religious buildings, and Pacifism's drain per
# garrisoned military unit. `base_prod` is this turn's settlement production,
# which the percentage bonuses scale off.
static func _policy_production_delta(gs: GameState, s: Settlement,
		player: Player, db: DataDB, item: Dictionary, base_prod: int) -> int:
	var delta: int = 0
	var itype: String = item.get("type", "unit")
	var iid: String = item.get("id", "")
	if itype == "unit":
		if _is_military_unit(db, iid):
			delta += Fixed.scale(base_prod,
				PolicyEffects.sum_int(player, db, "military_production"))
	elif itype == "structure":
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

# Whether a structure's gameplay effects are live in this settlement (§8). A
# structure flagged `requires_state_religion` (the Cathedral tier) only takes
# effect while the city follows the player's adopted state religion; everything
# else is always active.
static func _structure_effect_active(db: DataDB, struct_id: String,
		s: Settlement, player: Player) -> bool:
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
			u.movement_total = int(udata.get("movement", 200))
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
			var alliance_id: int = player.alliance_id
			if not gs.endgame_project_stages.has(alliance_id):
				gs.endgame_project_stages[alliance_id] = 0
			gs.endgame_project_stages[alliance_id] += 1
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
	for sid in s.structures:
		var fx: Dictionary = db.get_structure(sid).get("effects", {})
		var fp: String = str(fx.get("free_promotion", ""))
		if fp != "" and not (fp in u.promotions):
			var applies: String = str(db.get_promotion(fp).get("applies_to", "all"))
			if applies == "all" or applies == cls or applies == dom:
				u.promotions.append(fp)
		if bool(fx.get("free_promotion_all", false)):
			var pick: String = CombatApply.pick_promotion(gs, u)
			if pick != "":
				u.promotions.append(pick)

# Cottage-line maturation (§8): each worked tile carrying an improvement with an
# `upgrades_to` ages a step per turn (Emancipation's `faster_cottage_growth`
# doubles the rate); on reaching `upgrade_turns` it advances to the next stage
# (cottage → hamlet → village → town). Only worked tiles grow, mirroring the
# reference model. Pure age bookkeeping on the tile; output is gated by tech in
# TileOutput as usual.
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
	var per_turn: int = 2 if PolicyEffects.has_flag(player, db, "faster_cottage_growth") else 1
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
			t.improvement_age += per_turn
			var need: int = int(imp.get("upgrade_turns", 0))
			if need > 0 and t.improvement_age >= need:
				t.improvement_id = next_id
				t.improvement_age = 0

# Advance a worker's in-progress improvement build by one turn. When the build
# completes, the improvement is placed on the worker's tile and the build state
# is cleared; a record is queued for SimFacade to surface as a notification.
# Called once per turn for a worker that held its tile (see player_step).
static func _advance_worker_build(gs: GameState, u: Unit) -> void:
	if u.build_turns_left > 0:
		u.build_turns_left -= 1
	if u.build_turns_left > 0:
		return
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
	var thresholds: Array = db.constants.get("culture_ring_thresholds",
		[10, 30, 60, 100, 150, 210, 280, 360, 450, 550])

	# Culture is the culture slice of the economic split, not raw commerce (§4.7,
	# §6.2). Players with no settlement owner default to the whole commerce value.
	var culture_out: int = s.output_commerce
	if player != null:
		culture_out = player.split_commerce(s.output_commerce)[2]
		# Free Speech amplifies culture output in every city (§8).
		culture_out += Fixed.scale(culture_out,
			PolicyEffects.sum_int(player, db, "culture_all_cities"))
	s.culture_total += culture_out

	# Ring expansion
	var ring: int = 1
	for thresh in thresholds:
		if s.culture_total >= thresh:
			ring += 1
		else:
			break
	ring = min(ring, thresholds.size())
	s.culture_ring = ring

	# Spread cultural influence using the culture output.
	Influence.spread(gs.map, s.x, s.y, culture_out, ring, s.owner_player_id, db)
	Influence.resolve_ownership(gs.map)

static func _settlement_upkeep(gs: GameState, s: Settlement,
		player: Player) -> void:
	for struct_id in s.structures:
		var struct: Dictionary = gs.db.get_structure(struct_id)
		player.treasury -= int(struct.get("upkeep", 0))

static func _special_person_progress(gs: GameState, s: Settlement) -> void:
	# Accumulate special person points from specialists
	var points: int = 0
	for spec_type in s.specialists:
		points += int(s.specialists[spec_type])
	# Pacifism accelerates Great Person birth (§8, §14).
	var player: Player = gs.get_player(s.owner_player_id)
	if player != null:
		points += Fixed.scale(points,
			PolicyEffects.sum_int(player, gs.db, "great_person_rate"))
	s.special_person_points += points

	# When the rising threshold is crossed, produce a special person and apply
	# its effect. The threshold then grows for the next one (§6.5).
	if s.special_person_points >= s.special_person_threshold:
		s.special_person_points -= s.special_person_threshold
		s.special_person_threshold = Fixed.scale_up(s.special_person_threshold, 25)
		s.special_persons_produced += 1
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
	if rate <= 0:
		return
	u.health = 100 if u.health + rate > 100 else u.health + rate

static func _healing_rate(gs: GameState, u: Unit, player: Player) -> int:
	var db: DataDB = gs.db
	# Garrisoned inside one of the player's own settlements heals fastest.
	var settlement = gs.get_settlement_at(u.x, u.y)
	if settlement != null and settlement.owner_player_id == player.id:
		# A structure with `heals_units` (Ikhanda) fully restores its garrison (§5.5).
		for sid in settlement.structures:
			if db.get_structure(sid).get("effects", {}).get("heals_units", false):
				return 100
		return db.get_constant("healing_in_settlement", 30)
	var tile: Tile = gs.map.get_tile(u.x, u.y)
	if tile == null:
		return db.get_constant("healing_neutral_territory", 5)
	var owner: int = tile.owner_player_id
	if owner == player.id:
		return db.get_constant("healing_friendly_territory", 20)
	if owner < 0:
		return db.get_constant("healing_neutral_territory", 5)
	if gs.are_at_war(player.id, owner):
		return db.get_constant("healing_hostile_territory", 0)
	var other: Player = gs.get_player(owner)
	if other != null and other.alliance_id == player.alliance_id:
		return db.get_constant("healing_friendly_territory", 20)
	# Met but not hostile: peaceful/allied territory.
	return db.get_constant("healing_allied_territory", 15)

static func _update_treasury(gs: GameState, player: Player) -> void:
	var db: DataDB = gs.db
	var income: int = 0
	# Sum finance output from all settlements
	for s in gs.settlements:
		if s.owner_player_id != player.id:
			continue
		var split: Array = player.split_commerce(s.output_commerce)
		income += split[0]  # finance

	# Vassalage waives unit upkeep for a number of units per city (§8). Count the
	# player's cities, then exempt that many units below.
	var city_count: int = 0
	for s in gs.settlements:
		if s.owner_player_id == player.id:
			city_count += 1
	var free_units: int = city_count * PolicyEffects.sum_int(player, db, "free_units_per_city")

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

	# Policy upkeep modifier (percentage; negative = administrative discount).
	var policy_mod: int = 0
	for cat in player.policies:
		var pol: Dictionary = db.policies.get("policies", {}).get(player.policies[cat], {})
		policy_mod += int(pol.get("upkeep_modifier", 0))
	if policy_mod != 0:
		upkeep += Fixed.scale(upkeep, policy_mod)
	if upkeep < 0:
		upkeep = 0

	player.treasury += income - upkeep

	# Insolvency (§6.1): force research down immediately; only sell/disband as an
	# extreme measure once the player stays broke past the grace period.
	if player.treasury < 0:
		if player.slider_research > 0:
			player.slider_research = max(0, player.slider_research - 10)
			player.slider_finance += 10
		player.insolvent_turns += 1
		if player.insolvent_turns > db.get_constant("insolvency_grace_turns", 1):
			var guard: int = 0
			while player.treasury < 0 and guard < 100 and _sell_or_disband(gs, player):
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
# conquest code in SimFacade shares the exact formula.
static func city_max_health(s: Settlement, db: DataDB) -> int:
	var maxh: int = db.get_constant("city_base_health", 20)
	maxh += s.population * db.get_constant("city_health_per_pop", 3)
	var divisor: int = db.get_constant("city_defence_structure_divisor", 10)
	if divisor > 0:
		for struct_id in s.structures:
			maxh += int(db.get_structure(struct_id).get("defence_bonus", 0)) / divisor
	return maxh

# Heal a city's siege HP toward its maximum (and normalise the -1 "full"
# sentinel / any over-cap value left by a shrunk city).
static func _city_health_regen(gs: GameState, s: Settlement) -> void:
	var maxh: int = city_max_health(s, gs.db)
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

# Sell the newest structure (salvage refund) or, failing that, disband a unit to
# relieve insolvency. Returns true if something was sold/disbanded.
static func _sell_or_disband(gs: GameState, player: Player) -> bool:
	for s in gs.settlements:
		if s.owner_player_id == player.id and not s.structures.empty():
			var sid: String = s.structures[s.structures.size() - 1]
			s.structures.remove(s.structures.size() - 1)
			player.treasury += int(gs.db.get_structure(sid).get("cost", 0)) / 4
			return true
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
		research_income += split[1]  # research
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

	var cost: int = Research._effective_cost(tech_id, player, db, known_by_others, gs.pace_id)
	if player.research_store >= cost:
		player.research_store -= cost
		player.technologies.append(tech_id)
		player.current_research_id = ""
		gs.pending_tech_completions.append({"player_id": player.id, "tech_id": tech_id})

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
			+ _settlement_espionage_flat(s, gs.db)
		city_out += Fixed.scale(city_out, _settlement_espionage_output(s, gs.db))
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
static func _settlement_espionage_flat(s: Settlement, db: DataDB) -> int:
	var flat: int = 0
	for struct_id in s.structures:
		flat += int(db.get_structure(struct_id).get("effects", {}).get("espionage", 0))
	return flat

# Sum of the `espionage_output` percent modifiers a settlement's structures grant
# (they stack additively, e.g. Intelligence Agency +50% with Scotland Yard +100%).
static func _settlement_espionage_output(s: Settlement, db: DataDB) -> int:
	var pct: int = 0
	for struct_id in s.structures:
		pct += int(db.get_structure(struct_id).get("effects", {}).get("espionage_output", 0))
	return pct

static func _tick_states(gs: GameState, player: Player) -> void:
	if player.transition_turns > 0:
		player.transition_turns -= 1
	if player.celebration_turns > 0:
		player.celebration_turns -= 1
	# A running Golden Age counts down one turn (§14.4).
	GreatPeople.tick_golden_age(player)
	for s in gs.settlements:
		if s.owner_player_id != player.id:
			continue
		if s.rush_anger_turns > 0:
			s.rush_anger_turns -= 1

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
		# Honour manual locks first: a player-locked tile is always worked, as
		# long as it is in range, ownable, and within the worker budget.
		var assigned: int = 0
		var locked_set := {}
		for lt in s.locked_tiles:
			if assigned >= workers_needed:
				break
			var lx: int = int(lt[0]); var ly: int = int(lt[1])
			if not gs.map.is_valid(lx, ly):
				continue
			var ltile = gs.map.get_tile(lx, ly)
			if ltile == null:
				continue
			if not (ltile.owner_player_id == player.id or ltile.owner_player_id == -1):
				continue
			s.worked_tiles.append([lx, ly])
			locked_set[str(lx) + "," + str(ly)] = true
			assigned += 1
		# When citizen management is manual, stop here — only locked tiles work.
		if not s.manage_citizens_auto:
			continue
		# Gather candidate tiles owned by this player (excluding ones already
		# locked-in above).
		var candidates := []
		for tile in gs.map.tiles_in_range(s.x, s.y, s.culture_ring):
			if locked_set.has(str(tile.x) + "," + str(tile.y)):
				continue
			if tile.owner_player_id == player.id or tile.owner_player_id == -1:
				var out: Array = TileOutput.compute(tile, db, player.technologies)
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

static func _add_presence(presence: Dictionary, x: int, y: int, player_id: int) -> void:
	var key: String = "%d,%d" % [x, y]
	if not presence.has(key):
		presence[key] = {}
	presence[key][player_id] = true

# For one sight source at (cx, cy) belonging to seer_id, walk the visible tiles
# (Manhattan radius, matching the fog/wild sight model) and record contact with
# every other player present on any of them.
static func _scan_sight_contact(gs: GameState, presence: Dictionary,
		cx: int, cy: int, radius: int, seer_id: int) -> void:
	for t in gs.map.tiles_in_range(cx, cy, radius):
		if gs.map.manhattan(cx, cy, t.x, t.y) > radius:
			continue
		var here: Dictionary = presence.get("%d,%d" % [t.x, t.y], {})
		for other_id in here:
			if int(other_id) != seer_id:
				_ensure_mutual_contact(gs, seer_id, int(other_id))

static func _ensure_mutual_contact(gs: GameState, pid_a: int, pid_b: int) -> void:
	var a: Alliance = gs.get_player_alliance(pid_a)
	var b: Alliance = gs.get_player_alliance(pid_b)
	if a == null or b == null or a.id == b.id:
		return
	if not a.has_contact_with(b.id):
		a.contacts.append(b.id)
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
