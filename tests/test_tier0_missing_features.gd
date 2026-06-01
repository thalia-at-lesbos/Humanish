extends "res://addons/gut/test.gd"

# Tier 0 fixes from docs/missing-engine-features.md:
#   1. diplomatic win condition           (§10)
#   2. flanking damage application         (§5.4)
#   3. entrenchment growth while stationary(§5.3)
#   4. wonders counted in score            (§10)
#   5. withdrawal no longer a no-op hit    (§5.4)

func _make_db():
	var db = load("res://src/core/data_db.gd").new()
	db.load_all()
	return db

func _make_gs():
	var db = _make_db()
	var gs = load("res://src/sim/game_state.gd").new()
	gs.db = db
	gs.rng = load("res://src/core/rng.gd").new()
	gs.rng.init(42)
	gs.map = load("res://src/world/world_map.gd").new()
	gs.map.init(20, 20, false, false)
	for tile in gs.map.all_tiles():
		tile.terrain_id = "grassland"
	var p1 = load("res://src/sim/player.gd").new()
	p1.id = 1; p1.alliance_id = 1
	var p2 = load("res://src/sim/player.gd").new()
	p2.id = 2; p2.alliance_id = 2
	gs.players.append(p1); gs.players.append(p2)
	var a1 = load("res://src/sim/alliance.gd").new(); a1.id = 1; a1.add_member(1)
	var a2 = load("res://src/sim/alliance.gd").new(); a2.id = 2; a2.add_member(2)
	gs.alliances.append(a1); gs.alliances.append(a2)
	return gs

func _make_warrior(gs, player_id, x, y):
	var u = load("res://src/sim/unit.gd").new()
	u.id = gs.next_unit_id()
	u.unit_type_id = "warrior"
	u.owner_player_id = player_id
	u.x = x; u.y = y
	u.base_strength = 10
	u.health = 100
	u.movement_total = 200; u.movement_left = 200
	gs.units.append(u)
	return u

func _hooks():
	return load("res://src/sim/hooks.gd").new()

# ── 1. Diplomatic win condition ────────────────────────────────────────────────

func test_diplomatic_win_on_supermajority() -> void:
	var gs = _make_gs()
	gs.enabled_win_conditions = ["diplomatic"]
	gs.diplomatic_votes = {1: 70, 2: 30}  # 70% >= 67% required
	assert_eq(WinConditions.check_all(gs), 1,
		"Alliance with the required vote share wins diplomatically")

func test_diplomatic_no_win_below_threshold() -> void:
	var gs = _make_gs()
	gs.enabled_win_conditions = ["diplomatic"]
	gs.diplomatic_votes = {1: 60, 2: 40}  # 60% < 67%
	assert_eq(WinConditions.check_all(gs), -1,
		"No diplomatic win below the required share")

func test_diplomatic_no_win_without_votes() -> void:
	var gs = _make_gs()
	gs.enabled_win_conditions = ["diplomatic"]
	assert_eq(WinConditions.check_all(gs), -1,
		"No diplomatic win when the assembly has cast no votes")

func test_diplomatic_votes_survive_save_load() -> void:
	var gs = _make_gs()
	gs.diplomatic_votes = {1: 5, 2: 9}
	var restored = load("res://src/sim/game_state.gd").deserialize(gs.serialize(), gs.db)
	assert_eq(int(restored.diplomatic_votes.get(2, 0)), 9,
		"diplomatic_votes round-trips through serialization")

# ── 2. Flanking damage ─────────────────────────────────────────────────────────

func test_flanking_damages_stacked_unit() -> void:
	var gs = _make_gs()
	# A "fast"-tagged attacker triggers flanking on a kill (§5.4).
	gs.db.units["raider_horse"] = {
		"id": "raider_horse", "base_strength": 200, "movement": 300,
		"classification": "cavalry", "tags": ["fast"],
		"first_strikes": 0, "combat_limit": 0, "withdrawal_chance": 0,
		"upkeep": 0, "cost": 40
	}
	var atk = load("res://src/sim/unit.gd").new()
	atk.id = gs.next_unit_id(); atk.unit_type_id = "raider_horse"
	atk.owner_player_id = 1; atk.x = 5; atk.y = 6
	atk.base_strength = 200; atk.health = 100
	atk.movement_total = 300; atk.movement_left = 300
	gs.units.append(atk)

	var def1 = _make_warrior(gs, 2, 5, 5)   # the unit being attacked
	var def2 = _make_warrior(gs, 2, 5, 5)   # stacked behind it

	var rng = load("res://src/core/rng.gd").new(); rng.init(7)
	var result: Dictionary = Combat.resolve(atk, def1, gs, rng)
	assert_false(result["defender_survived"], "Overwhelming attacker kills the defender")
	assert_gt(result["flanking_damage"], 0, "Fast attacker produces flanking damage")

	var before: int = def2.health
	var facade = load("res://src/api/sim_facade.gd").new()
	facade._gs = gs
	facade._apply_combat_result(atk, def1, result)
	assert_lt(def2.health, before, "Stacked unit takes flanking damage when its defender falls")

# ── 3. Entrenchment growth ─────────────────────────────────────────────────────

func test_entrenchment_grows_while_stationary() -> void:
	var gs = _make_gs()
	var u = _make_warrior(gs, 1, 5, 5)
	u.entrenchment = 0; u.stationary_turns = 0
	var per: int = gs.db.get_constant("entrenchment_per_turn", 5)
	TurnEngine.player_step(gs, 1, _hooks())
	assert_eq(u.entrenchment, per, "One stationary turn grants one increment of entrenchment")
	TurnEngine.player_step(gs, 1, _hooks())
	assert_eq(u.entrenchment, per * 2, "A second stationary turn stacks entrenchment")

func test_entrenchment_capped() -> void:
	var gs = _make_gs()
	var u = _make_warrior(gs, 1, 5, 5)
	var cap: int = gs.db.get_constant("entrenchment_cap", 25)
	for _i in range(20):
		TurnEngine.player_step(gs, 1, _hooks())
	assert_eq(u.entrenchment, cap, "Entrenchment never exceeds the data cap")

func test_moving_unit_does_not_entrench() -> void:
	var gs = _make_gs()
	var u = _make_warrior(gs, 1, 5, 5)
	u.has_moved = true   # simulate having moved this turn
	TurnEngine.player_step(gs, 1, _hooks())
	assert_eq(u.entrenchment, 0, "A unit that moved this turn gains no entrenchment")
	assert_eq(u.stationary_turns, 0, "Stationary counter stays at zero for a moved unit")

# ── 4. Wonders in score ────────────────────────────────────────────────────────

func test_wonder_raises_score() -> void:
	var gs = _make_gs()
	gs.db.structures["great_wonder"] = {"id": "great_wonder", "is_wonder": true}
	var s = load("res://src/sim/settlement.gd").new()
	s.id = gs.next_settlement_id(); s.owner_player_id = 1
	s.x = 5; s.y = 5; s.population = 1
	gs.settlements.append(s)

	Scoring.compute_all(gs)
	var base_score: int = gs.get_player(1).score
	s.structures.append("great_wonder")
	Scoring.compute_all(gs)
	assert_gt(gs.get_player(1).score, base_score, "Owning a wonder increases the player's score")

# ── 5. Withdrawal path ─────────────────────────────────────────────────────────

func test_withdrawal_saves_attacker_from_fatal_hit() -> void:
	var gs = _make_gs()
	gs.db.units["coward"] = {
		"id": "coward", "base_strength": 1, "movement": 200,
		"classification": "melee", "tags": [],
		"first_strikes": 0, "combat_limit": 0, "withdrawal_chance": 100,
		"upkeep": 0, "cost": 10
	}
	var atk = load("res://src/sim/unit.gd").new()
	atk.id = gs.next_unit_id(); atk.unit_type_id = "coward"
	atk.owner_player_id = 1; atk.x = 5; atk.y = 6
	atk.base_strength = 1; atk.health = 100
	atk.movement_total = 200; atk.movement_left = 200
	gs.units.append(atk)

	var defender = _make_warrior(gs, 2, 5, 5)
	defender.base_strength = 100  # all but guaranteed to win each round

	var rng = load("res://src/core/rng.gd").new(); rng.init(3)
	var result: Dictionary = Combat.resolve(atk, defender, gs, rng)
	assert_true(result["attacker_withdrew"], "Guaranteed-withdrawal attacker retreats")
	assert_true(result["attacker_survived"], "A withdrawing attacker survives the fatal hit")
	assert_eq(result["attacker_health_after"], 100,
		"Withdrawn attacker reports its pre-combat health, not a mangled value")
