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

	# Economic organizations spread across settlements (§8). Cheap; runs each
	# world step independent of the per-phase hooks.
	EconOrgs.spread_all(gs, gs.rng)

	# Tributaries pay tribute to their overlords (§7).
	_collect_tribute(gs)

	# 3. Per-tile upkeep across the whole map
	if not hooks.run(IDs.Phase.WORLD_TILE_UPKEEP, gs):
		_tile_upkeep(gs)

	# 4. Spawn wild/raider settlements and units
	if not hooks.run(IDs.Phase.WORLD_SPAWN_WILD, gs):
		WildForces.spawn_turn(gs, gs.rng)
		WildForces.spawn_raider_settlement(gs, gs.rng)

	# 5. Environmental degradation
	if not hooks.run(IDs.Phase.WORLD_ENVIRONMENTAL, gs):
		Pollution.accumulate(gs)
		Pollution.degrade(gs, gs.rng)

	# 6. Assign/reassign special institutional sites (stub)
	if not hooks.run(IDs.Phase.WORLD_ASSIGN_SITES, gs):
		pass

	# 7. Resolve assembly/voting bodies
	if not hooks.run(IDs.Phase.WORLD_ASSEMBLY, gs):
		_resolve_assembly(gs)

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

	# Units that held position grow entrenchment and heal (§5.3, §5.6); a unit
	# does neither on a turn it moves or fights. Moving/attacking resets
	# entrenchment to 0 at the command site. Then reset flags for next turn.
	var ent_cap: int = gs.db.get_constant("entrenchment_cap", 25)
	var ent_per: int = gs.db.get_constant("entrenchment_per_turn", 5)
	for u in gs.units:
		if u.owner_player_id != player_id:
			continue
		if not u.has_moved and not u.has_attacked:
			u.stationary_turns += 1
			var ent: int = u.stationary_turns * ent_per
			u.entrenchment = ent_cap if ent > ent_cap else ent
			_heal_unit(gs, u, player)
		u.movement_left = u.movement_total
		u.has_moved = false
		u.has_attacked = false

# ── Per-settlement step ───────────────────────────────────────────────────────

static func settlement_step(gs: GameState, s: Settlement,
		player: Player, hooks: Hooks) -> void:
	# Growth
	if not hooks.run(IDs.Phase.SETTLEMENT_GROWTH, gs, {"settlement_id": s.id}):
		_settlement_growth(gs, s, player)

	# Production
	if not hooks.run(IDs.Phase.SETTLEMENT_PRODUCTION, gs, {"settlement_id": s.id}):
		_settlement_production(gs, s, player)

	# Culture accumulation + spread
	if not hooks.run(IDs.Phase.SETTLEMENT_CULTURE, gs, {"settlement_id": s.id}):
		_settlement_culture(gs, s)

	# Belief/affiliation processing
	if not hooks.run(IDs.Phase.SETTLEMENT_BELIEFS, gs, {"settlement_id": s.id}):
		Beliefs.spread_all(gs, gs.rng)

	# Decay/upkeep
	if not hooks.run(IDs.Phase.SETTLEMENT_DECAY, gs, {"settlement_id": s.id}):
		_settlement_upkeep(gs, s, player)

	# Special-person progress
	if not hooks.run(IDs.Phase.SETTLEMENT_SPECIALISTS, gs, {"settlement_id": s.id}):
		_special_person_progress(gs, s)

# ── Internal helpers ──────────────────────────────────────────────────────────

static func _settlement_growth(gs: GameState, s: Settlement, player: Player) -> void:
	var db: DataDB = gs.db

	# Compute output from worked tiles
	var total_food: int = 0
	var total_prod: int = 0
	var total_commerce: int = 0

	for wt in s.worked_tiles:
		var tile: Tile = gs.map.get_tile(int(wt[0]), int(wt[1]))
		if tile == null:
			continue
		var out: Array = TileOutput.compute(tile, db, player.technologies)
		total_food     += out[IDs.Output.FOOD]
		total_prod     += out[IDs.Output.PRODUCTION]
		total_commerce += out[IDs.Output.COMMERCE]

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
	total_commerce += spec_count * db.get_constant("specialist_commerce", 3)

	s.output_food       = total_food
	s.output_production = total_prod
	s.output_commerce   = total_commerce

	# Wellbeing: deficit reduces food surplus
	_update_wellbeing(s, db)
	var effective_food: int = total_food - s.wellbeing_deficit
	var consumed: int = s.population * 2
	var surplus: int = effective_food - consumed

	s.food_store += surplus

	# Growth threshold
	var base: int = db.get_constant("growth_base", 20)
	var pace: Dictionary = db.get_pace(gs.pace_id)
	var pace_scale: int = int(pace.get("growth_scale", 100))
	var threshold: int = Fixed.scale(base * s.population, pace_scale)

	if s.food_store >= threshold:
		s.population += 1
		var carry_frac: int = 50  # carry 50% of threshold
		if s.has_structure("granary"):
			carry_frac = int(db.get_structure("granary").get("effects", {}).get("food_carry_over", 50))
		s.food_store = Fixed.scale(threshold, carry_frac)
	elif s.food_store < 0:
		s.food_store = 0
		if s.population > 1:
			s.population -= 1

	# Contentment update
	_update_contentment(gs, s, player, db)

static func _update_wellbeing(s: Settlement, db: DataDB) -> void:
	var pos: int = 0
	var neg: int = s.population  # base negative from population
	for struct_id in s.structures:
		var struct: Dictionary = db.get_structure(struct_id)
		pos += int(struct.get("health_bonus", 0))
		neg += int(struct.get("health_penalty", 0))
	# Adopted belief wellbeing (§8)
	if s.belief_id != "":
		pos += int(db.beliefs.get(s.belief_id, {}).get("health_bonus", 0))
	s.wellbeing_positive = pos
	s.wellbeing_negative = neg
	s.wellbeing_deficit = max(0, neg - pos)

static func _update_contentment(gs: GameState, s: Settlement, player: Player, db: DataDB) -> void:
	var pos: int = 0
	var neg_anger: int = 0  # anger percentage points

	# Size-related comfort (base 3 for first city)
	pos += max(0, 3 - (s.population / 4))

	# Structures
	for struct_id in s.structures:
		var struct: Dictionary = db.get_structure(struct_id)
		pos += int(struct.get("happiness_bonus", 0))

	# Adopted belief comfort (§8)
	if s.belief_id != "":
		pos += int(db.beliefs.get(s.belief_id, {}).get("happiness_bonus", 0))

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
		neg_anger += fatigue_total / max(1, db.get_constant("war_fatigue_anger_divisor", 4))

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
	s.production_store += prod

	var item: Dictionary = s.production_queue[0]
	var cost: int = _item_cost(item, db, player, pace)
	if cost <= 0:
		return

	if s.production_store >= cost:
		s.production_store -= cost
		_complete_item(gs, s, player, item)
		s.production_queue.remove(0)

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
			gs.units.append(u)
		"structure":
			if not s.has_structure(iid):
				s.structures.append(iid)
		"project":
			var proj: Dictionary = gs.db.projects.get(iid, {})
			var alliance_id: int = player.alliance_id
			if not gs.endgame_project_stages.has(alliance_id):
				gs.endgame_project_stages[alliance_id] = 0
			gs.endgame_project_stages[alliance_id] += 1

static func _settlement_culture(gs: GameState, s: Settlement) -> void:
	var db: DataDB = gs.db
	var thresholds: Array = db.constants.get("culture_ring_thresholds",
		[10, 30, 60, 100, 150, 210, 280, 360, 450, 550])

	s.culture_total += s.output_commerce  # culture comes from commerce channel (simplified)

	# Ring expansion
	var ring: int = 1
	for thresh in thresholds:
		if s.culture_total >= thresh:
			ring += 1
		else:
			break
	ring = min(ring, thresholds.size())
	s.culture_ring = ring

	# Spread cultural influence
	Influence.spread(gs.map, s.x, s.y, s.output_commerce, ring, s.owner_player_id, db)
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
	s.special_person_points += points

	# When the rising threshold is crossed, produce a special person and apply
	# its effect. The threshold then grows for the next one (§6.5).
	if s.special_person_points >= s.special_person_threshold:
		s.special_person_points -= s.special_person_threshold
		s.special_person_threshold = Fixed.scale_up(s.special_person_threshold, 25)
		s.special_persons_produced += 1
		_apply_special_person(gs, s)

# A produced special person grants an instant technology to its owner if one is
# being researched; otherwise it settles for a one-off economic bonus (§6.5).
static func _apply_special_person(gs: GameState, s: Settlement) -> void:
	var player: Player = gs.get_player(s.owner_player_id)
	if player == null:
		return
	if player.current_research_id != "" and not player.has_tech(player.current_research_id):
		player.technologies.append(player.current_research_id)
		player.current_research_id = ""
		player.research_store = 0
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

	# Upkeep for units
	var upkeep: int = 0
	for u in gs.units:
		if u.owner_player_id != player.id:
			continue
		var udata: Dictionary = db.get_unit(u.unit_type_id)
		upkeep += int(udata.get("upkeep", 0))

	# Settlement upkeep scales with distance from the capital and settlement size
	# (§6.1). The capital is the player's earliest-founded settlement.
	var capital: Settlement = _find_capital(gs, player.id)
	var dist_scale: int = db.get_constant("upkeep_distance_scale", 1)
	var size_scale: int = db.get_constant("upkeep_size_scale", 1)
	for s in gs.settlements:
		if s.owner_player_id != player.id:
			continue
		var dist: int = 0
		if capital != null:
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

# The player's capital: the surviving settlement with the lowest id (earliest
# founded). Null if the player has no settlements.
static func _find_capital(gs: GameState, player_id: int) -> Settlement:
	var capital: Settlement = null
	for s in gs.settlements:
		if s.owner_player_id != player_id:
			continue
		if capital == null or s.id < capital.id:
			capital = s
	return capital

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
	for s in gs.settlements:
		if s.owner_player_id != player.id:
			continue
		var split: Array = player.split_commerce(s.output_commerce)
		research_income += split[1]  # research

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

static func _apply_intelligence(gs: GameState, player: Player) -> void:
	# Accumulate intel points from commerce allocation
	for s in gs.settlements:
		if s.owner_player_id != player.id:
			continue
		var split: Array = player.split_commerce(s.output_commerce)
		var intel: int = split[3]
		# Distribute evenly across all known alliances
		var alliance: Alliance = gs.get_player_alliance(player.id)
		if alliance == null:
			continue
		for target_aid in alliance.contacts:
			if not player.intel_points.has(target_aid):
				player.intel_points[target_aid] = 0
			var share: int = intel / max(1, alliance.contacts.size())
			player.intel_points[target_aid] += share

static func _tick_states(gs: GameState, player: Player) -> void:
	if player.transition_turns > 0:
		player.transition_turns -= 1
	if player.celebration_turns > 0:
		player.celebration_turns -= 1
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
		# Gather candidate tiles owned by this player.
		var candidates := []
		for tile in gs.map.tiles_in_range(s.x, s.y, s.culture_ring):
			if tile.owner_player_id == player.id or tile.owner_player_id == -1:
				var out: Array = TileOutput.compute(tile, db, player.technologies)
				var score: int = out[0] * 3 + out[1] * 2 + out[2]
				candidates.append([score, tile.x, tile.y])
		# Repeatedly take the best candidate. A plain candidates.sort() would
		# compare [score, x, y] sub-arrays, which Godot cannot order consistently
		# ("bad comparison function; sorting will be broken").
		var assigned: int = 0
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

# Diplomatic assembly (§3.7): each alliance's voting weight is the population it
# governs. The tally feeds the diplomatic win condition (§10).
static func _resolve_assembly(gs: GameState) -> void:
	var votes := {}
	for s in gs.settlements:
		var p: Player = gs.get_player(s.owner_player_id)
		if p == null:
			continue
		votes[p.alliance_id] = int(votes.get(p.alliance_id, 0)) + s.population
	gs.diplomatic_votes = votes

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

static func _tile_upkeep(gs: GameState) -> void:
	# Tile-level upkeep (improvement maintenance) — currently stub
	pass

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
