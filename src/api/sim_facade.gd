# Humanish — a turn-based 4X strategy game.
# Copyright (C) 2026 thalia-at-lesbos
# SPDX-License-Identifier: GPL-3.0-or-later
#
# This program is free software: you can redistribute it and/or modify it
# under the terms of the GNU General Public License as published by the Free
# Software Foundation, either version 3 of the License, or (at your option)
# any later version. See the LICENSE file for the full text and warranty
# disclaimer.

class_name SimFacade
extends Reference

# Public surface of the simulation engine.
# The only way to mutate state is apply_command().
# Events are emitted as signals so UI can observe without polling.

# _run_espionage_mission outcomes (§7.1): callers must distinguish an intercepted
# mission (EP spent; a tile spy is captured) from a gate/afford rejection
# (nothing spent) and a clean execution.
enum MissionRun { REJECTED, EXECUTED, INTERCEPTED }

signal event_emitted(event_dict)
signal quest_event(quest_dict)   # §4 multi-turn quest armed / completed / reward-pending / failed
signal turn_advanced(turn_number)
signal game_won(alliance_id)
signal unit_created(unit_id)
signal settlement_founded(settlement_id)
signal city_conquered(settlement_id, captor_player_id)   # kept (in revolt) — §4.8
signal city_razed(settlement_id, by_player_id)           # destroyed — §4.8
signal city_flipped(settlement_id, from_player_id, to_player_id)  # cultural — §4.9
signal technology_completed(player_id, tech_id)
signal era_advanced(player_id, from_era, to_era)         # §1
signal goody_received(reward)   # §9 goody-hut / discovery-site reward claimed
signal combat_resolved(result_dict)
signal player_turn_started(player_id)
signal screen_requested(screen_id)
signal assembly_event(event_dict)   # §7.2 session opened / resolution resolved
signal deal_cancelled(deal_dict)    # §7 persistent deal expired or cancelled
signal nuclear_detonated(result_dict)  # §5.7 nuke strike resolved (area effect)
signal first_contact(player_id, other_player_id)  # §7 two players newly met

var _gs: GameState
var _hooks: Hooks
var _db: DataDB

# UI state (not part of simulation; not serialized)
var _dirty: DirtyFlags
var _selection: SelectionState
var _interface_mode: int = 0    # IDs.InterfaceMode.SELECTION
var _popup_queue: Array = []
var _notifications: Array = []
# Transient (not serialized): informational popups for quests freshly armed for a
# human, surfaced once at the owner's next turn start by TurnPrompts (§4).
var _quest_info_popups: Array = []

# Remote-multiplayer client seam (not part of simulation; not serialized).
# When a NetClient installs a submit handler, this facade is a remote client:
# ending the turn no longer runs the local pipeline — instead the handler ships
# the player's post-move snapshot to the authoritative server, and the facade is
# parked in a "waiting" state until the server pushes the next turn's state.
# In server / single-player mode these stay null/false and nothing changes.
var _remote_submit_cb = null     # FuncRef() → bool, set via set_remote_submit_handler()
var _remote_waiting: bool = false

# ── Lifecycle ─────────────────────────────────────────────────────────────────

func setup(db: DataDB, seed_val: int, world_size_id: String, pace_id: String,
		difficulty_id: String, player_configs: Array,
		enabled_win_conditions: Array, map_type_id: String = "continents",
		aggressive_wild: bool = false,
		permanent_alliances: bool = false,
		events_enabled: bool = true) -> void:
	_db = db
	_hooks = Hooks.new()
	_dirty = load("res://src/api/dirty_flags.gd").new()
	_selection = load("res://src/api/selection_state.gd").new()
	_interface_mode = IDs.InterfaceMode.SELECTION
	_popup_queue = []
	_notifications = []
	_quest_info_popups = []

	_gs = GameState.new()
	_gs.db = db
	_gs.rng = RNG.new()
	_gs.rng.init(seed_val)
	_gs.pace_id = pace_id
	_gs.difficulty_id = difficulty_id
	_gs.world_size_id = world_size_id
	_gs.enabled_win_conditions = enabled_win_conditions.duplicate()
	_gs.wild_aggressive = aggressive_wild
	_gs.permanent_alliances = permanent_alliances
	_gs.events_enabled = events_enabled

	var ws: Dictionary = db.get_world_size(world_size_id)
	_gs.max_turns = int(db.get_pace(pace_id).get("max_turns", 500))

	# The map-type spec may override the world-size wrap flags (e.g. "archipelago"
	# sets wrap_x=false so island maps have a hard east/west edge).
	var mt: Dictionary = db.get_map_type(map_type_id)
	var map_wrap_x: bool = bool(mt.get("wrap_x", ws.get("wrap_x", true)))
	var map_wrap_y: bool = bool(mt.get("wrap_y", ws.get("wrap_y", false)))

	_gs.map = WorldMap.new()
	_gs.map.init(
		int(ws.get("width", 80)),
		int(ws.get("height", 48)),
		map_wrap_x,
		map_wrap_y
	)
	# Populate the blank grid with the chosen map script. Uses gs.rng so the result
	# is deterministic for the seed and is captured by save/load (tiles serialize).
	MapGen.generate(_gs.map, db, _gs.rng, map_type_id)

	# Choose start positions once (pure, no RNG draw), then run the map-fairness and
	# goody-hut passes that depend on them. Order is fixed so the shared RNG stream
	# stays deterministic: generate → normalize starts → scatter goody huts. The
	# normalize pass may reposition weak starts (step 1) — it mutates `starts` in
	# place, and the same array feeds unit placement below, so it is never recomputed.
	var starts: Array = MapGen.find_start_positions(_gs.map, db, player_configs.size(), map_type_id)
	MapGen.normalize_starts(_gs.map, db, _gs.rng, starts, map_type_id)
	MapGen.place_goody_huts(_gs.map, db, _gs.rng, starts)

	# Create players and alliances
	var difficulty: Dictionary = db.get_difficulty(difficulty_id)
	var default_techs: Array = db.constants.get("starting_techs", [])
	var default_research: String = str(db.constants.get("default_research", ""))
	for cfg in player_configs:
		var p := Player.new()
		p.id = _gs.next_player_id()
		p.name = str(cfg.get("name", "Player " + str(p.id)))
		p.leader_id = str(cfg.get("leader_id", ""))
		# Society id drives historical city naming. Prefer the explicit cfg value;
		# if absent, recover it by reverse-lookup from the unique leader_id.
		p.society_id = str(cfg.get("society_id", ""))
		if p.society_id == "" and p.leader_id != "":
			p.society_id = db.society_id_for_leader(p.leader_id)
		p.traits = cfg.get("traits", []).duplicate()
		p.free_early_wins = int(difficulty.get("free_early_wins", 0))
		p.treasury = int(cfg.get("starting_gold", 100))
		p.is_ai = bool(cfg.get("is_ai", false))

		# Seed the player's known techs and pick a default research target so the
		# tech tree (data/technologies.json) is usable from turn one. A player's
		# society supplies its own starting techs (cfg["starting_techs"]); society-
		# less players (default/headless games) fall back to the global default.
		p.technologies = cfg.get("starting_techs", default_techs).duplicate()
		if default_research != "" and Research.can_research(default_research, p, db):
			p.current_research_id = default_research
		# Seed the era cache from the starting techs (no notification at game start —
		# gs is omitted so nothing is queued).
		Eras.refresh(p, db)

		# Each player starts in their own alliance
		var a := Alliance.new()
		a.id = _gs.next_alliance_id()
		a.add_member(p.id)
		p.alliance_id = a.id
		_gs.alliances.append(a)
		_gs.players.append(p)

	if not _gs.players.empty():
		_gs.current_player_id = _gs.players[0].id

	# Place each player's opening units (data-driven via cfg["starting_units"]).
	# Players with no starting units (e.g. headless test configs) get none, so
	# the engine stays generic and society→unit mapping lives in the caller.
	_place_all_starting_units(player_configs, starts)

	# Roll this game's random-event roster (§9): each event's `active` inclusion
	# percent is drawn once from gs.rng in fixed event-id order, so the roster is
	# deterministic for the seed and is captured by save/load (active_event_ids).
	# Skipped entirely when the random-event/quest system is switched off (new-game
	# menu) — the same toggle governs both events and multi-turn quests.
	if _gs.events_enabled:
		Events.roll_active_events(_gs)
		# Roll this game's quest roster (§4) the same way, immediately after the events
		# roll so the RNG draw order stays fixed for the seed.
		Quests.roll_active_quests(_gs)

# Initialize only the non-serialized scaffolding (db, hooks, UI state) so a save
# can be loaded into a fresh facade without running setup(). load_save() then
# supplies the GameState. Used by the start menu's "Load Game" path.
func init_for_load(db: DataDB) -> void:
	_db = db
	_hooks = Hooks.new()
	_dirty = load("res://src/api/dirty_flags.gd").new()
	_selection = load("res://src/api/selection_state.gd").new()
	_interface_mode = IDs.InterfaceMode.SELECTION
	_popup_queue = []
	_notifications = []

func _place_all_starting_units(player_configs: Array, starts: Array) -> void:
	for i in range(_gs.players.size()):
		if i >= player_configs.size() or i >= starts.size():
			break
		var su: Array = player_configs[i].get("starting_units", [])
		if su.empty():
			continue
		_spawn_starting_units(_gs.players[i].id, int(starts[i][0]), int(starts[i][1]), su)

# Spawn a list of unit type ids for a player, fanned out across the start tile
# and its passable land neighbours so they do not all hide on one square.
func _spawn_starting_units(player_id: int, sx: int, sy: int, unit_types: Array) -> void:
	var tiles: Array = [[sx, sy]]
	for nb in _gs.map.neighbours8(sx, sy):
		var ter: Dictionary = _db.get_terrain(nb.terrain_id)
		if ter.get("domain", "land") == "land" and not ter.get("impassable", false):
			tiles.append([nb.x, nb.y])

	for k in range(unit_types.size()):
		var slot: Array = tiles[k % tiles.size()]
		_spawn_unit(str(unit_types[k]), player_id, int(slot[0]), int(slot[1]))

# Create a single unit of the given type for a player at (x, y), pulling stats
# from data/units.json. Returns the new unit id (-1 if the type is unknown).
func _spawn_unit(unit_type_id: String, player_id: int, x: int, y: int) -> int:
	var udata: Dictionary = _db.get_unit(unit_type_id)
	if udata.empty():
		return -1
	var u := Unit.new()
	u.id = _gs.next_unit_id()
	u.unit_type_id = unit_type_id
	u.owner_player_id = player_id
	u.x = x; u.y = y
	u.base_strength = int(udata.get("base_strength", 0))
	u.movement_total = int(udata.get("movement", 120))
	u.movement_left = u.movement_total
	_gs.units.append(u)
	emit_signal("unit_created", u.id)
	return u.id

# Load from a save string.
func load_save(json_str: String) -> bool:
	var gs := SaveLoad.load_from_string(json_str, _db)
	if gs == null:
		return false
	_gs = gs
	return true

func save() -> String:
	return SaveLoad.save_to_string(_gs)

func state_hash() -> int:
	return SaveLoad.state_hash(_gs)

# ── Query ─────────────────────────────────────────────────────────────────────

func get_state() -> GameState:
	return _gs

func get_hooks() -> Hooks:
	return _hooks

# A player's current era as {index, id, name} (§1), for HUD/AI/presentation. The
# index is read live (highest era over researched techs), so it is always current
# even if the cached Player.era lags by a notification.
func get_player_era(player_id: int) -> Dictionary:
	var p: Player = _gs.get_player(player_id)
	var idx: int = Eras.player_era(p, _db)
	return {"index": idx, "id": Eras.era_id(idx, _db), "name": Eras.era_name(idx, _db)}

# Net gold per turn for a player (income - upkeep), for the HUD's signed gold
# rate and the AI's solvency checks. Reads TurnEngine's pure economy helpers so
# the previewed rate is exactly the delta _update_treasury will apply. 0 for an
# unknown player.
func get_player_gold_rate(player_id: int) -> int:
	var p: Player = _gs.get_player(player_id)
	if p == null:
		return 0
	return TurnEngine.net_gold(_gs, p)

# ── Diplomatic assembly (§7.2) ────────────────────────────────────────────────

# The full assembly record ({} when no founding wonder exists). Read-only.
func get_assembly_state() -> Dictionary:
	return _gs.assembly

# The proposal a player still owes a vote on, as {resolution_id, name, text}, or {}
# when there is no open session, the player is not a member, or they have voted.
func get_pending_vote(player_id: int) -> Dictionary:
	var p: Player = _gs.get_player(player_id)
	if p == null or not Assembly.has_open_session(_gs) or Assembly.has_voted(_gs, player_id):
		return {}
	if not Assembly.is_member(_gs, p, str(_gs.assembly.get("kind", ""))):
		return {}
	var pending: Dictionary = Assembly.pending_proposal(_gs)
	return {
		"resolution_id": str(pending.get("resolution_id", "")),
		"name": str(pending.get("name", "")),
		"text": str(pending.get("text", ""))
	}

# Convenience wrapper used by screens/AI: cast a vote through the command path.
func cast_assembly_vote(player_id: int, choice: String) -> bool:
	return apply_command(Commands.cast_vote(player_id, choice))

# ── Commands ──────────────────────────────────────────────────────────────────

# Apply a command. Returns true if accepted.
func apply_command(cmd: Dictionary) -> bool:
	var ctype: int = int(cmd.get("type", -1))
	var player_id: int = int(cmd.get("player_id", -1))

	# Remote client: an end-turn is not run locally — it is handed to the server
	# as a full-state submission (see set_remote_submit_handler). All other
	# commands fall through and mutate the local facade normally, exactly as in a
	# solo game, because the client owns the current turn until it submits. Once
	# parked (waiting on the server) a repeat end-turn is dropped, never run
	# through the local pipeline — only the server advances the authoritative game.
	if _remote_submit_cb != null and _is_end_turn_command(ctype, cmd):
		if _remote_waiting:
			return false
		return _remote_submit()

	# Validate it's this player's turn
	if player_id != _gs.current_player_id:
		return false

	match ctype:
		IDs.CommandType.END_TURN:
			return _cmd_end_turn(player_id)
		IDs.CommandType.MOVE_STACK:
			return _cmd_move_stack(cmd)
		IDs.CommandType.FOUND_SETTLEMENT:
			return _cmd_found_settlement(cmd)
		IDs.CommandType.SET_SLIDERS:
			return _cmd_set_sliders(cmd)
		IDs.CommandType.SET_PRODUCTION:
			return _cmd_set_production(cmd)
		IDs.CommandType.SET_RESEARCH:
			return _cmd_set_research(cmd)
		IDs.CommandType.SET_POLICY:
			return _cmd_set_policy(cmd)
		IDs.CommandType.SET_STATE_RELIGION:
			return _cmd_set_state_religion(cmd)
		IDs.CommandType.DECLARE_WAR:
			return _cmd_declare_war(cmd)
		IDs.CommandType.MAKE_PEACE:
			return _cmd_make_peace(cmd)
		IDs.CommandType.RUSH_PRODUCTION:
			return _cmd_rush_production(cmd)
		IDs.CommandType.RUSH_POPULATION:
			return _cmd_rush_population(cmd)
		IDs.CommandType.BUILD_IMPROVEMENT:
			return _cmd_build_improvement(cmd)
		IDs.CommandType.UNIT_WAKE, IDs.CommandType.UNIT_SLEEP, \
		IDs.CommandType.UNIT_FORTIFY, IDs.CommandType.UNIT_CANCEL_ORDERS, \
		IDs.CommandType.UNIT_DISBAND, IDs.CommandType.UNIT_UPGRADE, \
		IDs.CommandType.UNIT_PROMOTE, IDs.CommandType.UNIT_GIFT:
			return _cmd_unit_command(cmd)
		IDs.CommandType.MISSION_MOVE_TO, IDs.CommandType.MISSION_BUILD_ROAD, \
		IDs.CommandType.MISSION_SKIP_TURN, IDs.CommandType.MISSION_PILLAGE, \
		IDs.CommandType.MISSION_BOMBARD, IDs.CommandType.MISSION_AIRLIFT, \
		IDs.CommandType.MISSION_SENTRY, IDs.CommandType.MISSION_HEAL, \
		IDs.CommandType.MISSION_MOVE_TO_UNIT, IDs.CommandType.MISSION_RECON, \
		IDs.CommandType.MISSION_AIR_PATROL, IDs.CommandType.MISSION_SEA_PATROL, \
		IDs.CommandType.MISSION_CLEAN_FALLOUT, \
		IDs.CommandType.MISSION_CLEAR_FEATURE, \
		IDs.CommandType.MISSION_SLEEP_UNTIL_HEALED, \
		IDs.CommandType.MISSION_FORTIFY_UNTIL_HEALED, \
		IDs.CommandType.MISSION_EXPLORE:
			return _cmd_mission(cmd)
		IDs.CommandType.NUCLEAR_STRIKE:
			return _cmd_nuclear_strike(cmd)
		IDs.CommandType.DRAFT:
			return _cmd_draft(cmd)
		IDs.CommandType.SPREAD_BELIEF:
			return _cmd_spread_belief(cmd)
		IDs.CommandType.SPREAD_CORPORATION:
			return _cmd_spread_corporation(cmd)
		IDs.CommandType.DO_CONTROL:
			return _cmd_do_control(cmd)
		IDs.CommandType.PROPOSE_TRADE:
			return _cmd_propose_trade(cmd)
		IDs.CommandType.ACCEPT_TRADE:
			return _cmd_accept_trade(cmd)
		IDs.CommandType.REJECT_TRADE:
			return _cmd_reject_trade(cmd)
		IDs.CommandType.CANCEL_DEAL:
			return _cmd_cancel_deal(cmd)
		IDs.CommandType.ASSIGN_SPECIALIST:
			return _cmd_assign_specialist(cmd)
		IDs.CommandType.SET_TILE_WORKED:
			return _cmd_set_tile_worked(cmd)
		IDs.CommandType.SET_CITIZEN_AUTOMATION:
			return _cmd_set_citizen_automation(cmd)
		IDs.CommandType.DISBAND_CITY:
			return _cmd_disband_city(cmd)
		IDs.CommandType.DEQUEUE_PRODUCTION:
			return _cmd_dequeue_production(cmd)
		IDs.CommandType.MOVE_PRODUCTION_ITEM:
			return _cmd_move_production_item(cmd)
		IDs.CommandType.ESPIONAGE_MISSION:
			return _cmd_espionage_mission(cmd)
		IDs.CommandType.SPY_MISSION:
			return _cmd_spy_mission(cmd)
		IDs.CommandType.LOAD_UNIT:
			return _cmd_load_unit(cmd)
		IDs.CommandType.UNLOAD_UNIT:
			return _cmd_unload_unit(cmd)
		IDs.CommandType.SET_SUBORDINATION:
			return _cmd_set_subordination(cmd)
		IDs.CommandType.FREE_VASSAL:
			return _cmd_free_vassal(cmd)
		IDs.CommandType.CANCEL_OPEN_BORDERS:
			return _cmd_cancel_open_borders(cmd)
		IDs.CommandType.GP_ACTION:
			return _cmd_gp_action(cmd)
		IDs.CommandType.CAST_VOTE:
			return _cmd_cast_vote(cmd)
		IDs.CommandType.RESOLVE_EVENT:
			return _cmd_resolve_event(cmd)
		IDs.CommandType.PROPOSE_PERMANENT_ALLIANCE:
			return _cmd_propose_permanent_alliance(cmd)
	return false

# ── Remote-multiplayer client seam ────────────────────────────────────────────

# Install (or clear, with null) the handler a NetClient uses to ship the player's
# post-move snapshot to the server at end-of-turn. Setting a non-null handler
# marks this facade as a remote client. Pure presentation/transport wiring — the
# sim never sees it; it is not serialized.
func set_remote_submit_handler(cb) -> void:
	_remote_submit_cb = cb
	if cb == null:
		_remote_waiting = false

func is_remote_client() -> bool:
	return _remote_submit_cb != null

# Park / unpark the local turn. While waiting, the End Turn button reads as
# "Waiting…" and another end-turn cannot be submitted. The NetClient clears this
# when the server pushes the next state this player owns.
func set_remote_waiting(flag: bool) -> void:
	_remote_waiting = flag
	_dirty.set_dirty(IDs.DirtyRegion.HUD_GROUPS)

func is_remote_waiting() -> bool:
	return _remote_waiting

# True for any command that ends the turn — the direct END_TURN command or the
# END_TURN / FORCE_END_TURN control routed through DO_CONTROL (the hotkey path).
func _is_end_turn_command(ctype: int, cmd: Dictionary) -> bool:
	if ctype == IDs.CommandType.END_TURN:
		return true
	if ctype == IDs.CommandType.DO_CONTROL:
		var ct: int = int(cmd.get("ctrl_type", -1))
		return ct == IDs.ControlType.END_TURN or ct == IDs.ControlType.FORCE_END_TURN
	return false

# Hand the current snapshot to the server and park the turn. Returns the
# handler's result (false if no handler is installed — should not happen, since
# the apply_command guard checks first).
func _remote_submit() -> bool:
	if _remote_submit_cb == null:
		return false
	_remote_waiting = true
	_dirty.set_dirty(IDs.DirtyRegion.HUD_GROUPS)
	return bool(_remote_submit_cb.call_func())

# ── Command handlers ──────────────────────────────────────────────────────────

func _cmd_end_turn(player_id: int) -> bool:
	var player: Player = _gs.get_player(player_id)
	if player == null:
		return false

	# A human may not end their turn while a random-event choice is unanswered (§9):
	# the decision is mandatory and is surfaced by the event-choice popup at turn
	# start. (AI choices auto-resolve inside the event step, so they never park one.)
	if not player.is_ai and not get_pending_event(player_id).empty():
		_add_notification("You must resolve the pending event first.", "major")
		return false

	# Advance all exploring scouts for this player before the turn pipeline runs.
	_run_explore_missions(player_id)

	TurnEngine.player_step(_gs, player_id, _hooks)
	_drain_flips()
	_drain_era_advances()
	_drain_tech_completions()
	_drain_great_people()
	_drain_productions()
	_drain_growth_events()
	_drain_improvement_completions()
	_drain_events()
	_drain_quest_events()

	# Trigger world step when the last player ends their turn (next wraps to index 0)
	var next_idx: int = _get_next_player_index(player_id)
	if next_idx == 0 or next_idx < 0:
		TurnEngine.world_step(_gs, _hooks)
		_drain_wild_events()
		_drain_first_contacts()
		_drain_assembly_events()
		_drain_deal_events()
		_drain_great_people()
		_add_notification("Turn " + str(_gs.turn_number) + " begins.", "info")
		emit_signal("turn_advanced", _gs.turn_number)
		if _gs.winning_alliance_id >= 0:
			emit_signal("game_won", _gs.winning_alliance_id)

	# Advance to next active player
	if not _gs.players.empty() and next_idx >= 0 and next_idx < _gs.players.size():
		_gs.current_player_id = _gs.players[next_idx].id
		# Resume any standing go-to orders before the turn opens, so multi-turn
		# journeys advance automatically (their movement was refreshed when this
		# player last ended a turn).
		_resume_goto(_gs.current_player_id)
		emit_signal("player_turn_started", _gs.current_player_id)
		# Raise the assembly ballot for a human who still owes a vote (§7.2).
		_maybe_raise_vote_popup(_gs.current_player_id)

	_dirty.mark_all()
	return true

func _cmd_move_stack(cmd: Dictionary) -> bool:
	var player_id: int = int(cmd["player_id"])
	var fx: int = int(cmd["from_x"]); var fy: int = int(cmd["from_y"])
	var tx: int = int(cmd["to_x"]);   var ty: int = int(cmd["to_y"])

	var moving_units: Array = _stack_movers(fx, fy, player_id, cmd.get("unit_ids", []))
	if moving_units.empty():
		return false

	var lead: Unit = moving_units[0]
	var path: Array = Pathfinding.find_path(
		_gs.map, fx, fy, tx, ty, lead, _db, _gs.units, player_id, _gs)

	if path.empty() and not (fx == tx and fy == ty):
		return false

	# Spy infiltration (§7.1): an all-spy stack moving onto a city tile (own or foreign)
	# relocates peacefully — it bypasses the combatant requirement below and never
	# resolves combat / captures the city in the step loop, even into a garrisoned or
	# at-war city. Spies cannot be attacked, so this is a one-way, non-violent entry.
	var infiltrating: bool = _is_spy_infiltration(moving_units, tx, ty)

	# Attacks must be led by a combatant. The destination tile is hostile when it
	# holds an enemy unit or a city we are at war with (pathfinding only routes onto
	# an enemy tile as the final, attacked tile). If so:
	#   • refuse the order outright when NO mover can attack (a lone worker/settler/
	#     spy/… — base_strength 0 — would otherwise walk up and waste its turn on a
	#     strength-0 "assault"); this is what makes a right-click with only a civilian
	#     selected a no-op (can_stack_move mirrors this gate so the UI and rules agree);
	#   • otherwise make sure a combat-capable mover leads, so a civilian at the head
	#     of a mixed stack never fights the battle in place of an escorting warrior (§5.3).
	if not infiltrating and (_enemy_settlement_at(tx, ty, player_id) != null \
			or Stack.get_defender(_gs.units, tx, ty, player_id, _gs) != null):
		var attacker: Unit = null
		for mu in moving_units:
			if mu.can_attack(_db):
				attacker = mu
				break
		if attacker == null:
			return false
		lead = attacker

	# Move one step at a time, consuming each unit's movement allowance (which is
	# set per unit class from data/units.json). The stack stops once its slowest
	# member is out of points; a unit with any points left may always enter one
	# more tile, so movement is bounded but never zero.
	for step in path:
		var min_left: int = lead.movement_left
		for u in moving_units:
			if u.movement_left < min_left:
				min_left = u.movement_left
		if min_left <= 0:
			break

		var sx: int = int(step[0]); var sy: int = int(step[1])

		# If the next tile holds an enemy, attack INTO it rather than moving on
		# first. Combat is resolved here; the attacker only advances onto the
		# tile if it wins (handled in _apply_combat_result). Attacking ends the
		# stack's movement for the turn. Spy infiltration skips combat/capture
		# entirely — the spy just walks onto the (possibly garrisoned/enemy) tile.
		var enemy_city: Settlement = null if infiltrating else _enemy_settlement_at(sx, sy, player_id)
		var enemy: Unit = null if infiltrating else Stack.get_defender(
			_gs.units, sx, sy, player_id, _gs)
		if enemy != null:
			# A defender on a city tile must be beaten before the city can be
			# assaulted, and killing it does NOT walk the attacker into the city
			# (the city is taken by the assault below, not by clearing defenders).
			var result: Dictionary = Combat.resolve(lead, enemy, _gs, _gs.rng)
			_apply_combat_result(lead, enemy, result, enemy_city == null)
			emit_signal("combat_resolved", result)
			_add_combat_notification(lead, enemy, result)
			for u in moving_units:
				u.movement_left = 0
				u.has_moved = true
				u.is_fortified = false
				u.is_sleep_until_healed = false
				u.is_fortify_until_healed = false
			lead.has_attacked = true
			break

		# An undefended enemy city tile falls immediately (§4.8): with no defender
		# left, a single attack captures it (kept, in revolt) or razes it — the
		# barbarian/wild and size-1 auto-raze rules in _city_falls still decide which.
		# The attacking stack always advances onto the tile (a kept city becomes ours;
		# a razed tile is now empty land). _city_falls emits the capture/raze
		# notification + signal, so the assault is never silent.
		if enemy_city != null:
			_city_falls(enemy_city, player_id)
			lead.has_attacked = true
			for u in moving_units:
				u.movement_left = 0
				u.has_moved = true
				u.x = sx; u.y = sy
				u.stationary_turns = 0
				u.entrenchment = 0
			break

		var step_cost: int = Pathfinding._move_cost(
			_gs.map.get_tile(sx, sy), _db,
			_db.get_unit(lead.unit_type_id).get("domain", "land"))

		for u in moving_units:
			u.movement_left = max(0, u.movement_left - step_cost)
			u.x = sx; u.y = sy
			u.has_moved = true
			u.stationary_turns = 0
			u.entrenchment = 0
			# Issue 5: moving cancels Fortify and any heal-stance (unit is now active).
			u.is_fortified = false
			u.is_sleep_until_healed = false
			u.is_fortify_until_healed = false
			# A worker that leaves its tile abandons any in-progress improvement
			# build or feature chop, so neither completes on the wrong tile.
			u.building_improvement = ""
			u.clearing_feature = ""
			u.build_turns_left = 0
			# Carried units ride along with their transport (§5.2).
			for cid in u.cargo:
				var carried: Unit = _gs.get_unit(cid)
				if carried != null:
					carried.x = sx; carried.y = sy

		# Exploration: the first unit to enter a goody hut / discovery site claims
		# its reward, then the site is consumed (§9). A "unit" reward spawns a free
		# unit for the discoverer (Events appends it to gs.units); surface it with the
		# usual unit_created so presentation paints it.
		var entered: Tile = _gs.map.get_tile(sx, sy)
		if entered != null and entered.has_discovery:
			entered.has_discovery = false
			var reward: Dictionary = Events.exploration_reward(lead, _gs, _gs.rng)
			if reward.get("type", "") == "unit" and int(reward.get("unit_id", -1)) >= 0:
				emit_signal("unit_created", int(reward["unit_id"]))
			# An ambush reward may have spawned wild raiders (§24); surface each so
			# presentation paints them like any other new unit.
			for wid in reward.get("spawned_unit_ids", []):
				emit_signal("unit_created", int(wid))
			_add_notification("Discovery: " + str(reward.get("type", "")), "major")
			emit_signal("event_emitted", reward)
			emit_signal("goody_received", reward)

		# Zone of control: entering a tile adjacent to a hostile unit ends the
		# stack's movement for the turn (§5.2).
		if _adjacent_hostile(sx, sy, player_id):
			for u in moving_units:
				u.movement_left = 0
			break

	# Persist (or clear) a go-to goal so a move that could not finish this turn keeps
	# travelling toward its target on later turns (§3.3 go-to mission). The goal is
	# dropped on arrival, and dropped after combat so a go-to never auto-re-attacks.
	for u in moving_units:
		if u.x == tx and u.y == ty:
			u.goto_x = -1; u.goto_y = -1
		elif lead.has_attacked:
			u.goto_x = -1; u.goto_y = -1
		else:
			u.goto_x = tx; u.goto_y = ty

	_dirty.set_dirty(IDs.DirtyRegion.WORLD)
	_dirty.set_dirty(IDs.DirtyRegion.HUD_GROUPS)
	return true

# Resume every go-to order for `player_id`: each unit still carrying a destination
# travels toward it with this turn's movement. Called at the start of the player's
# turn (movement already refreshed), so a multi-turn journey advances one turn's
# worth automatically. An order that can no longer be pathed is abandoned.
func _resume_goto(player_id: int) -> void:
	# Snapshot ids first — a resumed move may remove a unit (combat) or others.
	var ids: Array = []
	for u in _gs.units:
		if u.owner_player_id == player_id and u.goto_x >= 0:
			ids.append(u.id)
	for uid in ids:
		var u: Unit = _gs.get_unit(uid)
		if u == null or u.goto_x < 0:
			continue
		if u.x == u.goto_x and u.y == u.goto_y:
			u.goto_x = -1; u.goto_y = -1
			continue
		if u.movement_left <= 0:
			continue
		var mc: Dictionary = {
			"type": IDs.CommandType.MOVE_STACK,
			"player_id": player_id,
			"from_x": u.x, "from_y": u.y,
			"to_x": u.goto_x, "to_y": u.goto_y,
			"unit_ids": [u.id]
		}
		if not _cmd_move_stack(mc):
			u.goto_x = -1; u.goto_y = -1   # unreachable now: give up the order

# The units that actually move for a MOVE_STACK at (fx, fy): owned, on the tile,
# and not riding a transport. When unit_ids is non-empty the result is filtered
# to that subset, so a single member can be peeled off a larger stack; the order
# of all_here is preserved so the lead (and thus the path) stays stable.
func _stack_movers(fx: int, fy: int, player_id: int, unit_ids) -> Array:
	var wanted: Array = unit_ids if unit_ids != null else []
	var out: Array = []
	for mu in Stack.at(_gs.units, fx, fy, player_id):
		if mu.transported_by >= 0:
			continue
		if not wanted.empty() and not (mu.id in wanted):
			continue
		out.append(mu)
	return out

# ── City conquest (§4.8) ──────────────────────────────────────────────────────

# An enemy settlement on a tile the attacker is hostile to: a barbarian/wild city
# (owner -2) or another player's city the attacker is at war with. null otherwise
# — own cities, and foreign cities at peace, are not assaulted.
func _enemy_settlement_at(x: int, y: int, attacker_pid: int) -> Settlement:
	var s: Settlement = _gs.get_settlement_at(x, y)
	if s == null or s.owner_player_id == attacker_pid:
		return null
	if s.owner_player_id == -2 or _gs.are_at_war(attacker_pid, s.owner_player_id):
		return s
	return null

# A fallen city. Barbarians always raze; a size-1 city that was never larger is
# auto-razed; otherwise the captor keeps it (in revolt). Called the moment an
# undefended enemy city is attacked (§4.8) — there is no siege-HP wear-down.
func _city_falls(city: Settlement, captor_pid: int) -> String:
	if captor_pid == -2 or (city.population <= 1 and city.peak_population <= 1):
		_raze_city(city, captor_pid)
		return "razed"
	_capture_city(city, captor_pid)
	return "captured"

# Transfer a fallen city to its captor. It revolts for revolt_base_turns + half
# its size (producing nothing meanwhile, §4.8); its HP is restored, its queue and
# specialists are cleared, and the loser's Palace is stripped so they re-seed a
# new capital next turn (§6.1).
func _capture_city(city: Settlement, captor_pid: int) -> void:
	city.owner_player_id = captor_pid
	city.structures.erase("palace")
	city.production_queue = []
	city.production_store = 0
	city.specialists = {}
	city.worked_tiles = []
	city.locked_tiles = []
	city.revolt_turns = _db.get_constant("revolt_base_turns", 3) + city.population / 2
	city.health = TurnEngine.city_max_health(city, _db)
	city.in_disorder = true
	_add_notification(city.name + " captured!", "major")
	emit_signal("city_conquered", city.id, captor_pid)
	_dirty.set_dirty(IDs.DirtyRegion.WORLD)
	_dirty.set_dirty(IDs.DirtyRegion.DATA_PANES)
	_dirty.set_dirty(IDs.DirtyRegion.HUD_GROUPS)

# Destroy a city entirely (conquest raze, auto-raze, or a voluntary disband).
func _raze_city(city: Settlement, by_pid: int) -> void:
	var sid: int = city.id
	# Diplomatic memory (§7): the former owner long remembers who razed their city
	# (skip self-disband and barbarian razes, which have no player aggressor).
	var former_owner: int = city.owner_player_id
	if by_pid >= 0 and by_pid != former_owner:
		Diplomacy.record(_gs, _db, former_owner, by_pid, "razed_city")
	_gs.settlements.erase(city)
	if _selection != null and _selection.head_city() == sid:
		_selection.clear()
	_add_notification(city.name + " was razed.", "major")
	emit_signal("city_razed", sid, by_pid)
	_dirty.set_dirty(IDs.DirtyRegion.WORLD)
	_dirty.set_dirty(IDs.DirtyRegion.DATA_PANES)
	_dirty.set_dirty(IDs.DirtyRegion.HUD_GROUPS)

# Voluntarily disband (raze) one of the player's own cities at any time (§4.8).
# The capital (identified by holding the Palace structure) cannot be disbanded.
func _cmd_disband_city(cmd: Dictionary) -> bool:
	var s: Settlement = _gs.get_settlement(int(cmd.get("settlement_id", -1)))
	var pid: int = int(cmd["player_id"])
	if s == null or s.owner_player_id != pid:
		return false
	if s.has_structure("palace"):
		return false
	_raze_city(s, pid)
	return true

func _cmd_found_settlement(cmd: Dictionary) -> bool:
	var player_id: int = int(cmd["player_id"])
	var unit_id: int = int(cmd["unit_id"])
	var sname: String = str(cmd.get("name", ""))

	var u: Unit = _gs.get_unit(unit_id)
	if u == null or u.owner_player_id != player_id:
		return false
	# All founding legality (settler flag, foundable land, min distance) lives in
	# the shared predicate so the command and the UI never diverge.
	if not can_found_settlement_at(unit_id):
		return false

	# A player's first city is their capital (the earliest-founded settlement;
	# see TurnEngine._find_capital). Decide this before appending the new one.
	var is_first_city: bool = true
	for existing in _gs.settlements:
		if existing.owner_player_id == player_id:
			is_first_city = false
			break

	# Found the settlement
	var s := Settlement.new()
	s.id = _gs.next_settlement_id()
	# Determine the city name: explicit override > next unused historical name > fallback.
	# A name is "in use" if it was assigned before (used_city_names) OR currently
	# names one of this player's settlements — so a rename/capture frees/reserves
	# names correctly and never produces a duplicate live name.
	if sname == "":
		var player: Player = _gs.get_player(player_id)
		if player != null and player.society_id != "":
			var taken := {}
			for n in player.used_city_names:
				taken[n] = true
			for existing in _gs.settlements:
				if existing.owner_player_id == player_id:
					taken[existing.name] = true
			var cnames: Array = _db.get_city_names(player.society_id)
			for cname in cnames:
				if not taken.has(cname):
					sname = cname
					player.used_city_names.append(cname)
					break
	s.name = sname if sname != "" else "City " + str(s.id)
	s.owner_player_id = player_id
	s.x = u.x; s.y = u.y
	s.population = 1
	s.peak_population = 1
	# Seed the capital with the Palace by default. Data-driven: only added when
	# the structures table actually defines a "palace" entry.
	if is_first_city and not _db.get_structure("palace").empty():
		s.structures.append("palace")
	_gs.settlements.append(s)

	# Initial cultural claim
	Influence.found_claim(_gs.map, u.x, u.y, player_id, 2, 20, _db)

	# Remove the settler unit
	Stack.remove_unit(_gs.units, unit_id)

	_add_notification(s.name + " founded.", "major")
	emit_signal("settlement_founded", s.id)
	_dirty.set_dirty(IDs.DirtyRegion.WORLD)
	_dirty.set_dirty(IDs.DirtyRegion.DATA_PANES)
	# The founding settler is gone; refresh the selection/action panel.
	_dirty.set_dirty(IDs.DirtyRegion.HUD_GROUPS)
	return true

# The command carries the three adjustable rates (research/culture/intel);
# finance (economy) is the derived remainder 100 − (r + c + i), so the four
# Player fields still always sum to 100 and the save format is unchanged.
func _cmd_set_sliders(cmd: Dictionary) -> bool:
	var p: Player = _gs.get_player(int(cmd["player_id"]))
	if p == null:
		return false
	var r: int = int(cmd.get("research", 0))
	var c: int = int(cmd.get("culture", 0))
	var i: int = int(cmd.get("intel", 0))
	if r < 0 or c < 0 or i < 0:
		return false
	if r + c + i > 100:
		return false
	var f: int = 100 - (r + c + i)
	# Governing policies constrain the sliders (§6.2): an allowed increment and a
	# minimum research share.
	var increment: int = 0
	var min_research: int = 0
	for cat in p.policies:
		var pol: Dictionary = _db.policies.get("policies", {}).get(p.policies[cat], {})
		increment = max(increment, int(pol.get("slider_increment", 0)))
		min_research = max(min_research, int(pol.get("slider_min_research", 0)))
	if increment > 0 and (r % increment != 0 \
			or c % increment != 0 or i % increment != 0):
		return false
	if r < min_research:
		return false
	p.slider_finance = f; p.slider_research = r
	p.slider_culture = c; p.slider_intel = i
	_dirty.set_dirty(IDs.DirtyRegion.HUD_GROUPS)
	return true

func _cmd_set_production(cmd: Dictionary) -> bool:
	var s: Settlement = _gs.get_settlement(int(cmd["settlement_id"]))
	if s == null or s.owner_player_id != int(cmd["player_id"]):
		return false
	var incoming: Array = cmd.get("queue", []).duplicate(true)
	# Stamp each item with the turn it was queued (§15.2 NEW_HURRY_MODIFIER:
	# whipping an item queued this turn costs extra). An item already in the
	# old queue keeps its original stamp — matched by type+id, each old entry
	# consumed at most once so duplicates pair off in order.
	var used: Dictionary = {}
	for item in incoming:
		var stamp: int = _gs.turn_number
		for j in range(s.production_queue.size()):
			if used.has(j):
				continue
			var old: Dictionary = s.production_queue[j]
			if str(old.get("type", "")) == str(item.get("type", "")) \
					and str(old.get("id", "")) == str(item.get("id", "")):
				stamp = int(old.get("queued_turn", _gs.turn_number))
				used[j] = true
				break
		item["queued_turn"] = stamp
	s.production_queue = incoming
	s.produce_nothing = bool(cmd.get("produce_nothing", false))
	if not s.production_queue.empty():
		s.produce_nothing = false
	_dirty.set_dirty(IDs.DirtyRegion.DATA_PANES)
	return true

# Remove one item from a city's production queue by zero-based index (§11).
func _cmd_dequeue_production(cmd: Dictionary) -> bool:
	var s: Settlement = _gs.get_settlement(int(cmd.get("settlement_id", -1)))
	if s == null or s.owner_player_id != int(cmd["player_id"]):
		return false
	var idx: int = int(cmd.get("index", -1))
	if idx < 0 or idx >= s.production_queue.size():
		return false
	s.production_queue.remove(idx)
	_dirty.set_dirty(IDs.DirtyRegion.DATA_PANES)
	return true

func _cmd_move_production_item(cmd: Dictionary) -> bool:
	var s: Settlement = _gs.get_settlement(int(cmd.get("settlement_id", -1)))
	if s == null or s.owner_player_id != int(cmd["player_id"]):
		return false
	var from_idx: int = int(cmd.get("from_index", -1))
	var to_idx: int = int(cmd.get("to_index", -1))
	if from_idx < 0 or from_idx >= s.production_queue.size():
		return false
	if to_idx < 0 or to_idx >= s.production_queue.size():
		return false
	if from_idx == to_idx:
		return true
	var item = s.production_queue[from_idx]
	s.production_queue.remove(from_idx)
	s.production_queue.insert(to_idx, item)
	_dirty.set_dirty(IDs.DirtyRegion.DATA_PANES)
	return true

func _cmd_set_research(cmd: Dictionary) -> bool:
	var p: Player = _gs.get_player(int(cmd["player_id"]))
	if p == null:
		return false
	var tech_id: String = str(cmd.get("tech_id", ""))
	if not Research.can_research(tech_id, p, _db):
		return false
	p.current_research_id = tech_id
	_dirty.set_dirty(IDs.DirtyRegion.HUD_GROUPS)
	return true

func _cmd_set_policy(cmd: Dictionary) -> bool:
	var p: Player = _gs.get_player(int(cmd["player_id"]))
	if p == null:
		return false
	var cat: String = str(cmd.get("category", ""))
	var pol_id: String = str(cmd.get("policy_id", ""))
	var pol: Dictionary = _db.policies.get("policies", {}).get(pol_id, {})
	if pol.empty():
		return false
	var tech_req = pol.get("tech_required", null)
	if tech_req != null and tech_req != "" and not p.has_tech(tech_req):
		return false
	var prev: String = str(p.policies.get(cat, ""))
	if prev == pol_id:
		return false  # no change
	# Anarchy on a real switch only: replacing an established civic costs the
	# policy's transition turns, but the first government chosen in a category (from
	# none) is free, as is any switch for a Spiritual leader (§8).
	var transition: int = int(pol.get("transition_turns", 0))
	if transition > 0 and prev != "" and not ("spiritual" in p.traits):
		p.transition_turns = transition
	p.policies[cat] = pol_id
	_add_notification(p.name + " adopted " + str(pol.get("name", pol_id)) + ".", "major")
	_dirty.set_dirty(IDs.DirtyRegion.FULL_SCREENS)
	_dirty.set_dirty(IDs.DirtyRegion.HUD_GROUPS)
	return true

# Adopt or switch the player's empire-wide state religion (§8). "" means "no state
# religion" (always a legal choice). A non-empty religion must be a founded belief
# that is present in at least one of the player's settlements. Switching away from
# an existing state religion triggers anarchy (no commerce while it lasts) — but the
# first adoption (from none) is free, as is any switch for a Spiritual leader.
func _cmd_set_state_religion(cmd: Dictionary) -> bool:
	var p: Player = _gs.get_player(int(cmd["player_id"]))
	if p == null:
		return false
	var belief_id: String = str(cmd.get("belief_id", ""))
	if belief_id == p.state_religion:
		return false  # no change
	if belief_id != "":
		if not _gs.founded_beliefs.has(belief_id):
			return false
		var present: bool = false
		for s in _gs.settlements:
			if s.owner_player_id == p.id and s.belief_id == belief_id:
				present = true
				break
		if not present:
			return false
	# Anarchy on a real switch (not the first adoption), unless the leader is Spiritual.
	if p.state_religion != "" and not ("spiritual" in p.traits):
		p.transition_turns = _db.get_constant("state_religion_anarchy_turns", 1)
	p.state_religion = belief_id
	if belief_id == "":
		_add_notification(p.name + " abandoned their state religion.", "major")
	else:
		var belief_name: String = str(_db.beliefs.get(belief_id, {}).get("name", belief_id))
		_add_notification(p.name + " declared " + belief_name + " as state religion.", "major")
	_dirty.set_dirty(IDs.DirtyRegion.FULL_SCREENS)
	_dirty.set_dirty(IDs.DirtyRegion.HUD_GROUPS)
	return true

func _cmd_declare_war(cmd: Dictionary) -> bool:
	var p: Player = _gs.get_player(int(cmd["player_id"]))
	if p == null:
		return false
	var target_aid: int = int(cmd["target_alliance_id"])
	var alliance: Alliance = _gs.get_player_alliance(p.id)
	if alliance == null or alliance.id == target_aid:
		return false
	if not alliance.at_war_with in [target_aid]:
		alliance.at_war_with.append(target_aid)
	# Ensure contact
	if not alliance.has_contact_with(target_aid):
		alliance.contacts.append(target_aid)
	# Diplomatic memory (§7): every member of the attacked alliance remembers this
	# declaration against the aggressor, souring their attitude for a long time.
	var target: Alliance = _gs.get_alliance(target_aid)
	if target != null:
		Diplomacy.record_alliance(_gs, _db, target.member_player_ids, [p.id], "declared_war")
		# Open borders (§7): war overrides every standing open-borders agreement
		# between the two sides — at war you invade regardless, so the agreement is
		# torn up. Purge each cross-alliance member pair.
		for my_pid in alliance.member_player_ids:
			for their_pid in target.member_player_ids:
				_gs.remove_open_borders(int(my_pid), int(their_pid))
	_add_notification(p.name + " declared war on " + _alliance_label(target_aid) + "!", "major")
	return true

func _cmd_make_peace(cmd: Dictionary) -> bool:
	var p: Player = _gs.get_player(int(cmd["player_id"]))
	if p == null:
		return false
	var target_aid: int = int(cmd["target_alliance_id"])
	var alliance: Alliance = _gs.get_player_alliance(p.id)
	if alliance == null:
		return false
	alliance.at_war_with.erase(target_aid)
	# Diplomatic memory (§7): a peace overture is remembered warmly by the other side.
	var peaced: Alliance = _gs.get_alliance(target_aid)
	if peaced != null:
		Diplomacy.record_alliance(_gs, _db, peaced.member_player_ids, [p.id], "made_peace")
	_add_notification(p.name + " made peace with " + _alliance_label(target_aid) + ".", "major")
	return true

# Propose a permanent alliance with another alliance (§optional rule). Requires
# the permanent_alliances rule to be active and both sides to not already be at
# war or already permanently allied. The alliance is immediate and mutual — it is
# a voluntary act by the acting player, not a negotiation awaiting acceptance.
func _cmd_propose_permanent_alliance(cmd: Dictionary) -> bool:
	if not _gs.permanent_alliances:
		return false
	var p: Player = _gs.get_player(int(cmd["player_id"]))
	if p == null:
		return false
	var target_aid: int = int(cmd["target_alliance_id"])
	var mine: Alliance = _gs.get_player_alliance(p.id)
	var other: Alliance = _gs.get_alliance(target_aid)
	if mine == null or other == null or mine.id == target_aid:
		return false
	# Cannot form a permanent alliance while at war.
	if mine.is_at_war_with(target_aid):
		return false
	# Already permanently allied: no duplicate.
	if target_aid in mine.permanent_allies:
		return false
	# Record the alliance on both sides (mutual and permanent).
	if not (target_aid in mine.permanent_allies):
		mine.permanent_allies.append(target_aid)
	if not (mine.id in other.permanent_allies):
		other.permanent_allies.append(mine.id)
	# Ensure both sides have contact (declaring/forming alliance implies contact).
	if not mine.has_contact_with(target_aid):
		mine.contacts.append(target_aid)
	if not other.has_contact_with(mine.id):
		other.contacts.append(mine.id)
	_add_notification(p.name + " formed a permanent alliance with "
		+ _alliance_label(target_aid) + "!", "major")
	_dirty.set_dirty(IDs.DirtyRegion.FULL_SCREENS)
	return true

# Gold rush (hurry with treasury). The legacy method "population" delegates to
# the dedicated population-rush handler (§15.2) so older callers keep working.
func _cmd_rush_production(cmd: Dictionary) -> bool:
	if str(cmd.get("method", "treasury")) == "population":
		return _cmd_rush_population(cmd)
	var p: Player = _gs.get_player(int(cmd["player_id"]))
	if p == null:
		return false
	var s: Settlement = _gs.get_settlement(int(cmd["settlement_id"]))
	if s == null or s.owner_player_id != p.id:
		return false
	if s.production_queue.empty():
		return false
	var item: Dictionary = s.production_queue[0]
	var pace: Dictionary = _db.get_pace(_gs.pace_id)
	var cost: int = TurnEngine._item_cost(item, _db, p, pace)
	var remaining: int = max(0, cost - s.production_store)
	# Rushing with gold requires a civic that allows it (Universal Suffrage, §8).
	if not PolicyEffects.has_flag(p, _db, "can_rush_with_gold"):
		return false
	if p.treasury < remaining:
		return false
	p.treasury -= remaining
	s.production_store = cost
	s.rush_anger_turns = 5
	_dirty.set_dirty(IDs.DirtyRegion.DATA_PANES)
	return true

# Population rush ("whipping", §15.2): sacrifice citizens to finish the head
# production item. Gated on a civic carrying the `pop_rush` flag (Slavery, §8).
# Each sacrificed citizen buys `TurnEngine.rush_hammers_per_pop` hammers; the
# whip never takes more population than the remaining cost requires and must
# leave at least `rush_min_population` citizens. Every whip stacks one timed
# anger entry (−`rush_pop_anger` happiness for `rush_pop_anger_turns` turns) on
# the settlement, reusing the §9 timed-happiness channel.
func _cmd_rush_population(cmd: Dictionary) -> bool:
	var p: Player = _gs.get_player(int(cmd["player_id"]))
	if p == null:
		return false
	var s: Settlement = _gs.get_settlement(int(cmd["settlement_id"]))
	if s == null or s.owner_player_id != p.id:
		return false
	if not PolicyEffects.has_flag(p, _db, "pop_rush"):
		return false
	var pop_cost: int = TurnEngine.rush_pop_cost(_gs, s, p)
	if pop_cost <= 0:
		return false
	var min_pop: int = _db.get_constant("rush_min_population", 1)
	if s.population - pop_cost < min_pop:
		return false
	var per_pop: int = TurnEngine.rush_hammers_per_pop(
		_db, _db.get_pace(_gs.pace_id))
	s.population -= pop_cost
	s.production_store += pop_cost * per_pop
	# A structure with the `halve_slavery_anger` effect (Aztec Sacrificial
	# Altar) halves the whip-anger duration.
	var anger_turns: int = _db.get_constant("rush_pop_anger_turns", 10)
	for st in s.structures:
		if bool(_db.get_structure(st).get("effects", {}).get(
				"halve_slavery_anger", false)):
			anger_turns = anger_turns / 2
			break
	s.timed_happiness.append({
		"amount": -_db.get_constant("rush_pop_anger", 1),
		"turns_left": anger_turns
	})
	_dirty.set_dirty(IDs.DirtyRegion.DATA_PANES)
	return true

# Pure read for the city screen (§11): citizens a population rush of this
# settlement's head queue item would sacrifice right now (0 = nothing to rush).
func rush_population_cost(settlement_id: int) -> int:
	var s: Settlement = _gs.get_settlement(settlement_id)
	if s == null:
		return 0
	var p: Player = _gs.get_player(s.owner_player_id)
	if p == null:
		return 0
	return TurnEngine.rush_pop_cost(_gs, s, p)

# Shared legality predicate for a worker (unit_id) building improvement_id on its
# current tile. Used by _cmd_build_improvement (defence-in-depth on the command),
# the HUD worker-action panel, and the AI worker logic so all three agree on what
# is buildable. Validates ownership, build capability, tile landform, tech, river,
# feature, resource, and food requirements (§5). Pure read — no state mutation.
func can_build_improvement(player_id: int, unit_id: int, imp_id: String) -> bool:
	var p: Player = _gs.get_player(player_id)
	if p == null:
		return false
	var u: Unit = _gs.get_unit(unit_id)
	if u == null or u.owner_player_id != p.id:
		return false
	if not _db.get_unit(u.unit_type_id).get("can_build", false):
		return false
	var imp: Dictionary = _db.get_improvement(imp_id)
	if imp.empty():
		return false
	# Upgrade-only improvements (e.g. hamlet/village/town) are placed by the
	# cottage growth system, never by direct command.
	if bool(imp.get("upgrade_only", false)):
		return false
	# Validate the tile's landform against the improvement's allowed list.
	var tile: Tile = _gs.map.get_tile(u.x, u.y)
	if tile == null:
		return false
	# A settlement tile cannot be improved — reject even if the command is
	# submitted directly (defense-in-depth; the HUD also hides these buttons).
	if _gs.get_settlement_at(u.x, u.y) != null:
		return false
	var ter: Dictionary = _db.get_terrain(tile.terrain_id)
	var landform: String = str(ter.get("landform", "flat"))
	var allowed: Array = imp.get("allowed_landforms", [])
	if not allowed.empty() and not (landform in allowed):
		return false
	# Validate the tech requirement.
	var tech_req = imp.get("tech_required", null)
	if tech_req != null and str(tech_req) != "" and not p.has_tech(str(tech_req)):
		return false
	# Validate river requirement (watermill etc.).
	if bool(imp.get("requires_river", false)):
		var has_river: bool = tile.river_n or tile.river_w
		if not has_river:
			var s_tile: Tile = _gs.map.get_tile(u.x, u.y + 1)
			if s_tile != null and s_tile.river_n:
				has_river = true
		if not has_river:
			var e_tile: Tile = _gs.map.get_tile(u.x + 1, u.y)
			if e_tile != null and e_tile.river_w:
				has_river = true
		if not has_river:
			return false
	# Validate feature requirement (lumbermill needs forest, etc.).
	var req_feat: String = str(imp.get("requires_feature", ""))
	if req_feat != "" and tile.feature_id != req_feat:
		return false
	# Validate food requirement (§5): a cottage models a working settlement and
	# needs a tile that can feed it — reject on a zero base-food tile (desert,
	# snow). Data flag `requires_food` on the improvement; defaults off so other
	# improvements are unaffected. Uses the terrain's base food yield (integer).
	if bool(imp.get("requires_food", false)):
		if int(ter.get("base_output", {}).get("food", 0)) <= 0:
			return false
	# Validate resource requirement: a resource-bound improvement (pasture,
	# plantation, fishing boats, …) is only buildable on a tile carrying a
	# matching resource the player can already see (its reveal tech researched).
	if bool(imp.get("requires_resource", false)) \
			and not _tile_offers_resource_improvement(tile, imp_id, p):
		return false
	return true

func _cmd_build_improvement(cmd: Dictionary) -> bool:
	var u: Unit = _gs.get_unit(int(cmd["unit_id"]))
	var imp_id: String = str(cmd.get("improvement_id", ""))
	if not can_build_improvement(int(cmd["player_id"]), int(cmd["unit_id"]), imp_id):
		return false
	var p: Player = _gs.get_player(int(cmd["player_id"]))
	var imp: Dictionary = _db.get_improvement(imp_id)
	u.building_improvement = imp_id
	# Single-use builders (work boats, data flag `consumed_on_use`, §5) finish their
	# improvement INSTANTLY — the sea improvement is placed and the boat removed
	# within this same command, so the player never sees a multi-turn progress bar
	# or a leftover boat. Land workers fall through to the multi-turn path below.
	if "consumed_on_use" in _db.get_unit(u.unit_type_id).get("tags", []):
		var consumed: bool = TurnEngine.complete_worker_build(_gs, u)
		if consumed and _selection != null:
			_selection.selected_unit_ids.erase(u.id)
		# Surface the completion (notification + world repaint) immediately rather
		# than waiting for the end-of-turn drain, and repaint panes so the now-gone
		# boat clears from the selection panel.
		_drain_improvement_completions()
		_dirty.set_dirty(IDs.DirtyRegion.WORLD)
		_dirty.set_dirty(IDs.DirtyRegion.DATA_PANES)
		_dirty.set_dirty(IDs.DirtyRegion.HUD_GROUPS)
		return true
	# Serfdom speeds improvement construction (§8): fewer build turns.
	var bt: int = int(imp.get("build_turns", 5))
	var worker_speed: int = PolicyEffects.sum_int(p, _db, "worker_speed_bonus")
	if worker_speed > 0:
		bt = (bt * 100) / (100 + worker_speed)
		if bt < 1:
			bt = 1
	u.build_turns_left = bt
	u.has_moved = true
	u.movement_left = 0
	return true

# True when `tile` carries a resource that `imp_id` improves and that resource is
# visible to `player` (its reveal tech is researched). A resource is "visible"
# once the player holds the resource's tech_required; until then the tile shows no
# resource bonus and resource-bound improvements are not offered on it (§5, Jun 9
# bug report). Used by both _cmd_build_improvement and the worker action panel.
func _tile_offers_resource_improvement(tile: Tile, imp_id: String, player: Player) -> bool:
	if tile == null or tile.resource_id == "":
		return false
	var res: Dictionary = _db.get_resource(tile.resource_id)
	if str(res.get("improvement_required", "")) != imp_id:
		return false
	# A resource's reveal tech may be JSON null (e.g. fish/clam/crab/corn/rice/wheat
	# are visible from the start): the key is present with a null value, so a bare
	# get(..., "") returns null — str(null) is "Null", never a real tech. Coerce a
	# null/missing reveal tech to "" so those resources are always improvable.
	var reveal_val = res.get("tech_required", null)
	var reveal_tech: String = "" if reveal_val == null else str(reveal_val)
	return reveal_tech == "" or player.has_tech(reveal_tech)

# ── Trades (§7) ───────────────────────────────────────────────────────────────

func _cmd_propose_trade(cmd: Dictionary) -> bool:
	var p: Player = _gs.get_player(int(cmd["player_id"]))
	if p == null:
		return false
	var from_alliance: Alliance = _gs.get_player_alliance(p.id)
	var target_aid: int = int(cmd.get("target_alliance_id", -1))
	var to_alliance: Alliance = _gs.get_alliance(target_aid)
	if from_alliance == null or to_alliance == null or from_alliance.id == target_aid:
		return false
	# A standing assembly trade embargo (§7.2) bars commerce with the sanctioned
	# alliance, on either side of the deal.
	var embargo: int = int(_gs.assembly.get("standing", {}).get("trade_embargo", -1))
	if embargo >= 0 and (target_aid == embargo or from_alliance.id == embargo):
		_add_notification("Trade barred by assembly embargo.", "info")
		return false
	var open_borders: bool = bool(cmd.get("open_borders", false))
	# Open borders (§7) require the gating tech (Writing) on the proposing side, and
	# make no sense while at war (war already grants invasion rights).
	if open_borders:
		if not Diplomacy.can_open_borders(_gs, _db, p.id):
			_add_notification("You must research " + _open_borders_tech_name()
				+ " before proposing open borders.", "info")
			return false
		if from_alliance.is_at_war_with(target_aid):
			return false
	var duration: int = int(cmd.get("duration", -1))
	if duration <= 0:
		duration = _db.get_constant("trade_default_duration", 20)
	from_alliance.pending_trades.append({
		"id": _gs.next_trade_id(),
		"proposer_player_id": p.id,
		"from_alliance": from_alliance.id,
		"to_alliance": target_aid,
		"give": cmd.get("give", {}).duplicate(true),
		"receive": cmd.get("receive", {}).duplicate(true),
		"peace": bool(cmd.get("peace", false)),
		"open_borders": open_borders,
		"expires_turn": _gs.turn_number + duration
	})
	if not from_alliance.has_contact_with(target_aid):
		from_alliance.contacts.append(target_aid)
	_dirty.set_dirty(IDs.DirtyRegion.DATA_PANES)
	return true

func _cmd_accept_trade(cmd: Dictionary) -> bool:
	var p: Player = _gs.get_player(int(cmd["player_id"]))
	if p == null:
		return false
	var trade_id: int = int(cmd.get("trade_id", -1))
	for alliance in _gs.alliances:
		for i in range(alliance.pending_trades.size()):
			var t: Dictionary = alliance.pending_trades[i]
			if int(t.get("id", -1)) == trade_id and int(t.get("to_alliance", -1)) == p.alliance_id:
				_execute_trade(t, p)
				alliance.pending_trades.remove(i)
				_dirty.set_dirty(IDs.DirtyRegion.DATA_PANES)
				return true
	return false

func _cmd_reject_trade(cmd: Dictionary) -> bool:
	var p: Player = _gs.get_player(int(cmd["player_id"]))
	if p == null:
		return false
	var trade_id: int = int(cmd.get("trade_id", -1))
	var reason: String = str(cmd.get("reason", ""))
	for alliance in _gs.alliances:
		for i in range(alliance.pending_trades.size()):
			var t: Dictionary = alliance.pending_trades[i]
			if int(t.get("id", -1)) == trade_id and int(t.get("to_alliance", -1)) == p.alliance_id:
				# §7 denial reasons: a structured refusal is remembered per player
				# pair (read by the diplomacy screen) and queued for surfacing to
				# the proposer as a notification. A bare rejection ("") stays silent.
				var proposer_id: int = int(t.get("proposer_player_id", -1))
				if reason != "" and _gs.get_player(proposer_id) != null:
					if not _gs.deal_denials.has(proposer_id):
						_gs.deal_denials[proposer_id] = {}
					_gs.deal_denials[proposer_id][p.id] = \
						{"reason": reason, "turn": _gs.turn_number}
					_gs.pending_deal_events.append({"kind": "deal_rejected",
						"trade_id": trade_id, "reason": reason,
						"rejector_player_id": p.id,
						"proposer_player_id": proposer_id})
					_dirty.set_dirty(IDs.DirtyRegion.DATA_PANES)
				alliance.pending_trades.remove(i)
				return true
	return false

# Cancel an active recurring deal (§7). Either party to the deal may cancel, but
# only once the minimum duration has elapsed (start_turn + min_duration reached).
func _cmd_cancel_deal(cmd: Dictionary) -> bool:
	var p: Player = _gs.get_player(int(cmd["player_id"]))
	if p == null:
		return false
	var deal_id: int = int(cmd.get("deal_id", -1))
	for i in range(_gs.deals.size()):
		var d: Dictionary = _gs.deals[i]
		if int(d.get("id", -1)) != deal_id:
			continue
		# Only a party to the deal may cancel it.
		if p.alliance_id != int(d.get("a_alliance", -1)) and p.alliance_id != int(d.get("b_alliance", -1)):
			return false
		# Honour the minimum duration.
		if _gs.turn_number < int(d.get("start_turn", 0)) + int(d.get("min_duration", 0)):
			_add_notification("This deal cannot be cancelled yet.", "info")
			return false
		# Diplomatic memory (§7): the other party to the deal remembers it being torn up.
		var other_aid: int = int(d.get("b_alliance", -1)) if p.alliance_id == int(d.get("a_alliance", -1)) else int(d.get("a_alliance", -1))
		var other: Alliance = _gs.get_alliance(other_aid)
		var mine: Alliance = _gs.get_player_alliance(p.id)
		if other != null and mine != null:
			Diplomacy.record_alliance(_gs, _db, other.member_player_ids, mine.member_player_ids, "broke_deal")
		_gs.deals.remove(i)
		_gs.pending_deal_events.append({"kind": "deal_cancelled", "deal_id": deal_id})
		_dirty.set_dirty(IDs.DirtyRegion.DATA_PANES)
		return true
	return false

# Move gold/techs between the proposer and accepter and apply any peace clause.
func _execute_trade(t: Dictionary, accepter: Player) -> void:
	var proposer: Player = _gs.get_player(int(t.get("proposer_player_id", -1)))
	var give: Dictionary = t.get("give", {})       # proposer -> accepter
	var receive: Dictionary = t.get("receive", {}) # accepter -> proposer
	if proposer != null:
		var gg: int = int(give.get("gold", 0))
		var rg: int = int(receive.get("gold", 0))
		proposer.treasury -= gg; accepter.treasury += gg
		accepter.treasury -= rg; proposer.treasury += rg
		for tech in give.get("techs", []):
			if not accepter.has_tech(tech):
				accepter.technologies.append(tech)
		for tech in receive.get("techs", []):
			if not proposer.has_tech(tech):
				proposer.technologies.append(tech)
		var parts: Array = []
		if gg > 0: parts.append(str(gg) + " gold to " + accepter.name)
		if rg > 0: parts.append(str(rg) + " gold to " + proposer.name)
		var give_techs: Array = give.get("techs", [])
		var recv_techs: Array = receive.get("techs", [])
		if not give_techs.empty(): parts.append("tech to " + accepter.name)
		if not recv_techs.empty(): parts.append("tech to " + proposer.name)
		if not parts.empty():
			_add_notification(proposer.name + " and " + accepter.name + " traded: " + ", ".join(parts) + ".", "info")
			# Diplomatic memory (§7): a completed trade warms both sides; a tech hand-off
			# is remembered more fondly still.
			Diplomacy.record(_gs, _db, proposer.id, accepter.id, "fair_trade")
			Diplomacy.record(_gs, _db, accepter.id, proposer.id, "fair_trade")
			if not give_techs.empty() or not recv_techs.empty():
				Diplomacy.record(_gs, _db, proposer.id, accepter.id, "traded_tech")
				Diplomacy.record(_gs, _db, accepter.id, proposer.id, "traded_tech")
	if bool(t.get("peace", false)):
		var a_from: Alliance = _gs.get_alliance(int(t.get("from_alliance", -1)))
		var a_to: Alliance = _gs.get_alliance(int(t.get("to_alliance", -1)))
		if a_from != null and a_to != null:
			a_from.at_war_with.erase(a_to.id)
			a_to.at_war_with.erase(a_from.id)
			_add_notification(_alliance_label(a_from.id) + " and " + _alliance_label(a_to.id)
				+ " agreed to peace.", "major")
	# Open borders (§7): record a bilateral agreement between proposer and accepter.
	# Both sides must hold the gating tech (re-checked here so a tech lost between
	# proposal and acceptance — or an accepter who never had it — cannot slip through).
	if bool(t.get("open_borders", false)) and proposer != null:
		if Diplomacy.can_open_borders(_gs, _db, proposer.id) \
				and Diplomacy.can_open_borders(_gs, _db, accepter.id):
			_gs.add_open_borders(proposer.id, accepter.id)
			_add_notification(proposer.name + " and " + accepter.name
				+ " opened their borders.", "major")
	# Recurring items (gold-per-turn, resources) become a persistent Deal (§7),
	# delivered each world step until cancelled. One-off items above are already done.
	if _trade_has_recurring(give) or _trade_has_recurring(receive):
		_gs.deals.append({
			"id": _gs.next_trade_id(),
			"a_alliance": int(t.get("from_alliance", -1)),
			"b_alliance": int(t.get("to_alliance", -1)),
			"proposer_player_id": int(t.get("proposer_player_id", -1)),
			"accepter_player_id": accepter.id,
			"recurring": {
				"give": _recurring_items(give),
				"receive": _recurring_items(receive)
			},
			"start_turn": _gs.turn_number,
			"min_duration": _db.get_constant("deal_min_duration", 10)
		})

# The display name of the open-borders gating tech (for notifications).
func _open_borders_tech_name() -> String:
	var tech: String = Diplomacy.open_borders_tech(_db)
	var td: Dictionary = _db.get_technology(tech)
	return str(td.get("name", tech)) if not td.empty() else tech

# Whether a give/receive item bundle carries any recurring (per-turn) item.
func _trade_has_recurring(items: Dictionary) -> bool:
	return int(items.get("gold_per_turn", 0)) > 0 or not items.get("resources", []).empty()

# Extract just the recurring keys from a give/receive bundle (one-off keys dropped).
func _recurring_items(items: Dictionary) -> Dictionary:
	var out: Dictionary = {}
	var gpt: int = int(items.get("gold_per_turn", 0))
	if gpt > 0:
		out["gold_per_turn"] = gpt
	var res: Array = items.get("resources", [])
	if not res.empty():
		out["resources"] = res.duplicate()
	return out

# ── Subordination (§7) ────────────────────────────────────────────────────────

# The acting player's alliance becomes a tributary of the overlord alliance:
# their war ends, the subordinate joins the overlord's wars, and tribute is paid
# each world step.
func _cmd_set_subordination(cmd: Dictionary) -> bool:
	var p: Player = _gs.get_player(int(cmd["player_id"]))
	if p == null:
		return false
	var mine: Alliance = _gs.get_player_alliance(p.id)
	var overlord_id: int = int(cmd.get("overlord_alliance_id", -1))
	var overlord: Alliance = _gs.get_alliance(overlord_id)
	if mine == null or overlord == null or mine.id == overlord_id:
		return false
	mine.is_subordinate_to = overlord_id
	if not (mine.id in overlord.tributaries):
		overlord.tributaries.append(mine.id)
	mine.at_war_with.erase(overlord_id)
	overlord.at_war_with.erase(mine.id)
	for enemy_aid in overlord.at_war_with:
		if not (enemy_aid in mine.at_war_with):
			mine.at_war_with.append(enemy_aid)
	_add_notification(p.name + " became a tributary of " + _alliance_label(overlord_id) + ".", "major")
	_dirty.set_dirty(IDs.DirtyRegion.FULL_SCREENS)
	return true

# An overlord voluntarily releases one of its tributaries/vassals back to
# independence (§7, Phase 8 — the overlord's half of liberation; a vassal also
# breaks free on its own once strong enough, via Vassalage.world_tick). The acting
# player must belong to the overlord alliance, and the target must currently be its
# subordinate. Liberation is peaceful — it leaves both sides at peace.
func _cmd_free_vassal(cmd: Dictionary) -> bool:
	var p: Player = _gs.get_player(int(cmd["player_id"]))
	if p == null:
		return false
	var overlord: Alliance = _gs.get_player_alliance(p.id)
	var vassal: Alliance = _gs.get_alliance(int(cmd.get("vassal_alliance_id", -1)))
	if overlord == null or vassal == null:
		return false
	if vassal.is_subordinate_to != overlord.id:
		return false
	Vassalage.liberate(_gs, vassal)
	_add_notification(p.name + " released " + _alliance_label(vassal.id)
		+ " from vassalage.", "major")
	_dirty.set_dirty(IDs.DirtyRegion.FULL_SCREENS)
	return true

# Cancel a standing open-borders agreement (§7). Either party may revoke it; the
# other player's territory then blocks this player's units again. A no-op (false)
# when no such agreement exists between the two players.
func _cmd_cancel_open_borders(cmd: Dictionary) -> bool:
	var p: Player = _gs.get_player(int(cmd["player_id"]))
	if p == null:
		return false
	var other: Player = _gs.get_player(int(cmd.get("other_player_id", -1)))
	if other == null:
		return false
	if not _gs.remove_open_borders(p.id, other.id):
		return false
	_add_notification(p.name + " closed their borders to " + other.name + ".", "major")
	_dirty.set_dirty(IDs.DirtyRegion.FULL_SCREENS)
	return true

# ── Specialists (§6.5) ────────────────────────────────────────────────────────

func _cmd_assign_specialist(cmd: Dictionary) -> bool:
	var p: Player = _gs.get_player(int(cmd["player_id"]))
	if p == null:
		return false
	var s: Settlement = _gs.get_settlement(int(cmd.get("settlement_id", -1)))
	if s == null or s.owner_player_id != p.id:
		return false
	var stype: String = str(cmd.get("specialist_type", ""))
	var count: int = int(cmd.get("count", 0))
	if stype == "" or count < 0:
		return false
	# The type must be a known specialist (data/specialists.json).
	if _db.get_specialist(stype).empty():
		return false
	# Per-type slot ceiling (§14.5): default slots + per-structure slots, unless the
	# Caste System civic lifts the cap (slots = -1).
	var slots: int = Specialists.slots_for(_db, s, p, stype)
	if slots >= 0 and count > slots:
		return false
	# Total specialists may not exceed the settlement's population.
	var others: int = 0
	for k in s.specialists:
		if k != stype:
			others += int(s.specialists[k])
	if others + count > s.population:
		return false
	if count == 0:
		s.specialists.erase(stype)
	else:
		s.specialists[stype] = count
	_dirty.set_dirty(IDs.DirtyRegion.DATA_PANES)
	return true

# Lock or unlock a tile as worked by a city (§11 city screen). A locked tile is
# always worked (capacity permitting); unlocking removes the lock. After the
# change the player's worked tiles are recomputed immediately so the city screen
# reflects it at once (output stays turn-cached and refreshes next turn).
func _cmd_set_tile_worked(cmd: Dictionary) -> bool:
	var p: Player = _gs.get_player(int(cmd["player_id"]))
	if p == null:
		return false
	var s: Settlement = _gs.get_settlement(int(cmd.get("settlement_id", -1)))
	if s == null or s.owner_player_id != p.id:
		return false
	var tx: int = int(cmd.get("x", -999))
	var ty: int = int(cmd.get("y", -999))
	if not _gs.map.is_valid(tx, ty):
		return false
	# The tile must be within the city's worked radius, ownable by the player,
	# and workable at all (mountain peaks are unworkable, reference).
	var in_range: bool = false
	for tile in _gs.map.tiles_in_range(s.x, s.y, s.culture_ring):
		if tile.x == tx and tile.y == ty:
			if (tile.owner_player_id == p.id or tile.owner_player_id == -1) \
					and TileOutput.workable(tile, _db):
				in_range = true
			break
	if not in_range:
		return false
	var worked: bool = bool(cmd.get("worked", true))
	var idx: int = -1
	for i in range(s.locked_tiles.size()):
		if int(s.locked_tiles[i][0]) == tx and int(s.locked_tiles[i][1]) == ty:
			idx = i
			break
	if worked and idx < 0:
		s.locked_tiles.append([tx, ty])
	elif not worked and idx >= 0:
		s.locked_tiles.remove(idx)
	TurnEngine._auto_assign_workers(_gs, p)
	_dirty.set_dirty(IDs.DirtyRegion.DATA_PANES)
	return true

# Toggle a city's automatic citizen management (§11 city screen). When off, only
# the player's locked tiles are worked; when on, unlocked worker slots auto-fill.
func _cmd_set_citizen_automation(cmd: Dictionary) -> bool:
	var p: Player = _gs.get_player(int(cmd["player_id"]))
	if p == null:
		return false
	var s: Settlement = _gs.get_settlement(int(cmd.get("settlement_id", -1)))
	if s == null or s.owner_player_id != p.id:
		return false
	s.manage_citizens_auto = bool(cmd.get("auto", true))
	TurnEngine._auto_assign_workers(_gs, p)
	_dirty.set_dirty(IDs.DirtyRegion.DATA_PANES)
	return true

# ── Great Person actions (§14) ────────────────────────────────────────────────

# Direct a Great Person unit to perform one of its data-defined actions. Extra
# command keys (settlement_id, target_alliance_id, tech_id, org_id) are passed
# through as params; the GreatPeople module validates the action against the
# unit's own "actions" list.
func _cmd_gp_action(cmd: Dictionary) -> bool:
	var player_id: int = int(cmd["player_id"])
	var u: Unit = _gs.get_unit(int(cmd.get("unit_id", -1)))
	if u == null or u.owner_player_id != player_id:
		return false
	var action: String = str(cmd.get("action", ""))
	var params: Dictionary = {}
	for k in cmd:
		if k != "type" and k != "player_id" and k != "unit_id" and k != "action":
			params[k] = cmd[k]
	var p_gp: Player = _gs.get_player(player_id)
	var was_in_golden_age: bool = p_gp != null and GreatPeople.is_in_golden_age(p_gp)
	if not GreatPeople.perform_action(_gs, u, action, params):
		return false
	if p_gp != null:
		var udata_gp: Dictionary = _db.get_unit(u.unit_type_id)
		var gp_name: String = str(udata_gp.get("name", u.unit_type_id))
		match action:
			"start_golden_age":
				if GreatPeople.is_in_golden_age(p_gp) and not was_in_golden_age:
					_add_notification(p_gp.name + " has entered a Golden Age!", "major")
				else:
					_add_notification(gp_name + " contributed to the next Golden Age.", "info")
			"trade_mission":
				_add_notification(gp_name + " completed a trade mission.", "info")
			"found_religion":
				_add_notification(gp_name + " founded a new religion.", "major")
			"discover_technology":
				_add_notification(gp_name + " discovered a technology.", "major")
	_dirty.mark_all()
	return true

# ── Espionage (§7) ────────────────────────────────────────────────────────────

func _cmd_espionage_mission(cmd: Dictionary) -> bool:
	var p: Player = _gs.get_player(int(cmd["player_id"]))
	if p == null:
		return false
	var target_aid: int = int(cmd.get("target_alliance_id", -1))
	var target_alliance: Alliance = _gs.get_alliance(target_aid)
	if target_alliance == null or target_aid == p.alliance_id:
		return false
	# The mission must name a record in data/espionage_missions.json (§7.1).
	var mission: Dictionary = _db.get_espionage_mission(str(cmd.get("mission", "")))
	if mission.empty():
		return false
	# Alliance-scope screen mission: no fixed city, the effect picks its own victim.
	return _run_espionage_mission(p, target_alliance, mission, null) != MissionRun.REJECTED

# Spy-unit-on-tile espionage mission (§7.1): the spy `unit_id` must be an espionage
# unit standing on a foreign city tile with FULL movement. The mission strikes that
# specific city and, on success, consumes the spy's action for the turn.
func _cmd_spy_mission(cmd: Dictionary) -> bool:
	var p: Player = _gs.get_player(int(cmd["player_id"]))
	if p == null:
		return false
	var u: Unit = _gs.get_unit(int(cmd.get("unit_id", -1)))
	if u == null or u.owner_player_id != p.id:
		return false
	var city: Settlement = _spy_target_city(u, p)
	if city == null:
		return false
	var owner: Player = _gs.get_player(city.owner_player_id)
	var target_alliance: Alliance = _gs.get_alliance(owner.alliance_id) if owner != null else null
	if target_alliance == null:
		return false
	var mission: Dictionary = _db.get_espionage_mission(str(cmd.get("mission", "")))
	if mission.empty():
		return false
	var outcome: int = _run_espionage_mission(p, target_alliance, mission, city)
	if outcome == MissionRun.REJECTED:
		return false
	if outcome == MissionRun.INTERCEPTED:
		# A spy caught in the act is captured and destroyed (§7.1) — the EP is
		# already spent. The command still succeeded: the mission was attempted.
		Stack.remove_unit(_gs.units, u.id)
		if _selection != null:
			_selection.selected_unit_ids.erase(u.id)
		_add_notification("Your spy was captured in " + city.name + ".", "major")
		_dirty.set_dirty(IDs.DirtyRegion.WORLD)
		_dirty.set_dirty(IDs.DirtyRegion.HUD_GROUPS)
		return true
	u.movement_left = 0
	u.has_moved = true
	_dirty.set_dirty(IDs.DirtyRegion.HUD_GROUPS)
	return true

# Validate, pay for, roll interception against, and apply a mission. `target_city`
# (null for the alliance-scope screen path) fixes which city/owner the effect strikes.
# Returns EXECUTED or INTERCEPTED when the mission ran (the EP is spent either
# way — an intercepted tile spy is captured, see _cmd_spy_mission); REJECTED when
# the gate fails or the attacker cannot afford it (no EP spent).
func _run_espionage_mission(p: Player, target_alliance: Alliance,
		mission: Dictionary, target_city) -> int:
	# Passive intel records (§25.6) are standing threshold abilities, not
	# runnable operations — they cannot be executed from either mission path.
	if str(mission.get("kind", "active")) == "passive":
		return MissionRun.REJECTED
	# Reject a mission whose target gate does not hold (e.g. stealing a tech the
	# target cannot offer) before spending any points.
	if not _mission_target_valid(p, target_alliance, mission, target_city):
		return MissionRun.REJECTED
	var have: int = int(p.intel_points.get(target_alliance.id, 0))
	var cost: int = _mission_cost(p, target_alliance, have, mission)
	if have < cost:
		return MissionRun.REJECTED
	p.intel_points[target_alliance.id] = have - cost
	# detect_missions passive intel (§25.6): a victim holding the detect
	# threshold against the attacker learns who is behind the strike; otherwise
	# it stays anonymous.
	var detected: bool = _intel_detects(target_alliance, p.alliance_id)
	# A defender's espionage_defense structures plus the mission's own
	# interception_modifier raise the chance; interception spends the points but
	# fails the mission (§7, §15.5).
	var chance: int = _espionage_interception_chance(target_alliance,
		int(mission.get("interception_modifier", 0)), p.alliance_id)
	if _gs.rng.rand_bool_percent(chance):
		if detected:
			_add_notification("Espionage mission by " + p.name + " intercepted.", "info")
		else:
			_add_notification("Espionage mission intercepted.", "info")
		return MissionRun.INTERCEPTED
	_espionage_apply(p, target_alliance, mission, target_city)
	if detected:
		_add_notification(p.name + " ran the '" + str(mission.get("name", "")) \
			+ "' espionage mission against you.", "info")
	return MissionRun.EXECUTED

# Dispatch a mission's `effect` verb onto game state (§7.1). Each verb is a pure,
# deterministic application; magnitudes come from the mission record / constants.
# `target_city` (or null) fixes the victim city/owner for the spy-on-tile path; when
# null the effect selects its own deterministic victim (the alliance-screen path).
func _espionage_apply(thief: Player, target: Alliance, mission: Dictionary,
		target_city = null) -> void:
	match str(mission.get("effect", "")):
		"steal_tech":
			_espionage_steal_tech(thief, target, target_city)
		"sabotage":
			_espionage_sabotage(target, target_city)
		"destroy_building":
			_espionage_destroy_building(target, target_city)
		"destroy_project":
			_espionage_destroy_project(target, target_city)
		"destroy_improvement":
			_espionage_destroy_improvement(target, target_city)
		"steal_gold":
			_espionage_steal_gold(thief, target, int(mission.get("amount", 0)), target_city)
		"poison_water":
			_espionage_poison_water(target, target_city)
		"insert_culture":
			_espionage_insert_culture(thief, target, int(mission.get("amount", 0)), target_city)
		"incite_unhappiness":
			_espionage_incite_unhappiness(target, int(mission.get("amount", 1)),
				int(mission.get("duration", 1)), target_city)
		"incite_revolt":
			_espionage_incite_revolt(target, int(mission.get("duration", 1)), target_city)
		"switch_civic":
			_espionage_force_anarchy(target, int(mission.get("duration", 1)), false, target_city)
		"switch_religion":
			_espionage_force_anarchy(target, int(mission.get("duration", 1)), true, target_city)
		"counterespionage":
			_espionage_counterespionage(thief, target, int(mission.get("duration", 1)))

# True when `mission` can produce its effect right now — the per-verb target gate.
# When `target_city` is given (the spy-on-tile path) the gate is tested against that
# one city and its owner; otherwise it is tested across the whole target alliance.
func _mission_target_valid(attacker: Player, target: Alliance, mission: Dictionary,
		target_city = null) -> bool:
	# Resolve the candidate cities and owners the gate scans.
	var cities: Array = []
	var owners: Array = []
	if target_city != null:
		cities = [target_city]
		var o: Player = _gs.get_player(target_city.owner_player_id)
		if o != null:
			owners = [o]
	else:
		for s in _gs.settlements:
			if _settlement_in_alliance(s, target):
				cities.append(s)
		for pid in target.member_player_ids:
			var m: Player = _gs.get_player(pid)
			if m != null:
				owners.append(m)
	match str(mission.get("effect", "")):
		"steal_tech":
			# There must be a tech an owner knows that the attacker lacks.
			for victim in owners:
				for tech in victim.technologies:
					if not attacker.has_tech(tech):
						return true
			return false
		"sabotage":
			for s in cities:
				if s.production_store > 0:
					return true
			return false
		"destroy_building":
			# There must be a structure we can raze (the Palace is never targetable).
			for s in cities:
				for struct_id in s.structures:
					if struct_id != "palace":
						return true
			return false
		"destroy_project":
			for s in cities:
				if _settlement_building_project(s):
					return true
			return false
		"destroy_improvement":
			for s in cities:
				if _city_improved_tile(s) != null:
					return true
			return false
		"switch_religion":
			for victim in owners:
				if victim.state_religion != "":
					return true
			return false
		"steal_gold":
			for victim in owners:
				if victim.treasury > 0:
					return true
			return false
		"poison_water":
			for s in cities:
				if s.population >= 2:
					return true
			return false
		_:
			# insert_culture, incite_unhappiness/revolt, switch_civic, counterespionage
			# and any future gateless verb only need a target city to act on.
			return not cities.empty()

func _settlement_in_alliance(s: Settlement, target: Alliance) -> bool:
	var owner: Player = _gs.get_player(s.owner_player_id)
	return owner != null and owner.alliance_id == target.id

# The owner players a player-targeting mission may hit: just the target city's owner
# (spy-on-tile path) or every alliance member (alliance-screen path).
func _mission_owners(target: Alliance, target_city) -> Array:
	if target_city != null:
		var o: Player = _gs.get_player(target_city.owner_player_id)
		return [o] if o != null else []
	var owners: Array = []
	for pid in target.member_player_ids:
		var m: Player = _gs.get_player(pid)
		if m != null:
			owners.append(m)
	return owners

# The most populous settlement in `target` (lowest id on a tie), or null when the
# alliance holds none. The deterministic victim for the city-targeting missions.
func _largest_target_city(target: Alliance) -> Settlement:
	var biggest: Settlement = null
	for s in _gs.settlements:
		if not _settlement_in_alliance(s, target):
			continue
		if biggest == null or s.population > biggest.population \
				or (s.population == biggest.population and s.id < biggest.id):
			biggest = s
	return biggest

# True when `s` is currently building an endgame project (its queue head is a
# project) — the gate/target for destroy_project.
func _settlement_building_project(s: Settlement) -> bool:
	if s.production_queue.empty():
		return false
	return str(s.production_queue[0].get("type", "unit")) == "project"

# The first improved tile worked by a member of `target` (scanned in map order), or
# null — the deterministic victim/gate for destroy_improvement (alliance-screen path).
func _alliance_improved_tile(target: Alliance):
	for s in _gs.settlements:
		if not _settlement_in_alliance(s, target):
			continue
		var tile = _city_improved_tile(s)
		if tile != null:
			return tile
	return null

# The first improved tile worked by settlement `s` (in worked-tile order), or null —
# the per-city victim/gate for destroy_improvement (spy-on-tile path).
func _city_improved_tile(s: Settlement):
	for cell in s.worked_tiles:
		var tile = _gs.map.get_tile(int(cell[0]), int(cell[1]))
		if tile != null and tile.improvement_id != "":
			return tile
	return null

# True when the unit is an espionage (spy) unit — data-driven via the "espionage" tag
# in data/units.json, so any future spy-class unit is recognised without code change.
func _is_espionage_unit(u: Unit) -> bool:
	if u == null:
		return false
	return _db.get_unit(u.unit_type_id).get("tags", []).has("espionage")

# The foreign city a spy may act on, or null. The unit must be an espionage unit with
# FULL movement (§7.1: a spy spends a whole turn's movement on a mission) standing on
# a settlement tile owned by a DIFFERENT alliance. A spy on its own/allied city, with
# spent movement, or not on a city at all, returns null — so no actions are offered.
func _spy_target_city(u: Unit, p: Player):
	if not _is_espionage_unit(u):
		return null
	if u.movement_total <= 0 or u.movement_left < u.movement_total:
		return null
	for s in _gs.settlements:
		if s.x == u.x and s.y == u.y:
			var owner: Player = _gs.get_player(s.owner_player_id)
			if owner != null and owner.alliance_id != p.alliance_id:
				return s
			return null  # own/allied city offers no offensive missions
	return null

# True when `movers` are all espionage units and the destination (tx, ty) holds a city
# (any owner) — a peaceful spy infiltration rather than an attack or a normal move.
func _is_spy_infiltration(movers: Array, tx: int, ty: int) -> bool:
	if movers.empty() or _gs.get_settlement_at(tx, ty) == null:
		return false
	for u in movers:
		if not _is_espionage_unit(u):
			return false
	return true

# Public query: EP cost for the current player to run `mission_id` against
# target_alliance_id. Returns 0 when state is unavailable or the target is
# invalid, so callers can safely use the result to gate UI buttons. With the
# default mission ("steal_tech", cost_multiplier 100) this returns the base curve.
func get_espionage_mission_cost(target_alliance_id: int, mission_id: String = "steal_tech") -> int:
	if _gs == null:
		return 0
	var p: Player = _gs.get_player(_gs.current_player_id)
	if p == null:
		return 0
	var target: Alliance = _gs.get_alliance(target_alliance_id)
	if target == null:
		return 0
	var have: int = int(p.intel_points.get(target_alliance_id, 0))
	var mission: Dictionary = _db.get_espionage_mission(mission_id)
	if mission.empty():
		return _espionage_mission_cost(p, target, have)
	return _mission_cost(p, target, have, mission)

# Public query: interception percentage for `mission_id` against
# target_alliance_id (base defence plus the mission's interception_modifier).
func get_espionage_interception_chance(target_alliance_id: int, mission_id: String = "") -> int:
	if _gs == null:
		return 0
	var target: Alliance = _gs.get_alliance(target_alliance_id)
	if target == null:
		return 0
	var modifier: int = int(_db.get_espionage_mission(mission_id).get("interception_modifier", 0))
	return _espionage_interception_chance(target, modifier)

# Public query: the mission menu rows for the current player against a target —
# id, name, cost, interception chance, and whether each is currently available
# (its target gate holds) and affordable. Empty when state/target is invalid.
func espionage_mission_options(target_alliance_id: int) -> Array:
	var out: Array = []
	if _gs == null:
		return out
	var p: Player = _gs.get_player(_gs.current_player_id)
	var target: Alliance = _gs.get_alliance(target_alliance_id)
	if p == null or target == null:
		return out
	var have: int = int(p.intel_points.get(target_alliance_id, 0))
	for m in _db.get_espionage_missions():
		# Passive intel records (§25.6) are standing abilities shown by the
		# advisor's intel blocks, not runnable operations.
		if str(m.get("kind", "active")) == "passive":
			continue
		var cost: int = _mission_cost(p, target, have, m)
		out.append({
			"id": str(m.get("id", "")),
			"name": str(m.get("name", m.get("id", ""))),
			"cost": cost,
			"interception": _espionage_interception_chance(target,
				int(m.get("interception_modifier", 0))),
			"available": _mission_target_valid(p, target, m),
			"affordable": have >= cost,
		})
	return out

# Spy-on-tile mission rows for `unit_id` (§7.1): the catalogue filtered to the
# missions this spy can actually run from the foreign city it stands on — only those
# whose target gate holds AND that the attacker can afford (so the UI shows only valid
# and usable actions). Each row carries id, name, cost, and interception chance.
# Empty when the spy cannot act here (not a spy, lacking full movement, or not on a
# foreign city tile), which is the signal to show no spy actions at all.
func spy_mission_options(unit_id: int) -> Array:
	var out: Array = []
	if _gs == null:
		return out
	var u: Unit = _gs.get_unit(unit_id)
	if u == null:
		return out
	var p: Player = _gs.get_player(u.owner_player_id)
	if p == null:
		return out
	var city: Settlement = _spy_target_city(u, p)
	if city == null:
		return out
	var owner: Player = _gs.get_player(city.owner_player_id)
	var target: Alliance = _gs.get_alliance(owner.alliance_id) if owner != null else null
	if target == null:
		return out
	var have: int = int(p.intel_points.get(target.id, 0))
	for m in _db.get_espionage_missions():
		# Passive intel records (§25.6) never run from a tile spy either.
		if str(m.get("kind", "active")) == "passive":
			continue
		var cost: int = _mission_cost(p, target, have, m)
		# Only valid (gate holds) and usable (affordable) missions are listed.
		if have < cost or not _mission_target_valid(p, target, m, city):
			continue
		out.append({
			"id": str(m.get("id", "")),
			"name": str(m.get("name", m.get("id", ""))),
			"cost": cost,
			"interception": _espionage_interception_chance(target,
				int(m.get("interception_modifier", 0)), p.alliance_id),
		})
	return out

# Per-mission cost: the base EP-advantage curve scaled by the mission's
# cost_multiplier percent (§15.5).
func _mission_cost(attacker: Player, target: Alliance, attacker_ep: int, mission: Dictionary) -> int:
	var base: int = _espionage_mission_cost(attacker, target, attacker_ep)
	return base * int(mission.get("cost_multiplier", 100)) / 100

# §15.5 mission cost (provisional): base × (1 + EP-advantage/100). The advantage
# is how much more espionage the target holds against the attacker than the
# attacker holds against the target — a well-defended rival costs more to hit.
# When the attacker is ahead the advantage is zero (cost floors at base).
func _espionage_mission_cost(attacker: Player, target: Alliance, attacker_ep: int) -> int:
	var base: int = _db.get_constant("intel_mission_cost", 100)
	var defender_ep: int = 0
	for pid in target.member_player_ids:
		var member: Player = _gs.get_player(pid)
		if member != null:
			defender_ep += int(member.intel_points.get(attacker.alliance_id, 0))
	if defender_ep <= attacker_ep:
		return base
	var advantage: int = (defender_ep - attacker_ep) * 100 / (attacker_ep if attacker_ep > 0 else 1)
	var cap: int = _db.get_constant("intel_cost_advantage_max", 200)
	if advantage > cap:
		advantage = cap
	return base + base * advantage / 100

# Interception chance against missions targeting this alliance: the base chance
# plus the strongest espionage_defense structure across the target's cities, plus
# the mission's own `extra` modifier, plus a counterespionage bonus when a target
# member holds active cover against the attacker's alliance, capped (§15.5).
# `attacker_alliance_id` < 0 (the default, used by the read-only UI preview queries)
# skips the counterespionage term since no specific attacker is known.
func _espionage_interception_chance(target: Alliance, extra: int = 0,
		attacker_alliance_id: int = -1) -> int:
	var defense: int = 0
	var counter: int = 0
	for s in _gs.settlements:
		var owner: Player = _gs.get_player(s.owner_player_id)
		if owner == null or owner.alliance_id != target.id:
			continue
		for struct_id in s.structures:
			var d: int = int(_db.get_structure(struct_id).get("effects", {}).get("espionage_defense", 0))
			if d > defense:
				defense = d
		if attacker_alliance_id >= 0 \
				and int(owner.counter_espionage.get(attacker_alliance_id, 0)) > 0:
			counter = _db.get_constant("intel_counterespionage_bonus", 25)
	var chance: int = _db.get_constant("intel_interception_chance", 25) + defense + extra + counter
	if chance < 0:
		chance = 0
	var cap: int = _db.get_constant("intel_interception_max", 90)
	return cap if chance > cap else chance

func _espionage_steal_tech(thief: Player, target: Alliance, target_city = null) -> void:
	var victims: Array = _mission_owners(target, target_city)
	for victim in victims:
		for tech in victim.technologies:
			if not thief.has_tech(tech):
				thief.technologies.append(tech)
				_add_notification("Stole technology: " + str(tech), "major")
				return

func _espionage_sabotage(target: Alliance, target_city = null) -> void:
	var victim: Settlement = target_city if target_city != null else _largest_target_city(target)
	if victim != null:
		victim.production_store = victim.production_store / 2
		_add_notification("Sabotaged production in " + victim.name, "major")

# Destroy building: raze the costliest non-Palace structure in the victim city (§7.1).
# Deterministic — costliest first, lowest id on a cost tie.
func _espionage_destroy_building(target: Alliance, target_city = null) -> void:
	var victim: Settlement = target_city if target_city != null else _largest_target_city(target)
	if victim == null:
		return
	var best_id: String = ""
	var best_cost: int = -1
	for struct_id in victim.structures:
		if struct_id == "palace":
			continue
		var cost: int = int(_db.get_structure(struct_id).get("cost", 0))
		if cost > best_cost:
			best_cost = cost
			best_id = struct_id
	if best_id != "":
		victim.structures.erase(best_id)
		victim.structure_bonuses.erase(best_id)
		var sname: String = str(_db.get_structure(best_id).get("name", best_id))
		_add_notification("Destroyed %s in %s." % [sname, victim.name], "major")

# Destroy project: cancel the endgame project a victim city is building, wiping its
# stored production (§7.1). Deterministic — the largest such city, lowest id on a tie.
func _espionage_destroy_project(target: Alliance, target_city = null) -> void:
	var victim: Settlement = target_city
	if victim == null:
		for s in _gs.settlements:
			if not _settlement_in_alliance(s, target) or not _settlement_building_project(s):
				continue
			if victim == null or s.population > victim.population \
					or (s.population == victim.population and s.id < victim.id):
				victim = s
	if victim == null or not _settlement_building_project(victim):
		return
	var pname: String = str(victim.production_queue[0].get("id", "project"))
	victim.production_queue.remove(0)
	victim.production_store = 0
	_add_notification("Sabotaged the %s project in %s." % [pname, victim.name], "major")

# Destroy improvement: clear the first tile improvement worked by the victim city
# (§7.1). Deterministic — first improved worked tile in order.
func _espionage_destroy_improvement(target: Alliance, target_city = null) -> void:
	var tile = _city_improved_tile(target_city) if target_city != null \
		else _alliance_improved_tile(target)
	if tile == null:
		return
	var imp: String = tile.improvement_id
	tile.improvement_id = ""
	tile.improvement_turns_left = 0
	tile.improvement_age = 0
	_add_notification("Destroyed a %s improvement." % imp, "major")

# Spread culture: pour `amount` of the attacker's cultural influence onto the victim
# city's tile, feeding §4.9 cultural-revolt pressure (§7.1).
func _espionage_insert_culture(thief: Player, target: Alliance, amount: int, target_city = null) -> void:
	var victim: Settlement = target_city if target_city != null else _largest_target_city(target)
	if victim == null:
		return
	var tile = _gs.map.get_tile(victim.x, victim.y)
	if tile == null:
		return
	tile.influence[thief.id] = int(tile.influence.get(thief.id, 0)) + amount
	_add_notification("Spread culture into " + victim.name, "major")

# Foment unrest: add a timed angry-citizen modifier (`faces` for `turns` turns) to
# the victim city — temporary discontent that decays (§7.1).
func _espionage_incite_unhappiness(target: Alliance, faces: int, turns: int, target_city = null) -> void:
	var victim: Settlement = target_city if target_city != null else _largest_target_city(target)
	if victim == null:
		return
	victim.timed_happiness.append({"amount": -faces, "turns_left": turns})
	_add_notification("Fomented unrest in " + victim.name, "major")

# Incite revolt: tip the victim city into disorder and start a `turns`-turn revolt so
# it produces nothing until order is restored (§7.1).
func _espionage_incite_revolt(target: Alliance, turns: int, target_city = null) -> void:
	var worst: Settlement = target_city if target_city != null else _largest_target_city(target)
	if worst != null:
		worst.in_disorder = true
		worst.discontented = worst.population
		if turns > worst.revolt_turns:
			worst.revolt_turns = turns
		_add_notification("Incited revolt in " + worst.name, "major")

# Foment anarchy: force a victim into `turns` turns of governmental anarchy. When
# `drop_religion` is set (the switch-religion mission) the victim must have a state
# religion, which it loses. With `target_city` the victim is that city's owner; on the
# alliance path it is the largest qualifying city's owner. Deterministic (§7.1).
func _espionage_force_anarchy(target: Alliance, turns: int, drop_religion: bool, target_city = null) -> void:
	var victim: Player = null
	if target_city != null:
		var o: Player = _gs.get_player(target_city.owner_player_id)
		if o != null and (not drop_religion or o.state_religion != ""):
			victim = o
	elif drop_religion:
		var best_city: Settlement = null
		for s in _gs.settlements:
			if not _settlement_in_alliance(s, target):
				continue
			var owner: Player = _gs.get_player(s.owner_player_id)
			if owner == null or owner.state_religion == "":
				continue
			if best_city == null or s.population > best_city.population \
					or (s.population == best_city.population and s.id < best_city.id):
				best_city = s
		if best_city != null:
			victim = _gs.get_player(best_city.owner_player_id)
	else:
		var victim_city: Settlement = _largest_target_city(target)
		if victim_city != null:
			victim = _gs.get_player(victim_city.owner_player_id)
	if victim == null:
		return
	var span: int = turns if turns > 0 else _db.get_constant("espionage_anarchy_turns", 2)
	if span > victim.transition_turns:
		victim.transition_turns = span
	if drop_religion:
		victim.state_religion = ""
		_add_notification("Incited a religious schism in " + victim.name, "major")
	else:
		_add_notification("Fomented anarchy in " + victim.name, "major")

# Counterespionage: the attacker takes up `turns` turns of heightened interception
# against the target alliance's missions (recorded on the attacker's ledger) (§7.1).
func _espionage_counterespionage(thief: Player, target: Alliance, turns: int) -> void:
	thief.counter_espionage[target.id] = turns
	_add_notification("Counterespionage cover established.", "major")

# Steal treasury: transfer up to `amount` gold from the richest victim to the attacker
# (§7.1). With `target_city` the victim is that city's owner; on the alliance path it is
# the richest member (lowest id on a tie). Nothing happens when the victim is broke.
func _espionage_steal_gold(thief: Player, target: Alliance, amount: int, target_city = null) -> void:
	var richest: Player = null
	for member in _mission_owners(target, target_city):
		if member.treasury <= 0:
			continue
		if richest == null or member.treasury > richest.treasury \
				or (member.treasury == richest.treasury and member.id < richest.id):
			richest = member
	if richest == null:
		return
	var taken: int = amount if amount < richest.treasury else richest.treasury
	richest.treasury -= taken
	thief.treasury += taken
	_add_notification("Stole %d gold from %s." % [taken, richest.name], "major")

# Poison water supply: starve one population out of the victim city (§7.1). On the
# alliance path the most populous city of at least population 2 (lowest id on a tie)
# loses a citizen.
func _espionage_poison_water(target: Alliance, target_city = null) -> void:
	var biggest: Settlement = target_city
	if biggest == null:
		for s in _gs.settlements:
			if not _settlement_in_alliance(s, target) or s.population < 2:
				continue
			if biggest == null or s.population > biggest.population \
					or (s.population == biggest.population and s.id < biggest.id):
				biggest = s
	if biggest != null and biggest.population >= 2:
		biggest.population -= 1
		_add_notification("Poisoned the water supply of " + biggest.name, "major")

# ── Passive intel (§25.6): threshold-based information missions ───────────────
#
# Passive missions (kind "passive" in data/espionage_missions.json) spend no EP.
# Their intel stays revealed WHILE the attacker's banked EP against the target
# alliance meets the mission's threshold, so what a player knows is a pure
# function of current state — nothing new is serialized and save/load is
# untouched. Threshold = intel_mission_cost × threshold_multiplier/100, scaled
# by the same capped EP-advantage curve as active mission costs, then by a
# distance surcharge: +intel_passive_distance_percent% at a Chebyshev distance
# of half the map's mean dimension between the viewer's capital and the target
# city (city-scope missions) or the target's nearest city (alliance scope).

# The threshold the viewer's EP must meet for `mission` against `target`.
# `target_city` (a Settlement or null) fixes the city for city-scope missions.
func _passive_intel_threshold(viewer: Player, target: Alliance,
		mission: Dictionary, target_city) -> int:
	var have: int = int(viewer.intel_points.get(target.id, 0))
	var base: int = _espionage_mission_cost(viewer, target, have)
	base = base * int(mission.get("threshold_multiplier", 100)) / 100
	var diag: int = (_gs.map.width + _gs.map.height) / 2
	if diag > 0:
		var pct: int = _db.get_constant("intel_passive_distance_percent", 100)
		base += base * (pct * _intel_distance(viewer, target, target_city)) / (diag * 100)
	return base

# Whether the viewer currently holds `mission_id`'s intel over the target.
# False for anything that is not a passive record, and always false against the
# viewer's own alliance (there is nothing to reveal).
func _passive_intel_active(viewer: Player, target: Alliance,
		mission_id: String, target_city) -> bool:
	if viewer == null or target == null or viewer.alliance_id == target.id:
		return false
	var mission: Dictionary = _db.get_espionage_mission(mission_id)
	if mission.empty() or str(mission.get("kind", "active")) != "passive":
		return false
	var have: int = int(viewer.intel_points.get(target.id, 0))
	if have <= 0:
		return false
	return have >= _passive_intel_threshold(viewer, target, mission, target_city)

# Current-player wrappers for the UI (§25.6). `city_id` >= 0 pins a city-scope
# mission's target; alliance-scope missions ignore it.
func passive_intel_active(mission_id: String, target_alliance_id: int, city_id: int = -1) -> bool:
	var viewer: Player = _gs.get_player(_gs.current_player_id)
	var target: Alliance = _gs.get_alliance(target_alliance_id)
	var city = _gs.get_settlement(city_id) if city_id >= 0 else null
	return _passive_intel_active(viewer, target, mission_id, city)

func passive_intel_threshold(mission_id: String, target_alliance_id: int, city_id: int = -1) -> int:
	var viewer: Player = _gs.get_player(_gs.current_player_id)
	var target: Alliance = _gs.get_alliance(target_alliance_id)
	var mission: Dictionary = _db.get_espionage_mission(mission_id)
	if viewer == null or target == null or mission.empty():
		return 0
	var city = _gs.get_settlement(city_id) if city_id >= 0 else null
	return _passive_intel_threshold(viewer, target, mission, city)

# Chebyshev distance from the viewer's capital to the target city, or to the
# target alliance's nearest city on the alliance-scope path. 0 when either side
# has no city yet (no surcharge rather than a spurious one).
func _intel_distance(viewer: Player, target: Alliance, target_city) -> int:
	var cap: Settlement = _player_capital(viewer.id)
	if cap == null:
		return 0
	if target_city != null:
		return _chebyshev(cap.x, cap.y, target_city.x, target_city.y)
	var best: int = -1
	for s in _gs.settlements:
		if not _settlement_in_alliance(s, target):
			continue
		var d: int = _chebyshev(cap.x, cap.y, s.x, s.y)
		if best < 0 or d < best:
			best = d
	return best if best >= 0 else 0

# The player's capital: the city holding the Palace, falling back to the
# earliest-founded (lowest-id) owned city.
func _player_capital(player_id: int) -> Settlement:
	var fallback: Settlement = null
	for s in _gs.settlements:
		if s.owner_player_id != player_id:
			continue
		if s.structures.has("palace"):
			return s
		if fallback == null or s.id < fallback.id:
			fallback = s
	return fallback

func _chebyshev(ax: int, ay: int, bx: int, by: int) -> int:
	var dx: int = ax - bx if ax > bx else bx - ax
	var dy: int = ay - by if ay > by else by - ay
	return dx if dx > dy else dy

# Whether any member of the victim alliance holds detect_missions intel over the
# attacker (§25.6): the victim then learns WHO is behind a mission it suffers
# (or intercepts) instead of an anonymous strike.
func _intel_detects(victim: Alliance, attacker_alliance_id: int) -> bool:
	var attacker_alliance: Alliance = _gs.get_alliance(attacker_alliance_id)
	if attacker_alliance == null:
		return false
	for pid in victim.member_player_ids:
		if _passive_intel_active(_gs.get_player(pid), attacker_alliance,
				"detect_missions", null):
			return true
	return false

# What the current player may legitimately see of a rival's city (§25.6
# information fog): its defensive posture only — the defence bonus its
# structures grant, its siege HP, the garrison, and which of its structures are
# defensive. Population, production and the full building list stay hidden
# until the viewer's investigate_city intel is active against that city.
# Shared by tile_info_text and the espionage advisor.
func city_intel_lines(city_id: int) -> Array:
	var s: Settlement = _gs.get_settlement(city_id)
	if s == null:
		return []
	var owner: Player = _gs.get_player(s.owner_player_id)
	var owner_name: String = owner.name if owner != null else "Wild"
	var lines: Array = []
	lines.append(owner_name + "'s city: " + s.name)
	var maxh: int = TurnEngine.city_max_health(s, _db)
	var hp: int = s.health if s.health >= 0 and s.health <= maxh else maxh
	lines.append("Defence: +" + str(Combat.settlement_defence(s, _db)) + "%   HP: " \
		+ str(hp) + "/" + str(maxh))
	var defences: Array = []
	for struct_id in s.structures:
		var st: Dictionary = _db.get_structure(struct_id)
		if int(st.get("defence_bonus", 0)) > 0 or int(st.get("cultural_defence_bonus", 0)) > 0:
			defences.append(str(st.get("name", str(struct_id).capitalize())))
	if not defences.empty():
		lines.append("Defences: " + PoolStringArray(defences).join(", "))
	var garrison: Dictionary = {}   # unit display name → count
	for u in _gs.units:
		if u.x == s.x and u.y == s.y and u.owner_player_id != _gs.current_player_id \
				and not _is_espionage_unit(u):
			var uname: String = str(_db.get_unit(u.unit_type_id).get("name", u.unit_type_id.capitalize()))
			garrison[uname] = int(garrison.get(uname, 0)) + 1
	if garrison.empty():
		lines.append("Garrison: none")
	else:
		var parts: Array = []
		for uname in garrison:
			parts.append(str(garrison[uname]) + "x " + uname)
		lines.append("Garrison: " + PoolStringArray(parts).join(", "))
	if owner != null and passive_intel_active("investigate_city", owner.alliance_id, s.id):
		lines.append("Population: " + str(s.population))
		if not s.production_queue.empty():
			var item: Dictionary = s.production_queue[0]
			lines.append("Producing: " + str(item.get("id", "")).capitalize())
		if not s.structures.empty():
			var names: Array = []
			for struct_id in s.structures:
				names.append(str(_db.get_structure(struct_id).get("name", str(struct_id).capitalize())))
			lines.append("Structures: " + PoolStringArray(names).join(", "))
	return lines

# Empire-wide demographics for a player (§25.6 see_demographics): the summary
# the demographics reveal shows on the espionage advisor. Computed live from
# game state; also valid for the viewer's own empire.
func player_demographics(player_id: int) -> Dictionary:
	var pop: int = 0
	var cities: int = 0
	var production: int = 0
	var gnp: int = 0
	for s in _gs.settlements:
		if s.owner_player_id != player_id:
			continue
		cities += 1
		pop += s.population
		production += s.output_production
		gnp += s.output_commerce
	var soldiers: int = 0
	var power: int = 0
	for u in _gs.units:
		if u.owner_player_id != player_id:
			continue
		soldiers += 1
		power += int(_db.get_unit(u.unit_type_id).get("base_strength", 0))
	var land: int = 0
	for y in range(_gs.map.height):
		for x in range(_gs.map.width):
			if _gs.map.get_tile(x, y).owner_player_id == player_id:
				land += 1
	return {"population": pop, "cities": cities, "production": production,
		"gnp": gnp, "soldiers": soldiers, "power": power, "land": land}

# The rival's current research target and progress (§25.6 see_research).
func player_research_info(player_id: int) -> Dictionary:
	var p: Player = _gs.get_player(player_id)
	if p == null or p.current_research_id == "":
		return {}
	return {"tech": p.current_research_id,
		"progress": p.research_store,
		"cost": int(_db.get_technology(p.current_research_id).get("cost", 0))}

# Tiles kept in live sight by city_visibility intel (§25.6): every rival city
# the current player holds that intel over lights its surroundings within
# intel_city_visibility_radius. Merged into player_visible_tiles below.
func _intel_visible_tiles(player_id: int) -> Dictionary:
	var viewer: Player = _gs.get_player(player_id)
	if viewer == null:
		return {}
	var out: Dictionary = {}
	var radius: int = _db.get_constant("intel_city_visibility_radius", 2)
	for s in _gs.settlements:
		var owner: Player = _gs.get_player(s.owner_player_id)
		if owner == null or owner.alliance_id == viewer.alliance_id:
			continue
		var target: Alliance = _gs.get_alliance(owner.alliance_id)
		if not _passive_intel_active(viewer, target, "city_visibility", s):
			continue
		for dy in range(-radius, radius + 1):
			for dx in range(-radius, radius + 1):
				if _gs.map.is_valid(s.x + dx, s.y + dy):
					out[str(s.x + dx) + "," + str(s.y + dy)] = true
	return out

# ── Transport / embarkation (§5.2) ────────────────────────────────────────────

func _cmd_load_unit(cmd: Dictionary) -> bool:
	var p: Player = _gs.get_player(int(cmd["player_id"]))
	if p == null:
		return false
	var u: Unit = _gs.get_unit(int(cmd.get("unit_id", -1)))
	var t: Unit = _gs.get_unit(int(cmd.get("transport_id", -1)))
	if u == null or t == null or u.owner_player_id != p.id or t.owner_player_id != p.id:
		return false
	if _db.get_unit(u.unit_type_id).get("domain", "land") != "land":
		return false
	var cap: int = int(_db.get_unit(t.unit_type_id).get("transport_capacity", 0))
	if cap <= 0 or t.cargo.size() >= cap:
		return false
	if _gs.map.distance(u.x, u.y, t.x, t.y) > 1:
		return false
	u.x = t.x; u.y = t.y
	u.transported_by = t.id
	u.movement_left = 0; u.has_moved = true
	if not (u.id in t.cargo):
		t.cargo.append(u.id)
	_dirty.set_dirty(IDs.DirtyRegion.WORLD)
	return true

func _cmd_unload_unit(cmd: Dictionary) -> bool:
	var p: Player = _gs.get_player(int(cmd["player_id"]))
	if p == null:
		return false
	var u: Unit = _gs.get_unit(int(cmd.get("unit_id", -1)))
	if u == null or u.owner_player_id != p.id or u.transported_by < 0:
		return false
	var tx: int = int(cmd.get("target_x", u.x))
	var ty: int = int(cmd.get("target_y", u.y))
	if _gs.map.distance(u.x, u.y, tx, ty) > 1:
		return false
	var tile: Tile = _gs.map.get_tile(tx, ty)
	if tile == null or _db.get_terrain(tile.terrain_id).get("domain", "land") != "land":
		return false
	var t: Unit = _gs.get_unit(u.transported_by)
	if t != null:
		t.cargo.erase(u.id)
	u.transported_by = -1
	u.x = tx; u.y = ty
	u.movement_left = 0; u.has_moved = true
	_dirty.set_dirty(IDs.DirtyRegion.WORLD)
	return true

# ── Helpers ───────────────────────────────────────────────────────────────────

# Apply a resolved unit-vs-unit combat to state. Thin wrapper over the shared
# pure CombatApply sim module (also used by WildAI); callers emit combat_resolved.
func _apply_combat_result(attacker: Unit, defender: Unit,
		result: Dictionary, advance: bool = true) -> void:
	CombatApply.apply_unit_result(_gs, attacker, defender, result, advance)

# An enemy fighter near the target may intercept an inbound air strike. Returns
# true if the strike is aborted (the bomber was engaged), resolving the air-to-air
# combat as a side effect (§5.2).
func _resolve_interception(bomber: Unit, tx: int, ty: int, player_id: int) -> bool:
	var reach: int = _db.get_constant("interception_range", 2)
	var interceptor: Unit = null
	var best_d: int = 999
	for u in _gs.units:
		if u.owner_player_id == player_id:
			continue
		if _db.get_unit(u.unit_type_id).get("domain", "") != "air":
			continue
		if u.owner_player_id != -2 and not _gs.are_at_war(player_id, u.owner_player_id):
			continue
		var d: int = _gs.map.distance(tx, ty, u.x, u.y)
		if d <= reach and d < best_d:
			interceptor = u; best_d = d
	if interceptor == null:
		return false
	if not _gs.rng.rand_bool_percent(_db.get_constant("interception_chance", 50)):
		return false
	# The interceptor engages the bomber (no advance for either side).
	var ir: Dictionary = Combat.resolve(interceptor, bomber, _gs, _gs.rng)
	_apply_combat_result(interceptor, bomber, ir, false)
	emit_signal("combat_resolved", ir)
	_add_combat_notification(interceptor, bomber, ir)
	return true

# Spread a religion to a city with a missionary unit (§8). The missionary must be
# the player's, carry the `spread_religion` tag, and sit on the target city's tile.
# It spreads the player's religion (state religion, else a belief the player
# founded or whose faith its cities hold) to a city that has none, respecting
# Theocracy's non-state-spread block. The missionary is consumed on success.
func _cmd_spread_belief(cmd: Dictionary) -> bool:
	var p: Player = _gs.get_player(int(cmd["player_id"]))
	if p == null:
		return false
	var u: Unit = _gs.get_unit(int(cmd.get("unit_id", -1)))
	if u == null or u.owner_player_id != p.id:
		return false
	if not ("spread_religion" in _db.get_unit(u.unit_type_id).get("tags", [])):
		return false
	var s: Settlement = _gs.get_settlement(int(cmd.get("settlement_id", -1)))
	if s == null or s.x != u.x or s.y != u.y:
		return false
	if s.belief_id != "":
		return false  # single-belief model: only converts a faithless city
	var belief_id: String = _belief_to_spread(p)
	if belief_id == "":
		return false
	if Beliefs._spread_blocked(_gs, _db, s, belief_id):
		return false
	s.belief_id = belief_id
	Stack.remove_unit(_gs.units, u.id)
	if _selection != null:
		_selection.selected_unit_ids.erase(u.id)
	var belief_name: String = str(_db.beliefs.get(belief_id, {}).get("name", belief_id))
	_add_notification(belief_name + " spread to " + s.name + ".", "info")
	_dirty.set_dirty(IDs.DirtyRegion.WORLD)
	_dirty.set_dirty(IDs.DirtyRegion.DATA_PANES)
	return true

# The religion a player's missionary carries: the state religion if adopted, else
# a belief the player founded, else one its cities already follow. "" if none.
func _belief_to_spread(p: Player) -> String:
	if p.state_religion != "":
		return p.state_religion
	for bid in _gs.founded_beliefs:
		if int(_gs.founded_beliefs[bid]) == p.id:
			return bid
	for s in _gs.settlements:
		if s.owner_player_id == p.id and s.belief_id != "":
			return s.belief_id
	return ""

# Spread a corporation to a city with an executive unit (§14.6). The executive
# must be the player's, carry the `spread_corporation` tag, and sit on the target
# city's tile. It spreads the corporation the player founded into a city that has
# none (and whose owner does not ban corporations), charging the spread cost. The
# executive is consumed on success.
func _cmd_spread_corporation(cmd: Dictionary) -> bool:
	var p: Player = _gs.get_player(int(cmd["player_id"]))
	if p == null:
		return false
	var u: Unit = _gs.get_unit(int(cmd.get("unit_id", -1)))
	if u == null or u.owner_player_id != p.id:
		return false
	if not ("spread_corporation" in _db.get_unit(u.unit_type_id).get("tags", [])):
		return false
	var s: Settlement = _gs.get_settlement(int(cmd.get("settlement_id", -1)))
	if s == null or s.x != u.x or s.y != u.y:
		return false
	var org_id: String = EconOrgs.corporation_of_player(_gs, p.id)
	if org_id == "":
		return false
	var cost: int = _db.get_constant("corporation_executive_spread_cost", 100)
	if p.treasury < cost:
		return false
	if not EconOrgs.spread_to(org_id, s, _gs):
		return false
	p.treasury -= cost
	Stack.remove_unit(_gs.units, u.id)
	if _selection != null:
		_selection.selected_unit_ids.erase(u.id)
	var org_name: String = str(_db.econ_orgs.get(org_id, {}).get("name", org_id))
	_add_notification(org_name + " spread to " + s.name + ".", "info")
	_dirty.set_dirty(IDs.DirtyRegion.WORLD)
	_dirty.set_dirty(IDs.DirtyRegion.DATA_PANES)
	return true

# Conscript a military unit from a city (§6.4). Requires the can_draft civic
# (Nationhood); spends population and stirs unhappiness; the drafted unit is the
# most advanced draftable unit the player has the technology for.
func _cmd_draft(cmd: Dictionary) -> bool:
	var p: Player = _gs.get_player(int(cmd["player_id"]))
	if p == null:
		return false
	if not PolicyEffects.has_flag(p, _db, "can_draft"):
		return false
	var s: Settlement = _gs.get_settlement(int(cmd.get("settlement_id", -1)))
	if s == null or s.owner_player_id != p.id:
		return false
	if s.in_disorder:
		return false
	var min_pop: int = _db.get_constant("draft_min_population", 2)
	if s.population < min_pop:
		return false
	var unit_id: String = _draftable_unit(p)
	if unit_id == "":
		return false
	# Spend population and stir conscription unhappiness (reuses the rush-anger
	# channel that feeds contentment).
	var pop_cost: int = _db.get_constant("draft_population_cost", 1)
	s.population -= pop_cost
	if s.population < 1:
		s.population = 1
	s.food_store = 0
	var anger: int = _db.get_constant("draft_anger_turns", 5)
	if s.rush_anger_turns < anger:
		s.rush_anger_turns = anger
	# Raise the unit at the city. Drafted units come only with civic XP (no
	# building XP), reflecting their reduced training.
	var u := Unit.new()
	u.id = _gs.next_unit_id()
	u.unit_type_id = unit_id
	u.owner_player_id = p.id
	u.x = s.x; u.y = s.y
	var udata: Dictionary = _db.get_unit(unit_id)
	u.base_strength = int(udata.get("base_strength", 5))
	u.movement_total = int(udata.get("movement", 120))
	u.movement_left = u.movement_total
	u.experience = PolicyEffects.sum_int(p, _db, "new_unit_xp")
	_gs.units.append(u)
	emit_signal("unit_created", u.id)
	_dirty.set_dirty(IDs.DirtyRegion.WORLD)
	_dirty.set_dirty(IDs.DirtyRegion.HUD_GROUPS)
	return true

# The most advanced draftable unit (data `draftable`) whose tech and resource
# prerequisites the player meets (compound forms per §15.12), ranked by base
# strength. "" when none is available.
func _draftable_unit(p: Player) -> String:
	var best_id: String = ""
	var best_str: int = -1
	var have: Dictionary = EconOrgs.accessible_resources(_gs, p.id)
	for uid in _db.units:
		var ud: Dictionary = _db.units[uid]
		if not ud.get("draftable", false):
			continue
		if not UnitPrereqs.tech_ok(ud.get("tech_required", null), p):
			continue
		if not UnitPrereqs.resource_ok(ud.get("resource_required", null), have):
			continue
		var st: int = int(ud.get("base_strength", 0))
		if st > best_str:
			best_str = st
			best_id = uid
	return best_id

# Remove a spent `one_use` weapon after its strike resolves. The attacker may
# already have died in the exchange (removed by _apply_combat_result), so only
# remove it if it still exists.
func _consume_one_use(u: Unit) -> void:
	if _gs.get_unit(u.id) == null:
		return
	Stack.remove_unit(_gs.units, u.id)
	if _selection != null:
		_selection.selected_unit_ids.erase(u.id)
	_dirty.set_dirty(IDs.DirtyRegion.WORLD)

# Launch a one-use nuclear weapon at a target tile (§5.7). The missile is consumed
# whether or not it is intercepted. Forbidden while a Non-Proliferation resolution
# (`no_nuclear`) is in force.
func _cmd_nuclear_strike(cmd: Dictionary) -> bool:
	var player_id: int = int(cmd["player_id"])
	var u: Unit = _gs.get_unit(int(cmd.get("unit_id", -1)))
	if u == null or u.owner_player_id != player_id:
		return false
	if not Nuclear.is_nuke(_db, u):
		return false
	if not Nuclear.nukes_enabled(_gs):
		return false
	# Non-Proliferation in force: launching is forbidden (§5.7 / §7.2).
	if bool(_gs.assembly.get("standing", {}).get("no_nuclear", false)):
		return false
	var tx: int = int(cmd.get("target_x", -1))
	var ty: int = int(cmd.get("target_y", -1))
	if not _gs.map.is_valid(tx, ty):
		return false
	# Range: a `global_range` weapon (ICBM) reaches any tile; otherwise air_range.
	var udata: Dictionary = _db.get_unit(u.unit_type_id)
	if not ("global_range" in udata.get("tags", [])):
		var reach: int = int(udata.get("air_range", 12))
		if _gs.map.distance(u.x, u.y, tx, ty) > reach:
			return false

	# The unit is spent on launch; remove it first so it is never caught in its own
	# blast (we still hold the reference for owner/type lookups in detonate).
	Stack.remove_unit(_gs.units, u.id)
	if _selection != null:
		_selection.selected_unit_ids.erase(u.id)

	# Interception aborts the strike with no effect on the target.
	if Nuclear.try_intercept(_gs, u, tx, ty, _gs.rng):
		var p_nuke: Player = _gs.get_player(player_id)
		var who_nuke: String = p_nuke.name if p_nuke != null else "A nuclear weapon"
		_add_notification(who_nuke + "'s nuclear strike was intercepted!", "major")
		emit_signal("event_emitted", {
			"type": "nuclear_intercepted",
			"player_id": player_id, "target_x": tx, "target_y": ty
		})
		_dirty.set_dirty(IDs.DirtyRegion.WORLD)
		_dirty.set_dirty(IDs.DirtyRegion.HUD_GROUPS)
		return true

	var result: Dictionary = Nuclear.detonate(_gs, u, tx, ty, _gs.rng)

	# A strike is an act of war: declare war on every victim's alliance (§5.7).
	var attacker_alliance: Alliance = _gs.get_player_alliance(player_id)
	if attacker_alliance != null:
		for aid in result["victim_alliance_ids"]:
			if aid == attacker_alliance.id:
				continue
			if not attacker_alliance.is_at_war_with(aid):
				attacker_alliance.at_war_with.append(aid)
			if not attacker_alliance.has_contact_with(aid):
				attacker_alliance.contacts.append(aid)

	var p_nuke2: Player = _gs.get_player(player_id)
	var who_nuke2: String = p_nuke2.name if p_nuke2 != null else "A nuclear weapon"
	_add_notification(who_nuke2 + " detonated a nuclear weapon at (" + str(tx) + "," + str(ty) + ")!", "major")
	emit_signal("nuclear_detonated", result)
	_dirty.set_dirty(IDs.DirtyRegion.WORLD)
	_dirty.set_dirty(IDs.DirtyRegion.HUD_GROUPS)
	_dirty.set_dirty(IDs.DirtyRegion.DATA_PANES)
	return true

# True if a hostile unit (wild, or an enemy at war) occupies a tile adjacent to
# (x, y). Used to apply zones of control (§5.2).
func _adjacent_hostile(x: int, y: int, player_id: int) -> bool:
	for nb in _gs.map.neighbours8(x, y):
		for u in _gs.units:
			if u.x != nb.x or u.y != nb.y or u.owner_player_id == player_id:
				continue
			if u.owner_player_id == -2 or _gs.are_at_war(player_id, u.owner_player_id):
				return true
	return false

func _get_next_player_index(current_player_id: int) -> int:
	for i in range(_gs.players.size()):
		if _gs.players[i].id == current_player_id:
			return (i + 1) % _gs.players.size()
	return 0

# ── New command handlers ───────────────────────────────────────────────────────

func _cmd_unit_command(cmd: Dictionary) -> bool:
	var player_id: int = int(cmd["player_id"])
	var unit_id: int = int(cmd.get("unit_id", -1))
	var u: Unit = _gs.get_unit(unit_id)
	if u == null or u.owner_player_id != player_id:
		return false

	var ctype: int = int(cmd.get("type", -1))
	match ctype:
		IDs.CommandType.UNIT_WAKE:
			u.is_fortified = false
			u.is_sentry = false
			u.is_patrolling = false
			u.is_healing = false
			u.is_sleeping = false
			u.is_sleep_until_healed = false
			u.is_fortify_until_healed = false
			u.is_exploring = false
			u.has_moved = false
			u.movement_left = u.movement_total
		IDs.CommandType.UNIT_SLEEP:
			# Sleep is a skip-until-woken order, distinct from fortify, so the UI can
			# show it as "Sleeping". It still ends the unit's turn.
			u.is_sleeping = true
			u.has_moved = true
			u.movement_left = 0
		IDs.CommandType.UNIT_FORTIFY:
			# Only land combat units may fortify (Issue 3): no civilians, no naval/air,
			# no strengthless units. Single sim-side gate via Unit.can_fortify.
			if not u.can_fortify(_db):
				return false
			u.is_fortified = true
			u.has_moved = true
			u.movement_left = 0
		IDs.CommandType.UNIT_CANCEL_ORDERS:
			u.building_improvement = ""
			u.clearing_feature = ""
			u.build_turns_left = 0
			u.is_sleeping = false
			u.is_sleep_until_healed = false
			u.is_fortify_until_healed = false
			u.is_exploring = false
			u.goto_x = -1
			u.goto_y = -1
			u.has_moved = false
			u.movement_left = u.movement_total
		IDs.CommandType.UNIT_DISBAND:
			Stack.remove_unit(_gs.units, unit_id)
		IDs.CommandType.UNIT_PROMOTE:
			var promo_id: String = str(cmd.get("promotion_id", ""))
			if promo_id == "" or promo_id in u.promotions:
				return false
			u.promotions.append(promo_id)
		IDs.CommandType.UNIT_UPGRADE:
			var udata: Dictionary = _db.get_unit(u.unit_type_id)
			var upgrades_to: String = str(udata.get("upgrades_to", ""))
			if upgrades_to == "":
				return false
			var new_udata: Dictionary = _db.get_unit(upgrades_to)
			if new_udata.empty():
				return false
			var cost: int = int(new_udata.get("cost", 0)) - int(udata.get("cost", 0))
			var p: Player = _gs.get_player(player_id)
			if p == null or p.treasury < cost:
				return false
			# Upgrading gates on the *target* unit's prerequisites (compound tech
			# AND-lists and all/any resource sets, §15.12) — you cannot buy your
			# way into a unit your empire could not train.
			if not UnitPrereqs.tech_ok(new_udata.get("tech_required", null), p):
				return false
			if not UnitPrereqs.resource_ok(new_udata.get("resource_required", null),
					EconOrgs.accessible_resources(_gs, player_id)):
				return false
			p.treasury -= cost
			u.unit_type_id = upgrades_to
			u.base_strength = int(new_udata.get("base_strength", u.base_strength))
		IDs.CommandType.UNIT_GIFT:
			var target_id: int = int(cmd.get("target_player_id", -1))
			var target: Player = _gs.get_player(target_id)
			if target == null or target_id == player_id:
				return false
			# Cargo travels with its transport; reassign it too.
			for cargo_id in u.cargo:
				var c: Unit = _gs.get_unit(cargo_id)
				if c != null:
					c.owner_player_id = target_id
			u.owner_player_id = target_id
			_selection.selected_unit_ids.erase(unit_id)
		_:
			return false

	_dirty.set_dirty(IDs.DirtyRegion.WORLD)
	_dirty.set_dirty(IDs.DirtyRegion.HUD_GROUPS)
	return true

func _cmd_mission(cmd: Dictionary) -> bool:
	var player_id: int = int(cmd["player_id"])
	var unit_id: int = int(cmd.get("unit_id", -1))
	var u: Unit = _gs.get_unit(unit_id)
	if u == null or u.owner_player_id != player_id:
		return false

	var ctype: int = int(cmd.get("type", -1))
	match ctype:
		IDs.CommandType.MISSION_SKIP_TURN:
			u.has_moved = true
			u.movement_left = 0
		IDs.CommandType.MISSION_MOVE_TO:
			# A per-unit move order: only this unit leaves the tile, so it can be
			# peeled off a stack (unlike MOVE_STACK with no unit_ids, which moves
			# the whole tile together). A manual move cancels the explore mission.
			u.is_exploring = false
			var mc: Dictionary = {
				"type": IDs.CommandType.MOVE_STACK,
				"player_id": player_id,
				"from_x": u.x, "from_y": u.y,
				"to_x": int(cmd.get("target_x", u.x)),
				"to_y": int(cmd.get("target_y", u.y)),
				"unit_ids": [unit_id]
			}
			return _cmd_move_stack(mc)
		IDs.CommandType.MISSION_BUILD_ROAD:
			if not _db.get_unit(u.unit_type_id).get("can_build", false):
				return false
			var road: Dictionary = _db.get_improvement("road")
			if road.empty():
				return false
			u.building_improvement = "road"
			u.build_turns_left = int(road.get("build_turns", 3))
			u.has_moved = true
			u.movement_left = 0
		IDs.CommandType.MISSION_PILLAGE:
			var tile: Tile = _gs.map.get_tile(u.x, u.y)
			if tile == null or tile.improvement_id == "":
				return false
			tile.improvement_id = ""
			u.has_moved = true
			u.movement_left = 0
		IDs.CommandType.MISSION_BOMBARD:
			var tx: int = int(cmd.get("target_x", -1))
			var ty: int = int(cmd.get("target_y", -1))
			var udata_b: Dictionary = _db.get_unit(u.unit_type_id)
			var is_air: bool = udata_b.get("domain", "land") == "air"
			# A `one_use` weapon (guided missile) is spent on launch, hit or miss —
			# the same rule as the §5.7 nuke path.
			var one_use: bool = "one_use" in udata_b.get("tags", [])
			if is_air:
				# Air strikes reach within range; an interceptor may shoot the
				# bomber down before it strikes (§5.2).
				var reach: int = int(udata_b.get("air_range",
					_db.get_constant("air_strike_default_range", 4)))
				if _gs.map.distance(u.x, u.y, tx, ty) > reach:
					return false
				if _resolve_interception(u, tx, ty, player_id):
					u.has_moved = true; u.movement_left = 0
					if one_use:
						_consume_one_use(u)
					return true  # intercepted: mission aborted
			var target: Unit = Stack.get_defender(_gs.units, tx, ty, player_id, _gs)
			if target == null:
				return false
			var result: Dictionary = Combat.resolve(u, target, _gs, _gs.rng)
			# Bombard / air strike never advances onto the target tile.
			_apply_combat_result(u, target, result, false)
			emit_signal("combat_resolved", result)
			_add_combat_notification(u, target, result)
			u.has_moved = true
			if one_use:
				_consume_one_use(u)
		IDs.CommandType.MISSION_AIRLIFT:
			var tx2: int = int(cmd.get("target_x", u.x))
			var ty2: int = int(cmd.get("target_y", u.y))
			# Air units fly limited-range missions rather than teleporting (§5.2).
			if _db.get_unit(u.unit_type_id).get("domain", "land") == "air":
				var reach2: int = int(_db.get_unit(u.unit_type_id).get("air_range",
					_db.get_constant("air_strike_default_range", 4)))
				if _gs.map.distance(u.x, u.y, tx2, ty2) > reach2:
					return false
			u.x = tx2; u.y = ty2
			u.has_moved = true
			u.movement_left = 0
		IDs.CommandType.MISSION_SENTRY:
			# Hold position on watch; ends the turn but persists across turns
			# until woken (cycle-idle skips sentries — see cycle_idle_units).
			u.is_sentry = true
			u.has_moved = true
			u.movement_left = 0
		IDs.CommandType.MISSION_HEAL:
			# Hold position to recover; passive healing happens in turn upkeep.
			u.is_healing = true
			u.has_moved = true
			u.movement_left = 0
		IDs.CommandType.MISSION_AIR_PATROL, IDs.CommandType.MISSION_SEA_PATROL:
			# Patrol stance for air/naval units; holds the tile on standby.
			u.is_patrolling = true
			u.has_moved = true
			u.movement_left = 0
		IDs.CommandType.MISSION_CLEAN_FALLOUT:
			# A worker-type unit scrubs radioactive fallout off its tile (§5.7).
			if not _db.get_unit(u.unit_type_id).get("can_build", false):
				return false
			var ftile: Tile = _gs.map.get_tile(u.x, u.y)
			if ftile == null or ftile.feature_id != "fallout":
				return false
			ftile.feature_id = ""
			u.has_moved = true
			u.movement_left = 0
		IDs.CommandType.MISSION_CLEAR_FEATURE:
			# A worker-type unit chops/clears the removable feature on its tile over
			# a few turns; the clearing (and any forest chop yield) is applied when the
			# order completes in TurnEngine._advance_worker_chop (§4.11).
			if not _db.get_unit(u.unit_type_id).get("can_build", false):
				return false
			var ctile: Tile = _gs.map.get_tile(u.x, u.y)
			if ctile == null or ctile.feature_id == "":
				return false
			var cfeat: Dictionary = _db.get_feature(ctile.feature_id)
			if not bool(cfeat.get("removable", false)):
				return false
			u.clearing_feature = ctile.feature_id
			u.build_turns_left = int(cfeat.get("clear_turns",
				_db.get_constant("chop_default_turns", 4)))
			u.has_moved = true
			u.movement_left = 0
		IDs.CommandType.MISSION_SLEEP_UNTIL_HEALED:
			# Skip turns until full health, then wake idle (Issue 9). Available to
			# all units. The auto-wake is handled in TurnEngine.player_step.
			u.is_sleep_until_healed = true
			u.is_fortify_until_healed = false
			u.is_sleeping = false
			u.is_healing = false
			u.has_moved = true
			u.movement_left = 0
		IDs.CommandType.MISSION_FORTIFY_UNTIL_HEALED:
			# Fortify (gaining the defence bonus) until full health, then wake idle.
			# Only available to units that can normally fortify — land combat units
			# only (Issue 3): civilians, naval/air, and strengthless units excluded.
			if not u.can_fortify(_db):
				return false
			u.is_fortify_until_healed = true
			u.is_sleep_until_healed = false
			u.is_fortified = true
			u.is_healing = false
			u.is_sleeping = false
			u.has_moved = true
			u.movement_left = 0
		IDs.CommandType.MISSION_EXPLORE:
			# Explore mission (Issue 6): every combat unit may auto-explore, not just
			# recon/scout. A "combat unit" is non-civilian military with positive base
			# strength (classification != "civilian" AND base_strength > 0); this admits
			# melee/ranged/mounted/siege/gunpowder/armor/recon/naval/air while excluding
			# civilians (settler/worker/work_boat/spy/missionary/executive), Great People
			# and missiles (all base_strength 0). Recon and explicitly explore-tagged
			# units stay permitted regardless. Sets is_exploring; the actual move happens
			# at the start of each turn via _run_explore_missions.
			var utype_exp: Dictionary = _db.get_unit(u.unit_type_id)
			var cls_exp: String = str(utype_exp.get("classification", ""))
			var has_explore_tag: bool = "explore" in utype_exp.get("tags", [])
			var is_combat_exp: bool = cls_exp != "civilian" and u.base_strength > 0
			if not is_combat_exp and cls_exp != "recon" and not has_explore_tag:
				return false
			u.is_exploring = true
			u.is_sentry = false
			u.is_sleeping = false
			u.is_healing = false
			u.is_patrolling = false
			# Fresh order: clear any stale heading so the first step picks a new one.
			u.explore_dx = 0
			u.explore_dy = 0
			# Don't consume movement; the auto-move this turn is handled immediately.
			_explore_step(u)
			if not u.is_exploring:
				# Woken by enemy spot during the first step — notify.
				_add_notification(
					_db.get_unit(u.unit_type_id).get("name", u.unit_type_id).capitalize()
						+ " spotted an enemy and stopped exploring.", "major")
		IDs.CommandType.MISSION_MOVE_TO_UNIT:
			var tu: Unit = _gs.get_unit(int(cmd.get("target_unit_id", -1)))
			if tu == null:
				return false
			var muc: Dictionary = {
				"type": IDs.CommandType.MOVE_STACK,
				"player_id": player_id,
				"from_x": u.x, "from_y": u.y,
				"to_x": tu.x, "to_y": tu.y
			}
			return _cmd_move_stack(muc)
		IDs.CommandType.MISSION_RECON:
			# Scout toward a target tile; reveal follows the move via fog update.
			var rc: Dictionary = {
				"type": IDs.CommandType.MOVE_STACK,
				"player_id": player_id,
				"from_x": u.x, "from_y": u.y,
				"to_x": int(cmd.get("target_x", u.x)),
				"to_y": int(cmd.get("target_y", u.y))
			}
			return _cmd_move_stack(rc)
		_:
			return false

	_dirty.set_dirty(IDs.DirtyRegion.WORLD)
	_dirty.set_dirty(IDs.DirtyRegion.HUD_GROUPS)
	return true

# ── Explore mission helpers ────────────────────────────────────────────────────

# Run one explore step for a single unit. Picks a random passable, non-enemy
# neighbour to move toward and takes one step. If an enemy unit is within the
# unit's sight range the mission ends and the player is alerted. When no valid
# step can be found (surrounded or at map edge), the mission also ends.
func _explore_step(u: Unit) -> void:
	if not u.is_exploring:
		return
	var player_id: int = u.owner_player_id
	var sight: int = _db.get_constant("unit_sight", 2)
	# Check for enemies within sight: if any are visible, wake the scout.
	for eu in _gs.units:
		if eu.owner_player_id == player_id:
			continue
		if eu.owner_player_id != -2 and not _gs.are_at_war(player_id, eu.owner_player_id):
			continue
		if _gs.map.distance(u.x, u.y, eu.x, eu.y) <= sight:
			u.is_exploring = false
			u.has_moved = true
			u.movement_left = 0
			_add_notification(
				str(_db.get_unit(u.unit_type_id).get("name", u.unit_type_id.capitalize()))
					+ " spotted an enemy — explore cancelled.", "major")
			return
	# Collect candidate tiles: passable non-enemy-occupied neighbours.
	var candidates: Array = []
	for nb in _gs.map.neighbours8(u.x, u.y):
		var ter: Dictionary = _db.get_terrain(nb.terrain_id)
		# Skip impassable terrain and enemy-occupied tiles.
		if ter.get("impassable", false):
			continue
		if _db.get_unit(u.unit_type_id).get("domain", "land") == "land" \
				and ter.get("domain", "land") != "land":
			continue
		# Sea units obey the deep-water entry gate (§5): don't explore onto an
		# ocean tile this unit may not legally enter (avoids stalling on a move the
		# gated _cmd_move_stack would reject).
		if _db.get_unit(u.unit_type_id).get("domain", "land") == "sea" \
				and ter.get("landform", "") == "deep_water":
			var ectx: Dictionary = {
				"ocean_capable": bool(_db.get_unit(u.unit_type_id).get("ocean_capable", false)),
				"owner_id": player_id,
				"gs": _gs,
			}
			if not Pathfinding.can_enter_deep_water(nb, _db, ectx):
				continue
		# Border blocking (§7): don't explore into another player's territory the unit
		# may not legally enter (no war/alliance/open-borders) — the gated move would
		# be rejected, so steering there only wastes the scout's step.
		if not Pathfinding.border_passage_allowed(nb, player_id, _gs):
			continue
		# Never walk into an enemy: skip any tile that holds a hostile unit.
		var has_enemy: bool = false
		for eu2 in _gs.units:
			if eu2.x == nb.x and eu2.y == nb.y and eu2.owner_player_id != player_id:
				if eu2.owner_player_id == -2 or _gs.are_at_war(player_id, eu2.owner_player_id):
					has_enemy = true
					break
		if has_enemy:
			continue
		candidates.append(nb)
	if candidates.empty():
		u.is_exploring = false
		u.has_moved = true
		u.movement_left = 0
		_add_notification(
			str(_db.get_unit(u.unit_type_id).get("name", u.unit_type_id.capitalize()))
				+ " has nowhere to explore.", "info")
		return
	# Steer toward the nearest tile this player cannot currently see (fog / the
	# unexplored frontier), rather than wandering at random. `_explore_target`
	# BFS-finds that frontier tile from sim-visible knowledge; we then pick the
	# candidate neighbour that gets us closest to it. When the whole reachable map
	# is revealed it returns null and the scout idles instead of thrashing.
	var target: Tile = _explore_choose_step(u, player_id, candidates)
	if target == null:
		# Everything reachable is already revealed — stop exploring (idle) rather
		# than wander. The unit keeps its movement so the player can redirect it.
		u.is_exploring = false
		_add_notification(
			str(_db.get_unit(u.unit_type_id).get("name", u.unit_type_id.capitalize()))
				+ " has explored all it can reach.", "info")
		return
	var mc: Dictionary = {
		"type": IDs.CommandType.MOVE_STACK,
		"player_id": player_id,
		"from_x": u.x, "from_y": u.y,
		"to_x": target.x, "to_y": target.y,
		"unit_ids": [u.id]
	}
	_cmd_move_stack(mc)

# Pick which neighbour candidate an exploring unit should step onto so it heads
# toward unrevealed map. Returns null when no unseen tile is reachable at all
# (whole reachable map revealed), so the caller idles the scout instead of
# wandering.
#
# Algorithm:
#   * First confirm any reachable unseen tile still exists (`_explore_target`, a
#     deterministic BFS over legal terrain). If none does, the whole reachable map
#     is revealed → return null so the scout idles.
#   * Each candidate neighbour is scored by REVEAL — how many currently-unseen
#     tiles the candidate's own sight footprint would newly expose.
#   * HEADING COMMITMENT — an exploring unit keeps a persistent heading
#     (`explore_dx/dy`). If the tile one step along the current heading is still a
#     legal candidate that opens new fog, the unit stays the course (it does not
#     re-aim toward a fractionally-better neighbour). Only when the heading goes
#     stale (off-map, blocked, or revealing nothing new) does it re-aim toward the
#     (`Visibility.visible_tiles` footprint vs the player's current sight set,
#     `player_visible_tiles`). This is what stops an open-field scout ping-ponging
#     between two equally-fogged tiles: it commits to a line and walks it.
#   * Re-aim tiebreaks: more reveal first, then the candidate that best continues
#     the current heading (smallest turn), then stable (y, x).
# The chosen step's direction is written back to `explore_dx/dy`.
#
# Determinism: reads only sim-visible state (current per-player visibility, via
# the shared Visibility helper exactly like wild_forces / contact), never the
# scene fog layer, and uses no RNG — every tiebreak is a stable total order and
# the heading is serialized, so an explore turn is fully reproducible and survives
# save/load.
func _explore_choose_step(u: Unit, player_id: int, candidates: Array) -> Tile:
	var seen: Dictionary = player_visible_tiles(player_id)
	var domain: String = str(_db.get_unit(u.unit_type_id).get("domain", "land"))
	var ectx: Dictionary = {
		"ocean_capable": bool(_db.get_unit(u.unit_type_id).get("ocean_capable", false)),
		"owner_id": player_id,
		"gs": _gs,
	}
	# No reachable unseen tile anywhere ⇒ nothing left to explore.
	# Keep the frontier tile: when no neighbour opens fresh fog this turn, we steer
	# toward this reachable unseen tile so the scout makes progress instead of
	# ping-ponging along a coastline whose only unseen tiles lie across the water.
	var frontier: Tile = _explore_target(u, domain, ectx, seen)
	if frontier == null:
		return null
	var sight: int = _db.get_constant("unit_sight", 2)
	# Map each candidate's "x,y" → its reveal count (newly-unseen tiles in sight).
	var reveal_of: Dictionary = {}
	for c in candidates:
		var r: int = 0
		for vk in Visibility.visible_tiles(_gs.map, _db, c.x, c.y, sight):
			if not seen.has(vk):
				r += 1
		reveal_of[str(c.x) + "," + str(c.y)] = r
	# Heading commitment: if the tile one step along the current heading is still a
	# legal candidate that opens new fog, keep going straight.
	if u.explore_dx != 0 or u.explore_dy != 0:
		var hx: int = u.x + u.explore_dx
		var hy: int = u.y + u.explore_dy
		var hn: Array = _gs.map.normalize(hx, hy)
		var hkey: String = str(hn[0]) + "," + str(hn[1])
		for c in candidates:
			if c.x == hn[0] and c.y == hn[1] and int(reveal_of[hkey]) > 0:
				return c   # heading still productive — stay the course
	# Re-aim: pick the max-reveal candidate, tie-broken toward continuing the
	# current heading (smallest turn), then a stable (y, x) order.
	var best: Tile = null
	var best_reveal: int = -1
	var best_turn: int = 0x7FFFFFFF
	for c in candidates:
		var reveal: int = int(reveal_of[str(c.x) + "," + str(c.y)])
		var off: Array = _explore_offset(u.x, u.y, c.x, c.y)
		# Turn = how far this step deviates from the current heading (0 = straight).
		var turn: int = abs(off[0] - u.explore_dx) + abs(off[1] - u.explore_dy)
		var better: bool = false
		if reveal > best_reveal:
			better = true
		elif reveal == best_reveal:
			if turn < best_turn:
				better = true
			elif turn == best_turn and best != null \
					and (c.y < best.y or (c.y == best.y and c.x < best.x)):
				better = true
		if better:
			best_reveal = reveal
			best_turn = turn
			best = c
	# Coast-trap guard: when no candidate opens fresh fog this turn (best_reveal == 0),
	# the reveal+heading tiebreak has no sense of WHERE the reachable frontier lies, so
	# the scout can oscillate along a coastline whose only unseen tiles sit across water
	# it cannot enter. Instead steer toward the reachable BFS frontier tile: pick the
	# candidate that minimises wrap-aware distance to it (deterministic, no RNG), so the
	# scout walks the detour to genuinely reachable unexplored land.
	if best_reveal <= 0:
		var fbest: Tile = null
		var fbest_d: int = 0x7FFFFFFF
		for c in candidates:
			var d: int = _gs.map.distance(c.x, c.y, frontier.x, frontier.y)
			if d < fbest_d or (d == fbest_d and fbest != null \
					and (c.y < fbest.y or (c.y == fbest.y and c.x < fbest.x))):
				fbest_d = d
				fbest = c
		if fbest != null:
			best = fbest
	# Record the committed heading from the chosen step (signed unit step per axis).
	if best != null:
		var boff: Array = _explore_offset(u.x, u.y, best.x, best.y)
		u.explore_dx = boff[0]
		u.explore_dy = boff[1]
	return best

# Wrap-aware signed offset (dx, dy) from (ax, ay) to (bx, by): the shortest step
# along each axis, honouring map wrap so the offset geometry stays continuous
# across the east-west seam. Used to compare tile positions and headings locally.
func _explore_offset(ax: int, ay: int, bx: int, by: int) -> Array:
	var dx: int = bx - ax
	var dy: int = by - ay
	if _gs.map.wrap_x and abs(dx) * 2 > _gs.map.width:
		dx = dx - _gs.map.width if dx > 0 else dx + _gs.map.width
	if _gs.map.wrap_y and abs(dy) * 2 > _gs.map.height:
		dy = dy - _gs.map.height if dy > 0 else dy + _gs.map.height
	return [dx, dy]

# Authoritative set of "x,y" tile keys this player can currently see, from
# sim-visible state only. The single source of truth for current per-player
# visibility, consumed by the fog renderer, the explore mover, first contact and
# the wild spawn mask, so they all agree exactly. The union is:
#   * unit sight   — every owned unit through the terrain-aware Visibility helper
#   * city sight   — every owned settlement, likewise
#   * own territory — every tile the player culturally owns is always fully seen,
#                     regardless of terrain/LOS (you watch your own borders)
#   * a one-ring fringe one tile beyond that territory (width = the data-driven
#     `territory_vision_ring` constant, default 1), so a rival stepping up to your
#     border is seen even with no unit nearby
# This is additive (it unions with sight, never replacing it). Keys are
# map-normalized "x,y" (wrap-canonical), matching the Visibility / presence map.
# The scene fog layer's accumulated ever-seen memory is presentation-only and is
# NOT part of this — it must never be read back into sim logic.
func player_visible_tiles(player_id: int) -> Dictionary:
	# Single source of truth: the pure sight set computed in the sim layer (unit ∪
	# city ∪ owned territory ∪ ring fringe), shared with the turn pipeline's fog
	# memory commit so the rendered fog and the committed memory agree exactly.
	# city_visibility passive intel (§25.6) joins here — a live, presentation-side
	# reveal that is derived from current EP, so it never enters the committed
	# memory or the sim's own sight model.
	var seen: Dictionary = TurnEngine.player_visible_set(_gs, player_id)
	for key in _intel_visible_tiles(player_id):
		seen[key] = true
	return seen

# Persistent fog memory (§fog): the "x,y" → last-seen-snapshot map a player has
# accumulated, read by the scene fog layer / world view so revealed fog and
# remembered terrain survive save/load. Returns an empty Dictionary for a player
# with no recorded memory (e.g. an AI, which renders no fog).
func get_seen_memory(player_id: int) -> Dictionary:
	return SeenMemory.for_player(_gs, player_id)

# BFS outward from the unit over passable, domain-legal tiles to the nearest tile
# the player cannot currently see (`seen`). Returns that frontier Tile, or null
# when no unseen tile is reachable. The BFS expands in ring order and, within a
# ring, in a stable (y, x) order, so the chosen frontier is deterministic.
func _explore_target(u: Unit, domain: String, ectx: Dictionary, seen: Dictionary) -> Tile:
	var visited: Dictionary = {}
	var start_key: String = str(u.x) + "," + str(u.y)
	visited[start_key] = true
	var queue: Array = [_gs.map.get_tile(u.x, u.y)]
	while not queue.empty():
		var cur: Tile = queue.pop_front()
		# Expand neighbours in a stable order so ties resolve deterministically.
		var nbs: Array = _gs.map.neighbours8(cur.x, cur.y)
		nbs.sort_custom(self, "_tile_yx_less")
		for nb in nbs:
			var key: String = str(nb.x) + "," + str(nb.y)
			if visited.has(key):
				continue
			visited[key] = true
			# A tile the player cannot currently see is the frontier target — but
			# only if it is reachable terrain (so we never aim at an unreachable
			# ocean a land scout can't cross). Found the nearest unseen tile.
			if not _explore_tile_legal(nb, domain, ectx):
				continue
			if not seen.has(key):
				return nb
			# Seen and legal: keep walking outward through it.
			queue.append(nb)
	return null

# True if `tile` is passable terrain this unit's domain may legally stand on
# (mirrors the per-neighbour legality the explore step itself applies, including
# the §5 deep-water gate for sea units).
func _explore_tile_legal(tile: Tile, domain: String, ectx: Dictionary) -> bool:
	var ter: Dictionary = _db.get_terrain(tile.terrain_id)
	if ter.get("impassable", false):
		return false
	var tdomain: String = str(ter.get("domain", "land"))
	if domain == "land" and tdomain != "land":
		return false
	if domain == "sea" and tdomain == "land":
		return false
	if domain == "sea" and str(ter.get("landform", "")) == "deep_water":
		if not Pathfinding.can_enter_deep_water(tile, _db, ectx):
			return false
	return true

# Stable (y, x) ordering for deterministic BFS expansion.
func _tile_yx_less(a: Tile, b: Tile) -> bool:
	if a.y != b.y:
		return a.y < b.y
	return a.x < b.x

# Run explore steps for all exploring units owned by `player_id`. Called at
# the start of _cmd_end_turn so each exploring scout advances before the turn
# pipeline runs. Any scout woken by a sighted enemy has its notification added
# here too.
func _run_explore_missions(player_id: int) -> void:
	var ids: Array = []
	for u in _gs.units:
		if u.owner_player_id == player_id and u.is_exploring:
			ids.append(u.id)
	for uid in ids:
		var u: Unit = _gs.get_unit(uid)
		if u == null or not u.is_exploring:
			continue
		_explore_step(u)

func _cmd_do_control(cmd: Dictionary) -> bool:
	var ctrl_type: int = int(cmd.get("ctrl_type", -1))
	match ctrl_type:
		IDs.ControlType.NEXT_IDLE_UNIT:
			cycle_idle_units(false)
		IDs.ControlType.NEXT_IDLE_WORKER:
			cycle_idle_units(true)
		IDs.ControlType.NEXT_CITY:
			cycle_cities(true)
		IDs.ControlType.PREV_CITY:
			cycle_cities(false)
		IDs.ControlType.END_TURN, IDs.ControlType.FORCE_END_TURN:
			return _cmd_end_turn(int(cmd.get("player_id", _gs.current_player_id)))
		IDs.ControlType.OPEN_TECH, IDs.ControlType.OPEN_POLICY, \
		IDs.ControlType.OPEN_DIPLOMACY, IDs.ControlType.OPEN_FINANCE, \
		IDs.ControlType.OPEN_MILITARY, IDs.ControlType.OPEN_ESPIONAGE, \
		IDs.ControlType.OPEN_ENCYCLOPEDIA, IDs.ControlType.OPEN_CITY_SCREEN, \
		IDs.ControlType.OPEN_SAVE_LOAD, IDs.ControlType.QUICK_SAVE, \
		IDs.ControlType.QUICK_LOAD, IDs.ControlType.OPEN_MENU, \
		IDs.ControlType.TOGGLE_SCORE, IDs.ControlType.OPEN_RELIGION, \
		IDs.ControlType.OPEN_CORPORATION, IDs.ControlType.OPEN_TURN_LOG, \
		IDs.ControlType.OPEN_DOMESTIC_ADVISOR, \
		IDs.ControlType.OPEN_VICTORY_PROGRESS, IDs.ControlType.OPEN_OPTIONS, \
		IDs.ControlType.TOGGLE_MINIMAP, \
		IDs.ControlType.TOGGLE_FOG:
			emit_signal("screen_requested", ctrl_type)
	return true

# ── UI state queries ───────────────────────────────────────────────────────────

func get_dirty() -> DirtyFlags:
	return _dirty

func get_selection() -> SelectionState:
	return _selection

func select_unit(unit_id: int, do_clear: bool = true, toggle: bool = false) -> void:
	_selection.select_unit(unit_id, do_clear, toggle)
	_dirty.set_dirty(IDs.DirtyRegion.WORLD)
	_dirty.set_dirty(IDs.DirtyRegion.HUD_GROUPS)
	_dirty.set_dirty(IDs.DirtyRegion.DATA_PANES)

func select_city(city_id: int, raise_screen: bool = false) -> void:
	_selection.select_city(city_id, raise_screen)
	_dirty.set_dirty(IDs.DirtyRegion.WORLD)
	_dirty.set_dirty(IDs.DirtyRegion.HUD_GROUPS)
	_dirty.set_dirty(IDs.DirtyRegion.DATA_PANES)

# Select every unit the current player owns on a tile as one multi-unit
# selection (head = the first in spawn order). Lets the host issue an order to a
# whole stack at once. Returns the number of units selected.
func select_stack(tx: int, ty: int) -> int:
	_selection.clear()
	for u in _gs.units:
		if u.x == tx and u.y == ty and u.owner_player_id == _gs.current_player_id:
			_selection.select_unit(u.id, false, false)
	_dirty.set_dirty(IDs.DirtyRegion.WORLD)
	_dirty.set_dirty(IDs.DirtyRegion.HUD_GROUPS)
	_dirty.set_dirty(IDs.DirtyRegion.DATA_PANES)
	return _selection.selected_unit_ids.size()

func clear_selection() -> void:
	_selection.clear()
	_dirty.set_dirty(IDs.DirtyRegion.WORLD)
	_dirty.set_dirty(IDs.DirtyRegion.HUD_GROUPS)

# Can the given units (or the whole owned stack, when unit_ids is empty) reach
# (tx, ty) from (fx, fy)? True for a legal multi-turn route and for an adjacent
# enemy tile (entering it is an attack); false for impassable / wrong-domain
# tiles, so the host can treat an illegal click as "inspect" instead of a move.
func can_stack_move(fx: int, fy: int, tx: int, ty: int, unit_ids: Array = []) -> bool:
	if fx == tx and fy == ty:
		return false
	var movers: Array = _stack_movers(fx, fy, _gs.current_player_id, unit_ids)
	if movers.empty():
		return false
	# Spy infiltration (§7.1): an all-spy stack may move onto any city tile (own or
	# foreign, even garrisoned/at-war) as a peaceful relocation, so it bypasses the
	# combatant requirement below — mirroring _cmd_move_stack so UI and rules agree.
	if _is_spy_infiltration(movers, tx, ty):
		var spy_path: Array = Pathfinding.find_path(
			_gs.map, fx, fy, tx, ty, movers[0], _db, _gs.units, _gs.current_player_id, _gs)
		return not spy_path.empty()
	# Entering an enemy-held / hostile-city tile is an attack, so it is only a legal
	# target when at least one mover can actually fight. A civilian-only selection
	# (worker/settler/spy/…) right-clicking a hostile tile is therefore an illegal
	# target the host treats as "inspect", not a wasted strength-0 assault — this
	# mirrors the same gate in _cmd_move_stack so the UI and the rules agree (§5.3).
	if _enemy_settlement_at(tx, ty, _gs.current_player_id) != null \
			or Stack.get_defender(_gs.units, tx, ty, _gs.current_player_id, _gs) != null:
		var any_attacker: bool = false
		for mu in movers:
			if mu.can_attack(_db):
				any_attacker = true
				break
		if not any_attacker:
			return false
	var lead: Unit = movers[0]
	var path: Array = Pathfinding.find_path(
		_gs.map, fx, fy, tx, ty, lead, _db, _gs.units, _gs.current_player_id, _gs)
	return not path.empty()

# Is (tx, ty) a tile the current player would attack by entering it? True when it
# holds an enemy/wild city (owner -2 or one we are at war with) or an enemy/wild
# defender unit. Lets the input layer recognise an attack target so a right-click
# can route a combat-capable stack member into it (§5.3) without re-implementing
# the rules' hostility test.
func is_hostile_tile(tx: int, ty: int) -> bool:
	if _gs == null or _gs.map == null or not _gs.map.is_valid(tx, ty):
		return false
	if _enemy_settlement_at(tx, ty, _gs.current_player_id) != null:
		return true
	return Stack.get_defender(_gs.units, tx, ty, _gs.current_player_id, _gs) != null

# Mark an empty tile as the inspected subject: clears any unit/city selection and
# records the tile so the HUD can show a terrain readout (§UI bug: every tile is
# clickable; an unoccupied/illegal-target click shows terrain and drops the unit).
func inspect_tile(tx: int, ty: int) -> void:
	_selection.clear()
	_selection.inspected_tile = Vector2(tx, ty)
	_dirty.set_dirty(IDs.DirtyRegion.WORLD)
	_dirty.set_dirty(IDs.DirtyRegion.HUD_GROUPS)
	_dirty.set_dirty(IDs.DirtyRegion.DATA_PANES)

# Human-readable terrain readout for a tile (name, feature, resource, yields,
# movement cost, defence). The rules layer owns this text so it always matches
# the data tables (§9).
func tile_info_text(tx: int, ty: int) -> String:
	if _gs == null or _gs.map == null or not _gs.map.is_valid(tx, ty):
		return ""
	var tile: Tile = _gs.map.get_tile(tx, ty)
	if tile == null:
		return ""
	var ter: Dictionary = _db.get_terrain(tile.terrain_id)
	var lines: Array = []
	lines.append(str(ter.get("name", tile.terrain_id.capitalize())) \
		+ "  (" + str(tx) + ", " + str(ty) + ")")
	if tile.feature_id != "":
		lines.append("Feature: " + str(_db.get_feature(tile.feature_id).get("name", tile.feature_id.capitalize())))
	if tile.resource_id != "":
		lines.append("Resource: " + str(_db.get_resource(tile.resource_id).get("name", tile.resource_id.capitalize())))
	if tile.improvement_id != "":
		lines.append("Improvement: " + str(_db.get_improvement(tile.improvement_id).get("name", tile.improvement_id.capitalize())))
	# Full computed yield (terrain → feature → resource → improvement → transport),
	# from the perspective of the player viewing the tile, so a built improvement's
	# bonus (and resource yields it unlocks) show up in the readout, not just the
	# raw terrain base.
	var viewer: Player = _gs.get_player(_gs.current_player_id)
	var techs: Array = viewer.technologies if viewer != null else []
	var out: Array = TileOutput.compute(tile, _db, techs,
		_gs.map.tile_has_river(tile.x, tile.y))
	lines.append("Yields: " + str(out[IDs.Output.FOOD]) + "F " \
		+ str(out[IDs.Output.PRODUCTION]) + "P " \
		+ str(out[IDs.Output.COMMERCE]) + "C")
	lines.append("Move cost: " + str(int(ter.get("movement_cost", 100)) / 100) \
		+ "   Defence: +" + str(int(ter.get("defence_bonus", 0))) + "%")

	# Foreign cities and units on this tile (read-only; player may not own them).
	# A rival city shows only its defensive posture (§25.6 information fog) via
	# city_intel_lines; an alliance-mate's city stays fully readable.
	var rival_city_here: bool = false
	for s in _gs.settlements:
		if s.x == tx and s.y == ty and s.owner_player_id != _gs.current_player_id:
			var owner: Player = _gs.get_player(s.owner_player_id)
			if owner != null and viewer != null and owner.alliance_id == viewer.alliance_id:
				lines.append(owner.name + "'s city: " + s.name + "  (pop " + str(s.population) + ")")
				continue
			rival_city_here = true
			for intel_line in city_intel_lines(s.id):
				lines.append(intel_line)
	for u in _gs.units:
		if u.x == tx and u.y == ty and u.owner_player_id != _gs.current_player_id:
			# The garrison line of the rival-city intel block already covers these.
			if rival_city_here:
				continue
			# Foreign spies are invisible to everyone but their owner (§7.1).
			if _is_espionage_unit(u):
				continue
			var udata: Dictionary = _db.get_unit(u.unit_type_id)
			var uname: String = udata.get("name", u.unit_type_id.capitalize())
			var unit_label: String
			if u.owner_player_id == -2:
				# Wild/barbarian forces: animals show as "Wild <type>", raiders as "Bandit <type>"
				var cls: String = str(udata.get("classification", ""))
				if cls == "animal":
					unit_label = "Wild " + uname
				else:
					unit_label = "Bandit " + uname
			else:
				var owner: Player = _gs.get_player(u.owner_player_id)
				var owner_name: String = owner.name if owner != null else "?"
				unit_label = owner_name + "'s " + uname
			lines.append(unit_label + "  (HP " + str(u.health) + ")")

	return PoolStringArray(lines).join("\n")

# Net effective combat strength of a unit as it currently stands on its tile
# (§5.3): its base strength adjusted by the defensive modifiers that apply right
# now — terrain/feature defence bonus, entrenchment (fortify), defensive
# promotions, and the health-fraction scaling. Delegates to the same
# `Unit.effective_strength` the combat resolver uses (defender role), so the
# displayed number is honest. Returns an integer (this engine's strength scale is
# plain integer, not the Fixed 100-scale). Returns 0 for a non-combat / civilian
# unit (base_strength 0), so the UI can suppress the line.
func unit_effective_strength(unit_id: int) -> int:
	if _gs == null:
		return 0
	var u = _gs.get_unit(unit_id)
	if u == null or u.base_strength <= 0:
		return 0
	var tile: Tile = _gs.map.get_tile(u.x, u.y)
	if tile == null:
		return 0
	var ter: Dictionary = _db.get_terrain(tile.terrain_id)
	var feat: Dictionary = _db.get_feature(tile.feature_id) if tile.feature_id != "" else {}
	# Stationary defender: include the city's structure + cultural defence when the
	# unit garrisons one of its own settlements, mirroring the combat resolver.
	var settle: Settlement = _gs.get_settlement_at(u.x, u.y)
	var at_settlement: bool = settle != null
	var settle_def: int = 0
	if at_settlement:
		for sid in settle.structures:
			var st: Dictionary = _db.get_structure(sid)
			settle_def += int(st.get("defence_bonus", 0))
			settle_def += int(st.get("cultural_defence_bonus", 0))
	return u.effective_strength(_db, false, ter, feat, "",
		at_settlement, settle_def, false)

# Display string for a combat unit's strength line (§5.3 / Issue 4):
# "Strength: <base> (<effective> effective)". Returns "" for a non-combat unit so
# the selection panel can omit the line for civilians.
func unit_strength_text(unit_id: int) -> String:
	if _gs == null:
		return ""
	var u = _gs.get_unit(unit_id)
	if u == null or u.base_strength <= 0:
		return ""
	var eff: int = unit_effective_strength(unit_id)
	return "Strength: " + str(u.base_strength) + " (" + str(eff) + " effective)"

func cycle_idle_units(workers_only: bool = false) -> void:
	var idle: Array = []
	for u in _gs.units:
		if u.owner_player_id != _gs.current_player_id:
			continue
		if u.has_moved or u.is_fortified or u.is_sentry or u.is_patrolling \
				or u.is_healing or u.is_sleeping \
				or u.is_sleep_until_healed or u.is_fortify_until_healed \
				or u.is_exploring or u.building_improvement != "" \
				or u.clearing_feature != "":
			continue
		if workers_only and not _db.get_unit(u.unit_type_id).get("can_build", false):
			continue
		idle.append(u.id)
	if idle.empty():
		return
	var head: int = _selection.head_unit()
	var start_idx: int = 0
	if head >= 0:
		var idx: int = idle.find(head)
		if idx >= 0:
			start_idx = (idx + 1) % idle.size()
	_selection.select_unit(idle[start_idx], true, false)
	_dirty.set_dirty(IDs.DirtyRegion.HUD_GROUPS)
	_dirty.set_dirty(IDs.DirtyRegion.DATA_PANES)

func cycle_cities(forward: bool = true) -> void:
	var owned: Array = []
	for s in _gs.settlements:
		if s.owner_player_id == _gs.current_player_id:
			owned.append(s.id)
	if owned.empty():
		return
	var head: int = _selection.head_city()
	var start_idx: int = 0
	if head >= 0:
		var idx: int = owned.find(head)
		if idx >= 0:
			var delta: int = 1 if forward else -1
			start_idx = (idx + delta + owned.size()) % owned.size()
	_selection.select_city(owned[start_idx], false)
	_dirty.set_dirty(IDs.DirtyRegion.HUD_GROUPS)
	_dirty.set_dirty(IDs.DirtyRegion.DATA_PANES)

# ── Interface mode (§5) ───────────────────────────────────────────────────────

func get_interface_mode() -> int:
	return _interface_mode

func can_enter_mode(mode: int) -> bool:
	if mode == IDs.InterfaceMode.SELECTION:
		return true
	return _selection.head_unit() >= 0

func enter_interface_mode(mode: int) -> void:
	_interface_mode = mode
	_dirty.set_dirty(IDs.DirtyRegion.WORLD)

func exit_interface_mode() -> void:
	_interface_mode = IDs.InterfaceMode.SELECTION
	_dirty.set_dirty(IDs.DirtyRegion.WORLD)

func get_mode_tile_validity(x: int, y: int) -> int:
	if _gs.map == null:
		return 0
	if not _gs.map.is_valid(x, y):
		return 0
	match _interface_mode:
		IDs.InterfaceMode.SELECTION:
			return 1
		IDs.InterfaceMode.GO_TO, IDs.InterfaceMode.GO_TO_ALL, IDs.InterfaceMode.ROUTE_TO:
			return 1   # detailed reachability uses pathfinding at move time
		_:
			return 1

# ── Popup queue (§6) ──────────────────────────────────────────────────────────

func push_popup(descriptor: Dictionary) -> void:
	_popup_queue.append(descriptor)

func get_pending_popup() -> Dictionary:
	if _popup_queue.empty():
		return {}
	return _popup_queue[0]

func resolve_popup(result: Dictionary) -> void:
	if _popup_queue.empty():
		return
	_popup_queue.pop_front()

# ── Capability queries (§3, §10) ─────────────────────────────────────────────

func can_do_control(ctrl_type: int) -> bool:
	match ctrl_type:
		IDs.ControlType.END_TURN, IDs.ControlType.FORCE_END_TURN:
			return _gs.current_player_id >= 0
		IDs.ControlType.CENTER_ON_SELECTION:
			return _selection.head_unit() >= 0 or _selection.head_city() >= 0
		IDs.ControlType.NEXT_UNIT, IDs.ControlType.PREV_UNIT, \
		IDs.ControlType.NEXT_IDLE_UNIT, IDs.ControlType.NEXT_IDLE_WORKER:
			for u in _gs.units:
				if u.owner_player_id == _gs.current_player_id:
					return true
			return false
		IDs.ControlType.NEXT_CITY, IDs.ControlType.PREV_CITY:
			for s in _gs.settlements:
				if s.owner_player_id == _gs.current_player_id:
					return true
			return false
	return true  # screen toggles, hotkeys, etc. are always allowed

func can_handle_action(action_id: int, target_x: int, target_y: int) -> bool:
	if _selection.head_unit() < 0 and _selection.head_city() < 0:
		return false
	if _interface_mode != IDs.InterfaceMode.SELECTION:
		return false
	return true

# ── Display-gating queries (§10) ──────────────────────────────────────────────

func get_end_turn_state() -> int:
	# 0 = ready, 1 = waiting on others, 2 = idle units prompt
	# A remote client that has submitted its turn is waiting on the server.
	if _remote_waiting:
		return 1
	if _gs.current_player_id < 0:
		return 1
	for u in _gs.units:
		if u.owner_player_id == _gs.current_player_id and not u.has_moved \
				and not u.is_fortified and not u.is_sleeping \
				and not u.is_sleep_until_healed and not u.is_fortify_until_healed \
				and not u.is_exploring and u.building_improvement == "" \
				and u.clearing_feature == "":
			return 2
	return 0

func get_hud_visibility() -> Dictionary:
	return {
		"show_research": not _gs.players.empty(),
		"show_flag": not _gs.players.empty(),
		"show_minimap_center": _selection.head_unit() >= 0 or _selection.head_city() >= 0
	}

func get_tile_highlights() -> Dictionary:
	var highlights: Dictionary = {}
	var head_id: int = _selection.head_unit()
	if head_id < 0:
		return highlights
	var u: Unit = _gs.get_unit(head_id)
	if u == null:
		return highlights
	highlights[str(u.x) + "," + str(u.y)] = 0xFFFFFF
	return highlights

# Whether `unit_id` may legally found a settlement on the tile it currently stands
# on. The single source of truth for the founding rule, shared by the command
# handler (_cmd_found_settlement) and the UI (so the panel only offers "Found City"
# where it would actually succeed). Mirrors the handler's checks: the unit must be
# the current player's settler (can_found), the tile must be foundable land (not
# water, not a peak), and it must be at least min_settlement_distance from every
# existing settlement.
func can_found_settlement_at(unit_id: int) -> bool:
	var u: Unit = _gs.get_unit(unit_id)
	if u == null or u.owner_player_id != _gs.current_player_id:
		return false
	if not _db.get_unit(u.unit_type_id).get("can_found", false):
		return false
	if not _is_foundable_tile(u.x, u.y):
		return false
	var min_dist: int = _db.get_constant("min_settlement_distance", 2)
	for existing in _gs.settlements:
		if _gs.map.distance(u.x, u.y, existing.x, existing.y) < min_dist:
			return false
	return true

# A tile can host a new city only if it is land (a settler cannot found on
# water/coast) and not an impassable peak (mountain). Data-driven via the terrain
# domain/landform fields.
func _is_foundable_tile(x: int, y: int) -> bool:
	var tile = _gs.map.get_tile(x, y)
	if tile == null:
		return false
	var ter: Dictionary = _db.get_terrain(tile.terrain_id)
	if str(ter.get("domain", "land")) != "land":
		return false
	if str(ter.get("landform", "flat")) == "peak":
		return false
	return true

# Action list for one specific unit standing on its tile (§3.2/§3.3). This is the
# single builder the selection panel uses so the buttons always reflect the
# SELECTED unit (a settler in a mixed stack shows Found City; a garrisoned
# defender shows Fortify), not whichever unit happens to be first on the tile.
func get_unit_actions(unit_id: int) -> Array:
	var items: Array = []
	var u: Unit = _gs.get_unit(unit_id)
	if u == null or u.owner_player_id != _gs.current_player_id:
		return items
	# Each item carries a "kind" ("mission"/"cmd") alongside its action_id because
	# the UnitCmd and UnitMission enums share raw integer values (e.g. FORTIFY==2 and
	# SKIP_TURN==2): the kind disambiguates which command family the panel dispatches.
	# Found City: only when this settler may actually found here (foundable land,
	# far enough from other settlements).
	if can_found_settlement_at(u.id):
		items.append({
			"kind": "mission", "action_id": IDs.UnitMission.FOUND_SETTLEMENT,
			"label": "Found City",
			"unit_id": u.id,
			"target_x": u.x, "target_y": u.y
		})
	# Wake: surfaced when the unit is asleep so an idle-cycle-skipped unit can be
	# returned to active duty. Otherwise offer a plain Skip Turn for an unmoved unit.
	if u.is_sleeping:
		items.append({
			"kind": "cmd", "action_id": IDs.UnitCmd.WAKE,
			"label": "Wake",
			"target_x": u.x, "target_y": u.y
		})
	elif not u.has_moved:
		items.append({
			"kind": "mission", "action_id": IDs.UnitMission.SKIP_TURN,
			"label": "Skip Turn",
			"target_x": u.x, "target_y": u.y
		})
	# Fortify: only offered to land combat units (Issue 3), matching the sim gate
	# so the menu never lists an order the command would reject.
	if not u.is_fortified and u.can_fortify(_db):
		items.append({
			"kind": "cmd", "action_id": IDs.UnitCmd.FORTIFY,
			"label": "Fortify",
			"target_x": u.x, "target_y": u.y
		})
	# Sleep: a skip-until-woken order for any awake unit, distinct from Fortify
	# (no defence/heal intent) — removes the unit from the idle cycle until it is
	# woken or given another order.
	if not u.is_sleeping:
		items.append({
			"kind": "cmd", "action_id": IDs.UnitCmd.SLEEP,
			"label": "Sleep",
			"target_x": u.x, "target_y": u.y
		})
	return items

func get_flyout_menu(x: int, y: int) -> Array:
	var items: Array = []
	for u in _gs.units:
		if u.x == x and u.y == y and u.owner_player_id == _gs.current_player_id:
			items = get_unit_actions(u.id)
			break
	for s in _gs.settlements:
		if s.x == x and s.y == y and s.owner_player_id == _gs.current_player_id:
			items.append({
				"kind": "control", "action_id": IDs.ControlType.OPEN_CITY_SCREEN,
				"label": "Open City",
				"target_x": x, "target_y": y
			})
			break
	return items

# ── Widget dispatch (§4) ──────────────────────────────────────────────────────

func widget_help(widget: Dictionary) -> String:
	return TextGen.widget_help(widget, _gs, _db)

func widget_action(widget: Dictionary) -> bool:
	var wtype: int = int(widget.get("type", -1))
	match wtype:
		IDs.WidgetType.RESEARCH:
			var tech_id: String = str(widget.get("tech_id", ""))
			return apply_command(Commands.set_research(_gs.current_player_id, tech_id))
		IDs.WidgetType.RUSH_PRODUCTION:
			var city_id: int = int(widget.get("data1", -1))
			var method: String = str(widget.get("method", "treasury"))
			return apply_command(Commands.rush_production(_gs.current_player_id, city_id, method))
		IDs.WidgetType.CLOSE_SCREEN:
			emit_signal("screen_requested", -1)
			return true
	return false

func widget_alt_action(widget: Dictionary) -> bool:
	return false  # context-dependent; default no-op for Phase 6

func widget_is_link(widget: Dictionary) -> bool:
	var wtype: int = int(widget.get("type", -1))
	match wtype:
		IDs.WidgetType.ENCYCLOPEDIA, IDs.WidgetType.BACK, IDs.WidgetType.FORWARD:
			return true
	return false

# ── Notifications (§8) ────────────────────────────────────────────────────────

func get_notification_queue() -> Array:
	return _notifications

func _alliance_label(alliance_id: int) -> String:
	var a: Alliance = _gs.get_alliance(alliance_id)
	if a == null or a.member_player_ids.empty():
		return "another power"
	var p: Player = _gs.get_player(int(a.member_player_ids[0]))
	return p.name if p != null else "another power"

func _add_notification(text: String, category: String = "info") -> void:
	_notifications.append({"text": text, "category": category, "turn": _gs.turn_number})
	if _notifications.size() > 100:
		_notifications.pop_front()
	_dirty.set_dirty(IDs.DirtyRegion.DATA_PANES)

# Surface any cultural-flip records the §4.9 revolt phase produced this player
# step: one notification + a city_flipped signal each, then clear the queue.
func _drain_flips() -> void:
	if _gs.pending_flips.empty():
		return
	for f in _gs.pending_flips:
		var city: Settlement = _gs.get_settlement(int(f["settlement_id"]))
		var nm: String = city.name if city != null else "A city"
		_add_notification(nm + " has defected through cultural pressure!", "major")
		emit_signal("city_flipped", f["settlement_id"],
			f["from_player_id"], f["to_player_id"])
	_gs.pending_flips = []
	_dirty.set_dirty(IDs.DirtyRegion.WORLD)
	_dirty.set_dirty(IDs.DirtyRegion.DATA_PANES)
	_dirty.set_dirty(IDs.DirtyRegion.HUD_GROUPS)

# Surface any era advancements queued during the player step (§1): one notification
# + an era_advanced signal each, then clear the queue.
func _drain_era_advances() -> void:
	if _gs.pending_era_advances.empty():
		return
	for adv in _gs.pending_era_advances:
		var pid: int = int(adv["player_id"])
		var to_era: int = int(adv["to"])
		var p: Player = _gs.get_player(pid)
		var who: String = p.name if p != null else "A civilization"
		_add_notification(
			who + " has entered the " + Eras.era_name(to_era, _db) + " Era.", "major")
		emit_signal("era_advanced", pid, int(adv["from"]), to_era)
	_gs.pending_era_advances = []
	_dirty.set_dirty(IDs.DirtyRegion.HUD_GROUPS)
	_dirty.set_dirty(IDs.DirtyRegion.DATA_PANES)

# Surface any wild-forces combat/conquest records WildAI produced this world step
# (§9): each fight re-emits combat_resolved; each razed city clears a stale
# selection, notifies, and emits city_razed. Then clear the queue.
func _drain_wild_events() -> void:
	if _gs.pending_wild_events.empty():
		return
	for e in _gs.pending_wild_events:
		match e["kind"]:
			"combat":
				emit_signal("combat_resolved", e["result"])
				# Notify any player whose unit was killed by a wild attacker.
				var def_owner: int = int(e.get("defender_owner_id", -1))
				if def_owner >= 0 and not bool(e["result"].get("defender_survived", true)):
					var def_type: String = str(e.get("defender_type_id", ""))
					var def_name: String = str(_db.get_unit(def_type).get("name", def_type))
					var dx: int = int(e.get("defender_x", -1))
					var dy: int = int(e.get("defender_y", -1))
					var p_owner: Player = _gs.get_player(def_owner)
					var owner_label: String = (p_owner.name + "'s") if p_owner != null else "A"
					_add_notification(owner_label + " " + def_name + " was killed by wild forces at ("
						+ str(dx) + "," + str(dy) + ").", "major")
			"razed":
				var sid: int = int(e["settlement_id"])
				if _selection != null and _selection.head_city() == sid:
					_selection.clear()
				_add_notification(str(e["name"]) + " was razed by raiders.", "major")
				emit_signal("city_razed", sid, -2)
	_gs.pending_wild_events = []
	_dirty.set_dirty(IDs.DirtyRegion.WORLD)
	_dirty.set_dirty(IDs.DirtyRegion.DATA_PANES)
	_dirty.set_dirty(IDs.DirtyRegion.HUD_GROUPS)

# Surface any first-contact records produced this world step (§7): the first time
# two players meet, notify each side (naming the other) and emit a first_contact
# signal each, then clear the queue. The records are per-direction already.
func _drain_first_contacts() -> void:
	if _gs.pending_first_contacts.empty():
		return
	for fc in _gs.pending_first_contacts:
		var pid: int = int(fc["player_id"])
		var other_id: int = int(fc["other_player_id"])
		var other: Player = _gs.get_player(other_id)
		var who: String = other.name if (other != null and other.name != "") \
			else "another civilization"
		_add_notification("You have made contact with " + who + ".", "major")
		emit_signal("first_contact", pid, other_id)
	_gs.pending_first_contacts = []
	_dirty.set_dirty(IDs.DirtyRegion.DATA_PANES)
	_dirty.set_dirty(IDs.DirtyRegion.HUD_GROUPS)

# Surface any diplomatic-assembly records produced this world step (§7.2): a
# notification + an assembly_event signal for each opened session and resolved
# proposal. Then clear the queue.
func _drain_assembly_events() -> void:
	if _gs.pending_assembly_events.empty():
		return
	for e in _gs.pending_assembly_events:
		match str(e.get("kind", "")):
			"session_opened":
				_add_notification("The assembly convenes: " + str(e.get("name", "")) + ".", "major")
			"resolution_resolved":
				var verb: String = "passed" if bool(e.get("passed", false)) else "failed"
				_add_notification("Assembly motion " + verb + ": " + str(e.get("name", "")) + ".", "major")
		emit_signal("assembly_event", e)
	_gs.pending_assembly_events = []
	_dirty.set_dirty(IDs.DirtyRegion.DATA_PANES)
	_dirty.set_dirty(IDs.DirtyRegion.HUD_GROUPS)

# Surface the persistent-deal lifecycle records produced this world step (§7): a
# notification + a deal_cancelled signal for each deal that expired (a party went
# away or the two alliances went to war) or was cancelled. Then clear the queue.
func _drain_deal_events() -> void:
	if _gs.pending_deal_events.empty():
		return
	for e in _gs.pending_deal_events:
		match str(e.get("kind", "")):
			"deal_expired":
				_add_notification("A standing deal has lapsed.", "info")
				emit_signal("deal_cancelled", e)
			"deal_cancelled":
				_add_notification("A standing deal was cancelled.", "info")
				emit_signal("deal_cancelled", e)
			"deal_rejected":
				# §7 denial reasons: tell the proposer *why* the offer was refused,
				# with the display text from the diplomacy.json denial table.
				var rejector: Player = _gs.get_player(int(e.get("rejector_player_id", -1)))
				var proposer: Player = _gs.get_player(int(e.get("proposer_player_id", -1)))
				var rej_nm: String = rejector.name if rejector != null else "A rival"
				var pro_nm: String = proposer.name if proposer != null else "a rival"
				_add_notification(rej_nm + " refused " + pro_nm + "'s offer: "
					+ Diplomacy.denial_text(_db, str(e.get("reason", ""))), "info")
			"vassal_liberated":
				# §7 vassalage: a vassal grew strong enough to break free of its
				# overlord (Vassalage.world_tick), or an overlord released it.
				_add_notification(_alliance_label(int(e.get("alliance_id", -1)))
					+ " broke free of " + _alliance_label(int(e.get("overlord_alliance_id", -1)))
					+ ".", "major")
	_gs.pending_deal_events = []
	_dirty.set_dirty(IDs.DirtyRegion.DATA_PANES)

# Surface the random-event records produced this player step (§9): a notification
# + an event_emitted signal for each fired/expired event. Then clear the queue.
# (A human's pending CHOICE is surfaced separately as a popup; it is not drained
# here so the prompt persists until resolved.)
func _drain_events() -> void:
	if _gs.pending_events.empty():
		return
	for e in _gs.pending_events:
		var nm: String = str(e.get("name", e.get("event_id", "")))
		match str(e.get("kind", "")):
			"event_fired":
				_add_notification("Event: " + nm + ".", "major")
			"event_choice_pending":
				_add_notification("Event awaiting your decision: " + nm + ".", "major")
			"event_expired":
				_add_notification("Event ended: " + nm + ".", "info")
		emit_signal("event_emitted", e)
	_gs.pending_events = []
	_dirty.set_dirty(IDs.DirtyRegion.DATA_PANES)
	_dirty.set_dirty(IDs.DirtyRegion.HUD_GROUPS)

# Surface quest-lifecycle records produced during the quest player-step (§4): one
# notification + a quest_event signal each, then clear the queue. A reward-pending quest
# parked a non-skippable choice into pending_event_choices under a "quest:<id>" event_id;
# the event-choice popup (TurnPrompts → get_pending_event) raises it at the player's
# next turn start, exactly like a random-event choice.
func _drain_quest_events() -> void:
	if _gs.pending_quest_events.empty():
		return
	for q in _gs.pending_quest_events:
		var nm: String = str(q.get("name", q.get("quest_id", "")))
		match str(q.get("kind", "")):
			"quest_armed":
				# Surface the quest's full flavour description and its concrete
				# objective when it starts (§4) — the data rides on the descriptor.
				var line: String = "New quest — " + nm
				var desc: String = str(q.get("text", ""))
				if desc != "":
					line += ": " + desc
				var obj: String = str(q.get("objective", ""))
				if obj != "":
					line += "  Objective: " + obj
				_add_notification(line, "major")
				_enqueue_quest_info(q)
			"quest_completed":
				_add_notification("Quest complete: " + nm + ".", "major")
			"quest_reward_pending":
				_add_notification("Quest complete — choose your reward: " + nm + ".", "major")
			"quest_failed":
				_add_notification("Quest failed: " + nm + ".", "info")
		emit_signal("quest_event", q)
	_gs.pending_quest_events = []
	_dirty.set_dirty(IDs.DirtyRegion.DATA_PANES)
	_dirty.set_dirty(IDs.DirtyRegion.HUD_GROUPS)

# Queue an informational popup for a quest freshly armed for a HUMAN player (§4),
# carrying its description, objective and reward summary. AI players never queue one.
# Transient (not serialized); surfaced once by TurnPrompts at the owner's turn start.
func _enqueue_quest_info(q: Dictionary) -> void:
	var pid: int = int(q.get("player_id", -1))
	var pl: Player = _gs.get_player(pid)
	if pl == null or pl.is_ai:
		return
	var quest: Dictionary = _db.get_quest(str(q.get("quest_id", "")))
	_quest_info_popups.append({
		"player_id": pid,
		"quest_id": str(q.get("quest_id", "")),
		"name": str(q.get("name", "")),
		"text": str(q.get("text", "")),
		"objective": str(q.get("objective", "")),
		"reward_lines": _quest_reward_lines(quest)
	})

# Human-readable reward summary lines for a quest's reward block (§4): the choice
# texts for a multi-choice reward, else the reward's own flavour text.
func _quest_reward_lines(quest: Dictionary) -> Array:
	var reward: Dictionary = quest.get("reward", {})
	var lines: Array = []
	var choices: Array = reward.get("choices", [])
	if not choices.empty():
		lines.append(str(reward.get("text", "On completion, choose a reward:")))
		for ch in choices:
			lines.append("• " + str(ch.get("text", "")))
	else:
		var t: String = str(reward.get("text", ""))
		lines.append(t if t != "" else "Completing this quest grants a reward.")
	return lines

# The first unacknowledged armed-quest info popup owed to a player (§4), or {}.
func get_pending_quest_info(player_id: int) -> Dictionary:
	for info in _quest_info_popups:
		if int(info.get("player_id", -1)) == player_id:
			return info
	return {}

# Drop the armed-quest info popup for (player, quest) once it has been shown (§4).
func ack_quest_info(player_id: int, quest_id: String) -> void:
	for i in range(_quest_info_popups.size()):
		var info: Dictionary = _quest_info_popups[i]
		if int(info.get("player_id", -1)) == player_id \
				and str(info.get("quest_id", "")) == quest_id:
			_quest_info_popups.remove(i)
			return

# The first unresolved event choice owed by a player (§9), or {} when none. Mirrors
# get_pending_vote: lets presentation re-raise the prompt after a load.
func get_pending_event(player_id: int) -> Dictionary:
	for pc in _gs.pending_event_choices:
		if int(pc.get("player_id", -1)) == player_id:
			return pc
	return {}

# Resolve a human's random-event choice (§9): apply the chosen branch, clear the
# pending entry, and pop the matching popup. Effects are fixed-value, so applying
# here draws no RNG and stays deterministic regardless of when the human answers.
func _cmd_resolve_event(cmd: Dictionary) -> bool:
	var player_id: int = int(cmd["player_id"])
	var event_id: String = str(cmd.get("event_id", ""))
	var choice_id: String = str(cmd.get("choice_id", ""))
	var idx: int = -1
	for i in range(_gs.pending_event_choices.size()):
		var pc: Dictionary = _gs.pending_event_choices[i]
		if int(pc.get("player_id", -1)) == player_id and str(pc.get("event_id", "")) == event_id:
			idx = i
			break
	if idx < 0:
		return false
	var player: Player = _gs.get_player(player_id)
	if player == null or not Events.apply_choice(event_id, choice_id, player, _gs):
		return false
	_gs.pending_event_choices.remove(idx)
	var ev: Dictionary = _db.get_event(event_id)
	_add_notification("Event resolved: " + str(ev.get("name", event_id)) + ".", "major")
	_dirty.set_dirty(IDs.DirtyRegion.DATA_PANES)
	_dirty.set_dirty(IDs.DirtyRegion.HUD_GROUPS)
	_dirty.set_dirty(IDs.DirtyRegion.WORLD)
	return true

# Surface technology-completion records queued during a player step: one
# notification + a technology_completed signal each, then clear the queue.
func _drain_tech_completions() -> void:
	if _gs.pending_tech_completions.empty():
		return
	for entry in _gs.pending_tech_completions:
		var pid: int = int(entry["player_id"])
		var tech_id: String = str(entry["tech_id"])
		var p: Player = _gs.get_player(pid)
		var who: String = p.name if p != null else "A civilization"
		var tech_name: String = str(_db.get_technology(tech_id).get("name", tech_id))
		_add_notification(who + " discovered " + tech_name + ".", "major")
		emit_signal("technology_completed", pid, tech_id)
	_gs.pending_tech_completions = []
	_dirty.set_dirty(IDs.DirtyRegion.DATA_PANES)
	_dirty.set_dirty(IDs.DirtyRegion.HUD_GROUPS)

# Surface great-person birth records queued during a player/world step: one
# notification each, then clear the queue.
func _drain_great_people() -> void:
	if _gs.pending_great_people.empty():
		return
	for entry in _gs.pending_great_people:
		var pid: int = int(entry["player_id"])
		var unit_type: String = str(entry["unit_type_id"])
		var p: Player = _gs.get_player(pid)
		var who: String = p.name if p != null else "A civilization"
		var gp_name: String = str(_db.get_unit(unit_type).get("name", unit_type))
		_add_notification(who + " produced a " + gp_name + "!", "major")
	_gs.pending_great_people = []
	_dirty.set_dirty(IDs.DirtyRegion.DATA_PANES)
	_dirty.set_dirty(IDs.DirtyRegion.HUD_GROUPS)

# Surface wonder/project-completion records queued during a player step: one
# notification each, then clear the queue.
func _drain_productions() -> void:
	if _gs.pending_productions.empty():
		return
	for entry in _gs.pending_productions:
		var pid: int = int(entry["player_id"])
		var p: Player = _gs.get_player(pid)
		var who: String = p.name if p != null else "A civilization"
		var city: String = str(entry.get("settlement_name", ""))
		var item_name: String = str(entry.get("item_name", ""))
		if str(entry.get("item_type", "")) == "project":
			_add_notification(who + " completed a project stage: " + item_name + ".", "major")
		else:
			_add_notification(who + " built " + item_name + " in " + city + "!", "major")
	_gs.pending_productions = []
	_dirty.set_dirty(IDs.DirtyRegion.DATA_PANES)
	_dirty.set_dirty(IDs.DirtyRegion.HUD_GROUPS)

# Surface city-growth records queued during a player step: one notification each,
# then clear the queue.
func _drain_growth_events() -> void:
	if _gs.pending_growth.empty():
		return
	for entry in _gs.pending_growth:
		var city: String = str(entry.get("settlement_name", ""))
		var pop: int = int(entry.get("population", 0))
		_add_notification(city + " grew to population " + str(pop) + "!", "major")
	_gs.pending_growth = []
	_dirty.set_dirty(IDs.DirtyRegion.DATA_PANES)
	_dirty.set_dirty(IDs.DirtyRegion.HUD_GROUPS)

# Surface completed worker improvement builds (§5) as notifications for the
# current player, and repaint the world so the new improvement renders.
func _drain_improvement_completions() -> void:
	if _gs.pending_improvements.empty():
		return
	for entry in _gs.pending_improvements:
		if int(entry.get("player_id", -1)) == _gs.current_player_id:
			var loc: String = "(" + str(int(entry.get("x", 0))) + ", " \
				+ str(int(entry.get("y", 0))) + ")"
			var cleared: String = str(entry.get("cleared_feature", ""))
			var feat_name: String = str(_db.get_feature(cleared).get("name", cleared.capitalize())) \
				if cleared != "" else ""
			var chop: int = int(entry.get("chop_yield", 0))
			var imp_id: String = str(entry.get("improvement_id", ""))
			var msg: String
			if imp_id == "":
				# A standalone chop/clear order (§4.11): no improvement was placed.
				msg = feat_name + " cleared at " + loc
				if chop > 0:
					msg += " (+" + str(chop) + " production)"
				msg += "."
			else:
				var imp_name: String = str(_db.get_improvement(imp_id).get("name", imp_id.capitalize()))
				msg = imp_name + " completed at " + loc + "."
				# A cleared feature, and any chop production it sent to a city, are
				# appended so the felled forest is visible in the log.
				if cleared != "":
					msg += " " + feat_name + " cleared"
					if chop > 0:
						msg += " (+" + str(chop) + " production)"
					msg += "."
			_add_notification(msg, "info")
	_gs.pending_improvements = []
	_dirty.set_dirty(IDs.DirtyRegion.WORLD)
	_dirty.set_dirty(IDs.DirtyRegion.HUD_GROUPS)

# Compose a brief combat notification from the attacker and defender units.
# When the defender is the current player's unit and was killed, a distinct
# "Your X was killed" notification is added so losses are always visible.
func _add_combat_notification(attacker: Unit, defender: Unit, result: Dictionary) -> void:
	var atk_name: String = str(_db.get_unit(attacker.unit_type_id).get("name", attacker.unit_type_id))
	var def_name: String = str(_db.get_unit(defender.unit_type_id).get("name", defender.unit_type_id))
	var outcome: String
	if not bool(result.get("attacker_survived", true)):
		outcome = atk_name + " was destroyed attacking " + def_name + "."
		# Current player's unit killed while attacking
		if attacker.owner_player_id == _gs.current_player_id:
			_add_notification("Your " + atk_name + " was killed at ("
				+ str(defender.x) + "," + str(defender.y) + ").", "major")
			return
	elif not bool(result.get("defender_survived", true)):
		outcome = atk_name + " defeated " + def_name + "."
		# Current player's unit killed while defending
		if defender.owner_player_id == _gs.current_player_id:
			_add_notification("Your " + def_name + " was killed at ("
				+ str(defender.x) + "," + str(defender.y) + ").", "major")
			return
	else:
		outcome = atk_name + " attacked " + def_name + " — both survived."
	_add_notification(outcome, "info")

# Push a CHOOSE_ELECTION popup for a human player who is an eligible member of an
# open assembly session and has not yet voted (§7.2). AI players vote through
# PlayerAI.manage_assembly instead, so they never see a popup.
func _maybe_raise_vote_popup(player_id: int) -> void:
	var p: Player = _gs.get_player(player_id)
	if p == null or p.is_ai:
		return
	if not Assembly.has_open_session(_gs) or Assembly.has_voted(_gs, player_id):
		return
	var body: String = str(_gs.assembly.get("kind", ""))
	if not Assembly.is_member(_gs, p, body):
		return
	var pending: Dictionary = Assembly.pending_proposal(_gs)
	# Carry the candidate slate so the ballot can offer a runoff choice (a supreme-
	# leadership motion has 1–2 candidates; other proposals carry none / one).
	var candidates: Array = []
	for c in pending.get("candidates", []):
		var cp: Player = _gs.get_player(int(c))
		candidates.append({"id": int(c), "name": (cp.name if cp != null else "")})
	push_popup({
		"type": IDs.PopupType.CHOOSE_ELECTION,
		"player_id": player_id,
		"resolution_id": str(pending.get("resolution_id", "")),
		"name": str(pending.get("name", "")),
		"text": str(pending.get("text", "")),
		"candidates": candidates
	})

func _cmd_cast_vote(cmd: Dictionary) -> bool:
	var ok: bool = Assembly.cast_vote(_gs, int(cmd["player_id"]), str(cmd.get("choice", "")))
	if ok:
		_dirty.set_dirty(IDs.DirtyRegion.DATA_PANES)
		_dirty.set_dirty(IDs.DirtyRegion.HUD_GROUPS)
	return ok
