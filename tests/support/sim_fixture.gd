# Humanish — a turn-based 4X strategy game.
# Copyright (C) 2026 thalia-at-lesbos
# SPDX-License-Identifier: GPL-3.0-or-later
#
# This program is free software: you can redistribute it and/or modify it
# under the terms of the GNU General Public License as published by the Free
# Software Foundation, either version 3 of the License, or (at your option)
# any later version. See the LICENSE file for the full text and warranty
# disclaimer.

extends "res://addons/gut/test.gd"

# Shared fixtures for the headless engine suites (core/world/sim/api).
#
# Test files under tests/ extend this instead of GUT's test.gd directly, so the
# game-state/unit/settlement/facade scaffolding lives in one place. This file is
# NOT collected by GUT itself — the runner only picks up files named `test_*`.
#
# Helper functions deliberately omit return-type annotations: a `-> GameState`
# style hint forces an early parse of the class_name global and trips Godot 3's
# cyclic-reference checker (see CLAUDE.md).

# ── Data + state ───────────────────────────────────────────────────────────────

func make_db():
	var db = load("res://src/core/data_db.gd").new()
	db.load_all()
	return db

# A bare game state: a flat grassland map, `num_players` players each in their own
# single-member alliance (player N has id N and alliance id N), and a seeded RNG.
# Several tests mutate `gs.db` (injecting unit/structure types), so each state owns
# a fresh DataDB to keep them isolated.
func make_gs(num_players = 2, seed_val = 42, w = 20, h = 20):
	var gs = load("res://src/sim/game_state.gd").new()
	gs.db = make_db()
	gs.rng = load("res://src/core/rng.gd").new()
	gs.rng.init(seed_val)
	gs.map = load("res://src/world/world_map.gd").new()
	gs.map.init(w, h, false, false)
	for tile in gs.map.all_tiles():
		tile.terrain_id = "grassland"
	gs.pace_id = "normal"
	gs.difficulty_id = "prince"
	for i in range(num_players):
		var pid = i + 1
		var p = load("res://src/sim/player.gd").new()
		p.id = pid
		p.name = "P%d" % pid
		p.alliance_id = pid
		gs.players.append(p)
		var a = load("res://src/sim/alliance.gd").new()
		a.id = pid
		a.add_member(pid)
		gs.alliances.append(a)
	return gs

func hooks():
	return load("res://src/sim/hooks.gd").new()

# ── Units ────────────────────────────────────────────────────────────────────

# A data-driven unit: strength/movement come from units.json for `type_id`.
func make_unit(gs, type_id, player_id, x, y):
	var u = load("res://src/sim/unit.gd").new()
	u.id = gs.next_unit_id()
	u.unit_type_id = type_id
	u.owner_player_id = player_id
	u.x = x
	u.y = y
	var ud = gs.db.get_unit(type_id)
	u.base_strength = int(ud.get("base_strength", 5))
	u.health = 100
	u.movement_total = int(ud.get("movement", 200))
	u.movement_left = u.movement_total
	gs.units.append(u)
	return u

# A plain strength-10 warrior with two movement points — the canonical combatant
# the combat/movement tests reason about regardless of data tuning.
func make_warrior(gs, player_id, x, y, wild = false):
	var u = load("res://src/sim/unit.gd").new()
	u.id = gs.next_unit_id()
	u.unit_type_id = "warrior"
	u.owner_player_id = player_id
	u.x = x
	u.y = y
	u.base_strength = 10
	u.health = 100
	u.movement_total = 200
	u.movement_left = 200
	u.is_wild = wild
	gs.units.append(u)
	return u

func make_gp(gs, type_id, player_id, x, y):
	return GreatPeople.spawn_unit(gs, type_id, player_id, x, y)

# ── Settlements ────────────────────────────────────────────────────────────────

func make_settlement(gs, player_id, x, y, pop = 1):
	var s = load("res://src/sim/settlement.gd").new()
	s.id = gs.next_settlement_id()
	s.owner_player_id = player_id
	s.x = x
	s.y = y
	s.population = pop
	gs.settlements.append(s)
	return s

# ── Facade ───────────────────────────────────────────────────────────────────

# Wrap an existing game state in a facade without running setup() — for exercising
# command handlers (`_cmd_*`) and combat application against a hand-built state.
# `_hooks` is initialized to a real (empty) Hooks registry, exactly as production
# setup()/init_for_load() do, so a command that drives the turn pipeline
# (end_turn → world_step/player_step, which call hooks.run()) works instead of
# raising a "Nonexistent function 'run' in base 'Nil'" error that GUT swallows.
func bare_facade(gs):
	var f = load("res://src/api/sim_facade.gd").new()
	f._gs = gs
	f._db = gs.db
	f._dirty = load("res://src/api/dirty_flags.gd").new()
	f._hooks = hooks()
	return f

# A fully set-up facade via the real new-game path. Defaults to two society-less
# players on a tiny map; pass `players`/`win` to vary the scenario.
func setup_facade(seed_val = 1234, size = "tiny", players = null, win = null, difficulty = "warlord"):
	if players == null:
		players = [
			{"name": "Alice", "leader_id": "", "traits": [], "starting_gold": 50},
			{"name": "Bob", "leader_id": "", "traits": [], "starting_gold": 50}
		]
	if win == null:
		win = ["last_standing", "time"]
	var f = load("res://src/api/sim_facade.gd").new()
	f.setup(make_db(), seed_val, size, "normal", difficulty, players, win)
	return f

# Drive `n` whole rounds of end-turns through the facade (every living player ends
# their turn each round), stopping early once the game has been won.
func run_turns(facade, n):
	var gs = facade.get_state()
	for _t in range(n):
		if gs.winning_alliance_id >= 0:
			return
		for p in gs.players:
			if p.is_eliminated:
				continue
			gs.current_player_id = p.id
			facade.apply_command(Commands.end_turn(p.id))
