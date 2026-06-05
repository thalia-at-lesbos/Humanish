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

# Exercises the advanced-debugging core: the pure DebugLog ring buffer and the
# DebugConsole command engine (the shared engine behind both the terminal reader
# and the '~' overlay). The Node-based surfaces (overlay/terminal) are thin and
# scene-only; the testable logic all lives here.

# A bare facade armed with a Hooks registry so commands that route through the
# turn pipeline (war/peace/endturn) work against a hand-built state.
func dbg_facade(gs):
	var f = bare_facade(gs)
	f._hooks = hooks()
	return f

func make_console(gs, log_ref = null):
	var c = DebugConsole.new()
	c.init(dbg_facade(gs), log_ref)
	return c

# ── DebugLog ────────────────────────────────────────────────────────────────────

func test_log_append_and_format() -> void:
	var dlog = DebugLog.new()
	dlog.append("turn", "hello", 3)
	dlog.append("combat", "boom")
	assert_eq(dlog.lines().size(), 2, "two entries recorded")
	var text: String = dlog.formatted(0)
	assert_true(text.find("hello") != -1, "formatted text includes the message")
	assert_true(text.find("T3") != -1, "turn-scoped line is tagged with its turn")

func test_log_disabled_records_nothing() -> void:
	var dlog = DebugLog.new()
	dlog.enabled = false
	dlog.append("turn", "ignored")
	assert_eq(dlog.lines().size(), 0, "a disabled dlog drops appends")

func test_log_caps_at_max_lines() -> void:
	var dlog = DebugLog.new()
	for i in range(DebugLog.MAX_LINES + 50):
		dlog.append("x", str(i))
	assert_eq(dlog.lines().size(), DebugLog.MAX_LINES, "ring buffer is capped")
	# The oldest entries are evicted first.
	assert_eq(int(dlog.lines()[0].get("text", "-1")), 50, "oldest lines dropped")

func test_log_emits_appended_signal() -> void:
	var dlog = DebugLog.new()
	watch_signals(dlog)
	dlog.append("turn", "ping")
	assert_signal_emitted(dlog, "appended", "appended fires on each entry")

func test_clear_empties_log() -> void:
	var dlog = DebugLog.new()
	dlog.append("a", "1")
	dlog.clear()
	assert_eq(dlog.lines().size(), 0, "clear empties the buffer")

# ── DebugConsole: read commands ──────────────────────────────────────────────────

func test_help_lists_commands() -> void:
	var gs = make_gs(2)
	var c = make_console(gs)
	var out: String = c.execute("help")
	assert_true(out.find("gold") != -1 and out.find("tech") != -1,
		"help enumerates the commands")

func test_state_reports_turn_and_counts() -> void:
	var gs = make_gs(2)
	gs.current_player_id = 1
	gs.turn_number = 7
	var c = make_console(gs)
	var out: String = c.execute("state")
	assert_true(out.find("turn=7") != -1, "state shows the turn number")
	assert_true(out.find("players=2") != -1, "state shows the player count")

func test_unknown_command_is_reported() -> void:
	var gs = make_gs(1)
	var c = make_console(gs)
	assert_true(c.execute("frobnicate").find("unknown command") != -1,
		"unknown commands return a helpful message")

func test_empty_line_is_noop() -> void:
	var gs = make_gs(1)
	var c = make_console(gs)
	assert_eq(c.execute("   "), "", "blank input does nothing")

# ── DebugConsole: value modification ─────────────────────────────────────────────

func test_gold_sets_treasury() -> void:
	var gs = make_gs(2)
	var c = make_console(gs)
	c.execute("gold 1 999")
	assert_eq(gs.get_player(1).treasury, 999, "gold sets the treasury absolutely")

func test_addgold_adds_to_treasury() -> void:
	var gs = make_gs(2)
	gs.get_player(1).treasury = 100
	var c = make_console(gs)
	c.execute("addgold 1 50")
	assert_eq(gs.get_player(1).treasury, 150, "addgold accumulates")

func test_gold_rejects_unknown_player() -> void:
	var gs = make_gs(1)
	var c = make_console(gs)
	assert_true(c.execute("gold 99 5").find("no such player") != -1,
		"unknown player id is rejected")

func test_tech_grants_known_technology() -> void:
	var gs = make_gs(1)
	var c = make_console(gs)
	var tech_id: String = gs.db.technologies.keys()[0]
	c.execute("tech 1 " + tech_id)
	assert_true(gs.get_player(1).has_tech(tech_id), "the tech is granted")

func test_tech_rejects_unknown_technology() -> void:
	var gs = make_gs(1)
	var c = make_console(gs)
	assert_true(c.execute("tech 1 not_a_real_tech").find("no such tech") != -1,
		"a bogus tech id is rejected")

func test_pop_sets_population_with_floor() -> void:
	var gs = make_gs(1)
	var s = make_settlement(gs, 1, 5, 5, 1)
	var c = make_console(gs)
	c.execute("pop " + str(s.id) + " 8")
	assert_eq(s.population, 8, "pop sets the population")
	c.execute("pop " + str(s.id) + " 0")
	assert_eq(s.population, 1, "population is floored at 1")

func test_heal_restores_unit_health() -> void:
	var gs = make_gs(1)
	var u = make_warrior(gs, 1, 2, 2)
	u.health = 12
	var c = make_console(gs)
	c.execute("heal " + str(u.id))
	assert_eq(u.health, 100, "heal restores full health")

func test_heal_all_heals_current_player_units() -> void:
	var gs = make_gs(2)
	gs.current_player_id = 1
	var u1 = make_warrior(gs, 1, 1, 1); u1.health = 30
	var u2 = make_warrior(gs, 1, 2, 2); u2.health = 40
	var enemy = make_warrior(gs, 2, 3, 3); enemy.health = 50
	var c = make_console(gs)
	c.execute("heal all")
	assert_eq(u1.health, 100, "own unit healed")
	assert_eq(u2.health, 100, "own unit healed")
	assert_eq(enemy.health, 50, "enemy units untouched")

func test_kill_removes_unit() -> void:
	var gs = make_gs(1)
	var u = make_warrior(gs, 1, 4, 4)
	var c = make_console(gs)
	c.execute("kill " + str(u.id))
	assert_null(gs.get_unit(u.id), "the unit is removed")

func test_setturn_sets_counter() -> void:
	var gs = make_gs(1)
	var c = make_console(gs)
	c.execute("setturn 42")
	assert_eq(gs.turn_number, 42, "setturn updates the turn counter")

func test_win_forces_winning_alliance() -> void:
	var gs = make_gs(2)
	var c = make_console(gs)
	c.execute("win 2")
	assert_eq(gs.winning_alliance_id, 2, "win forces the winning alliance")

func test_war_and_peace_route_through_facade() -> void:
	var gs = make_gs(2)
	gs.current_player_id = 1
	var c = make_console(gs)
	c.execute("war 1 2")
	assert_true(gs.are_at_war(1, 2), "war declares against the target alliance")
	c.execute("peace 1 2")
	assert_false(gs.are_at_war(1, 2), "peace ends the war")

func test_hash_matches_facade_state_hash() -> void:
	var gs = make_gs(1)
	var f = dbg_facade(gs)
	var c = DebugConsole.new()
	c.init(f, null)
	var out: String = c.execute("hash")
	assert_true(out.find(str(f.state_hash())) != -1,
		"hash command reports the facade's determinism hash")

# ── DebugConsole + DebugLog integration ──────────────────────────────────────────

func test_execute_echoes_command_into_log() -> void:
	var gs = make_gs(1)
	var dlog = DebugLog.new()
	var c = make_console(gs, dlog)
	c.execute("state")
	var text: String = dlog.formatted(0)
	assert_true(text.find("> state") != -1, "the command line is echoed into the dlog")

func test_log_command_reads_buffer() -> void:
	var gs = make_gs(1)
	var dlog = DebugLog.new()
	dlog.append("seed", "marker-line")
	var c = make_console(gs, dlog)
	assert_true(c.execute("log 10").find("marker-line") != -1,
		"the log command surfaces buffered lines")
