# Humanish — a turn-based 4X strategy game.
# Copyright (C) 2026 thalia-at-lesbos
# SPDX-License-Identifier: GPL-3.0-or-later
#
# This program is free software: you can redistribute it and/or modify it
# under the terms of the GNU General Public License as published by the Free
# Software Foundation, either version 3 of the License, or (at your option)
# any later version. See the LICENSE file for the full text and warranty
# disclaimer.

extends "res://tests/support/sim_fixture.gd"

# The override-hook seam (§3/§13.11): a registered hook that handles a phase
# replaces the built-in rule, while one that declines lets it run. This is the
# mechanism content packs/mods use to swap any phase — exercised here against the
# WORLD_INCREMENT_TURN phase, whose built-in advances `turn_number`.

func _always_handle(_gs, _args) -> bool:
	return true

func _never_handle(_gs, _args) -> bool:
	return false

# ── run() contract ───────────────────────────────────────────────────────────

func test_run_returns_false_when_no_hook_registered() -> void:
	assert_false(hooks().run(IDs.Phase.WORLD_SPAWN_WILD, make_gs(1)),
		"An unhooked phase reports unhandled so the built-in runs")

func test_run_returns_true_when_a_hook_handles() -> void:
	var h = hooks()
	h.register(IDs.Phase.WORLD_SPAWN_WILD, self, "_always_handle")
	assert_true(h.run(IDs.Phase.WORLD_SPAWN_WILD, make_gs(1)),
		"A hook returning true marks the phase handled")

func test_run_returns_false_when_hook_declines() -> void:
	var h = hooks()
	h.register(IDs.Phase.WORLD_SPAWN_WILD, self, "_never_handle")
	assert_false(h.run(IDs.Phase.WORLD_SPAWN_WILD, make_gs(1)),
		"A hook returning false leaves the phase unhandled")

# ── Built-in suppression in the pipeline ───────────────────────────────────────

func test_handling_hook_skips_builtin_phase() -> void:
	var gs = make_gs(2)
	var h = hooks()
	h.register(IDs.Phase.WORLD_INCREMENT_TURN, self, "_always_handle")
	var before: int = gs.turn_number
	TurnEngine.world_step(gs, h)
	assert_eq(gs.turn_number, before,
		"A hook that handles WORLD_INCREMENT_TURN suppresses the built-in increment")

func test_declining_hook_lets_builtin_run() -> void:
	var gs = make_gs(2)
	var h = hooks()
	h.register(IDs.Phase.WORLD_INCREMENT_TURN, self, "_never_handle")
	var before: int = gs.turn_number
	TurnEngine.world_step(gs, h)
	assert_eq(gs.turn_number, before + 1, "A declining hook lets the built-in increment run")

func test_unregister_all_restores_builtin() -> void:
	var gs = make_gs(2)
	var h = hooks()
	h.register(IDs.Phase.WORLD_INCREMENT_TURN, self, "_always_handle")
	h.unregister_all(IDs.Phase.WORLD_INCREMENT_TURN)
	var before: int = gs.turn_number
	TurnEngine.world_step(gs, h)
	assert_eq(gs.turn_number, before + 1, "After unregister the built-in phase runs again")
