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

	# 7. Resolve assembly/voting bodies (stub)
	if not hooks.run(IDs.Phase.WORLD_ASSEMBLY, gs):
		pass

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

	# Reset unit movement and action flags
	for u in gs.units:
		if u.owner_player_id == player_id:
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
	_update_contentment(s, player, db)

static func _update_wellbeing(s: Settlement, db: DataDB) -> void:
	var pos: int = 0
	var neg: int = s.population  # base negative from population
	for struct_id in s.structures:
		var struct: Dictionary = db.get_structure(struct_id)
		pos += int(struct.get("health_bonus", 0))
		neg += int(struct.get("health_penalty", 0))
	s.wellbeing_positive = pos
	s.wellbeing_negative = neg
	s.wellbeing_deficit = max(0, neg - pos)

static func _update_contentment(s: Settlement, player: Player, db: DataDB) -> void:
	var pos: int = 0
	var neg_anger: int = 0  # anger percentage points

	# Size-related comfort (base 3 for first city)
	pos += max(0, 3 - (s.population / 4))

	# Structures
	for struct_id in s.structures:
		var struct: Dictionary = db.get_structure(struct_id)
		pos += int(struct.get("happiness_bonus", 0))

	# Policy anger
	for cat in player.policies:
		var pol_id: String = player.policies[cat]
		var pol: Dictionary = db.policies.get("policies", {}).get(pol_id, {})
		neg_anger += int(pol.get("anger_modifier", 0))

	# Rush penalty
	if s.rush_anger_turns > 0:
		neg_anger += 20

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
		points += s.specialists[spec_type]
	s.special_person_points += points

	# When threshold is crossed, emit event (handled by facade)
	# Threshold increases with each produced special person (stub rising threshold)
	if s.special_person_points >= s.special_person_threshold:
		s.special_person_points -= s.special_person_threshold
		s.special_person_threshold = Fixed.scale_up(s.special_person_threshold, 25)

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

	player.treasury += income - upkeep

	# Insolvency: force research down if broke
	if player.treasury < 0:
		player.treasury = 0
		if player.slider_research > 0:
			player.slider_research = max(0, player.slider_research - 10)
			var freed: int = 10
			player.slider_finance += freed

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
		var workers_needed: int = s.effective_workers()
		s.worked_tiles = []
		# Gather candidate tiles owned by this player, sorted by food output descending
		var candidates := []
		for tile in gs.map.tiles_in_range(s.x, s.y, s.culture_ring):
			if tile.owner_player_id == player.id or tile.owner_player_id == -1:
				var out: Array = TileOutput.compute(tile, db, player.technologies)
				var score: int = out[0] * 3 + out[1] * 2 + out[2]
				candidates.append([score, tile.x, tile.y])
		candidates.sort()
		candidates.invert()
		var assigned: int = 0
		for c in candidates:
			if assigned >= workers_needed:
				break
			s.worked_tiles.append([c[1], c[2]])
			assigned += 1

static func _resolve_trades(gs: GameState) -> void:
	for alliance in gs.alliances:
		var expired := []
		for i in range(alliance.pending_trades.size()):
			var trade: Dictionary = alliance.pending_trades[i]
			if int(trade.get("expires_turn", 0)) <= gs.turn_number:
				expired.append(i)
		for i in range(expired.size() - 1, -1, -1):
			alliance.pending_trades.remove(expired[i])

static func _advance_alliances(gs: GameState) -> void:
	for alliance in gs.alliances:
		for pid in alliance.member_player_ids:
			var p: Player = gs.get_player(pid)
			if p == null:
				continue
			# Shared research: each member contributes to the pool
			var research_contrib: int = 0
			for s in gs.settlements:
				if s.owner_player_id != pid:
					continue
				var split: Array = p.split_commerce(s.output_commerce)
				research_contrib += split[1]
			alliance.shared_research_store += research_contrib / max(1, alliance.member_player_ids.size())

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
