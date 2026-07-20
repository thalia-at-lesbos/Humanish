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

# SetupScreen new-game gating: Start is blocked until every player has chosen a
# society, and an error is shown.

var _started = false
var _started_facade = null
func _on_start(facade, _db) -> void:
	_started = true
	_started_facade = facade

func test_blocks_start_until_every_player_picks_a_society() -> void:
	var screen = load("res://scenes/setup/setup_screen.gd").new()
	screen.anchor_right = 1.0
	screen.anchor_bottom = 1.0
	add_child_autofree(screen)
	screen.init(make_db(), funcref(self, "_on_start"))
	_started = false

	# Explicitly set 2 players for this test.
	screen._player_count_spin.value = 2
	# Leave player 1 at "— No Society —" (index 0).
	screen._player_rows[0]["society_btn"].select(0)
	screen._player_rows[1]["society_btn"].select(1)
	assert_eq(screen._players_missing_society(2), [1],
		"Player 1 should be flagged as missing a society")

	screen._on_start_pressed()
	assert_false(_started, "Start must be blocked while any player has no society")
	assert_true(screen._error_label.visible, "An error message should be shown")

	# Give player 1 a society too → start should now proceed.
	screen._player_rows[0]["society_btn"].select(1)
	assert_eq(screen._players_missing_society(2), [],
		"No players should be missing a society now")
	screen._on_start_pressed()
	assert_true(_started, "Start proceeds once all players have chosen a society")

func _visible_row_count(screen) -> int:
	var n: int = 0
	for r in screen._player_rows:
		if r["row"].visible:
			n += 1
	return n

func test_initial_player_count_matches_visible_rows_on_open() -> void:
	# Regression: on open the SpinBox must already show the default count for the
	# initial world size (standard = 6), and exactly that many player rows must be
	# visible — without the user touching anything first.
	var screen = load("res://scenes/setup/setup_screen.gd").new()
	screen.anchor_right = 1.0
	screen.anchor_bottom = 1.0
	add_child_autofree(screen)
	screen.init(make_db(), funcref(self, "_on_start"))

	var default_count = int(make_db().get_world_size("standard").get("players_suggested", 4))
	assert_eq(int(screen._player_count_spin.value), default_count,
		"SpinBox shows the standard world-size default on open")
	assert_eq(screen._player_count_spin.get_line_edit().text, str(default_count),
		"SpinBox text field displays the default immediately (not blank until clicked)")
	assert_eq(_visible_row_count(screen), default_count,
		"Visible player rows match the default count on open")
	assert_false(screen._player_count_user_set,
		"Applying the default must not flag the count as user-set")

func test_world_size_change_updates_count_and_rows_until_user_override() -> void:
	var screen = load("res://scenes/setup/setup_screen.gd").new()
	screen.anchor_right = 1.0
	screen.anchor_bottom = 1.0
	add_child_autofree(screen)
	screen.init(make_db(), funcref(self, "_on_start"))

	# Switch to a world size with a different suggested count; both the value and
	# the visible rows should follow.
	var duel_idx = screen._world_size_ids.find("duel")
	assert_true(duel_idx >= 0, "duel world size exists")
	screen._on_world_size_changed(duel_idx)
	var duel_count = int(make_db().get_world_size("duel").get("players_suggested", 2))
	assert_eq(int(screen._player_count_spin.value), duel_count,
		"World-size change updates the player count")
	assert_eq(_visible_row_count(screen), duel_count,
		"World-size change updates the visible rows")

	# Once the user sets the count manually, a later world-size change must not
	# override their choice.
	screen._player_count_spin.value = 5
	assert_true(screen._player_count_user_set, "Manual edit flags user-set")
	var huge_idx = screen._world_size_ids.find("huge")
	screen._on_world_size_changed(huge_idx)
	assert_eq(int(screen._player_count_spin.value), 5,
		"User-chosen count is preserved across world-size changes")
	assert_eq(_visible_row_count(screen), 5,
		"Visible rows still match the user-chosen count")

func test_leader_picker_populates_and_flows_chosen_leader() -> void:
	var screen = load("res://scenes/setup/setup_screen.gd").new()
	screen.anchor_right = 1.0
	screen.anchor_bottom = 1.0
	add_child_autofree(screen)
	screen.init(make_db(), funcref(self, "_on_start"))
	_started = false
	_started_facade = null
	screen._player_count_spin.value = 2

	var db = make_db()
	# Greek has two leaders (alexander = society default, plus pericles).
	var greek_pos = screen._player_rows[0]["society_ids"].find("greek")
	assert_true(greek_pos >= 0, "greek society exists")
	# select() does not emit item_selected, so drive the handler as the UI would.
	screen._player_rows[0]["society_btn"].select(greek_pos + 1)  # +1 for No Society
	screen._populate_leaders(0)

	var leader_ids = screen._player_rows[0]["leader_ids"]
	assert_true("alexander" in leader_ids and "pericles" in leader_ids,
		"Greek leader picker lists the faction's leaders")
	assert_eq(leader_ids[screen._player_rows[0]["leader_btn"].selected], "alexander",
		"Leader picker defaults to the society's own leader")

	# Choose the non-default leader.
	screen._player_rows[0]["leader_btn"].select(leader_ids.find("pericles"))
	# Player 2 just needs any society so Start proceeds.
	screen._player_rows[1]["society_btn"].select(1)

	screen._on_start_pressed()
	assert_true(_started, "Start proceeds with a valid setup")
	var p1 = _started_facade.get_state().get_player(1)
	assert_eq(p1.leader_id, "pericles", "Chosen leader flows into the player")
	assert_eq(p1.traits, db.get_leader("pericles").get("traits"),
		"Player receives the chosen leader's traits, not the society default")

func test_society_default_leader_used_when_picker_untouched() -> void:
	# Regression: selecting only a society (no leader interaction) preserves the
	# old behaviour — the society's default leader and traits.
	var screen = load("res://scenes/setup/setup_screen.gd").new()
	screen.anchor_right = 1.0
	screen.anchor_bottom = 1.0
	add_child_autofree(screen)
	screen.init(make_db(), funcref(self, "_on_start"))
	_started = false
	_started_facade = null
	screen._player_count_spin.value = 2
	screen._player_rows[0]["society_btn"].select(1)
	screen._player_rows[1]["society_btn"].select(1)

	screen._on_start_pressed()
	assert_true(_started, "Start proceeds")
	var db = make_db()
	var sid = screen._player_rows[0]["society_ids"][0]
	var p1 = _started_facade.get_state().get_player(1)
	assert_eq(p1.leader_id, db.get_society(sid).get("leader_id"),
		"Untouched picker yields the society's default leader")

func test_ai_toggle_flows_into_player_is_ai() -> void:
	var screen = load("res://scenes/setup/setup_screen.gd").new()
	screen.anchor_right = 1.0
	screen.anchor_bottom = 1.0
	add_child_autofree(screen)
	screen.init(make_db(), funcref(self, "_on_start"))
	_started = false
	_started_facade = null

	# Explicitly set 2 players; both with a society so Start proceeds.
	screen._player_count_spin.value = 2
	screen._player_rows[0]["society_btn"].select(1)
	screen._player_rows[1]["society_btn"].select(1)
	# Player 1 = human, player 2 = AI (its default).
	screen._player_rows[0]["ai_check"].pressed = false
	screen._player_rows[1]["ai_check"].pressed = true

	screen._on_start_pressed()
	assert_true(_started, "Start should proceed")
	var gs = _started_facade.get_state()
	assert_false(gs.get_player(1).is_ai, "Player 1 is human")
	assert_true(gs.get_player(2).is_ai, "Player 2 is AI")

	# Player 1 opens with exactly a settler + tech-derived escort (game-data.md §3).
	var sid = screen._player_rows[0]["society_ids"][0]
	var techs = make_db().get_society(sid).get("starting_techs", [])
	var escort = "scout" if "hunting" in techs else "warrior"
	var p1_types = []
	for u in gs.units:
		if u.owner_player_id == gs.get_player(1).id:
			p1_types.append(u.unit_type_id)
	p1_types.sort()
	var expected = ["settler", escort]; expected.sort()
	assert_eq(p1_types, expected,
		"Player 1 (society %s) starts with settler + %s" % [sid, escort])

func test_form_hosted_in_scroll_container() -> void:
	# Regression: the form overflows the window once many players are added, so it
	# must be hosted in a ScrollContainer or the lower options and Start button slide
	# off-screen with no way to reach them.
	var screen = load("res://scenes/setup/setup_screen.gd").new()
	screen.anchor_right = 1.0
	screen.anchor_bottom = 1.0
	add_child_autofree(screen)
	screen.init(make_db(), funcref(self, "_on_start"))
	var has_scroll := false
	for c in screen.get_children():
		if c is ScrollContainer:
			has_scroll = true
	assert_true(has_scroll, "The setup form is hosted in a ScrollContainer")
